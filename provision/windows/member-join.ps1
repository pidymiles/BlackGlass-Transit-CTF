param(
    [Parameter(Mandatory = $true)]
    [string]$ExpectedAddress
)

$ErrorActionPreference = "Stop"

function Import-EnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            continue
        }

        $name, $value = $line -split "=", 2
        Set-Variable -Scope Script -Name $name -Value $value
    }
}

$secretsPath = "C:\Windows\Temp\bg-member.env"
Import-EnvFile -Path $secretsPath

$corpAddress = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -eq $ExpectedAddress } |
    Select-Object -First 1

if (-not $corpAddress) {
    throw "The expected corporate interface address $ExpectedAddress is unavailable."
}

Set-DnsClientServerAddress -InterfaceIndex $corpAddress.InterfaceIndex -ServerAddresses "10.60.20.10"

for ($attempt = 0; $attempt -lt 120; $attempt++) {
    if (Test-NetConnection -ComputerName "10.60.20.10" -Port 389 -InformationLevel Quiet) {
        break
    }
    Start-Sleep -Seconds 5
}

if (-not (Test-NetConnection -ComputerName "10.60.20.10" -Port 389 -InformationLevel Quiet)) {
    throw "dc01 did not become reachable on LDAP."
}

$computerSystem = Get-CimInstance Win32_ComputerSystem
if ($computerSystem.PartOfDomain -and $computerSystem.Domain -ieq $DOMAIN_FQDN) {
    Write-Host "This system is already joined to $DOMAIN_FQDN."
    exit 0
}

$securePassword = ConvertTo-SecureString $DOMAIN_ADMIN_PASSWORD -AsPlainText -Force
$credential = [PSCredential]::new("$DOMAIN_NETBIOS\Administrator", $securePassword)
Add-Computer -DomainName $DOMAIN_FQDN -Credential $credential -Force

Write-Host "Domain join complete; Vagrant will reboot this member."
