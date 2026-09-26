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

$archivePath = "C:\BlackglassArchive"
New-Item -ItemType Directory -Path $archivePath -Force | Out-Null
Set-Content -LiteralPath "$archivePath\flag4.txt" -Value $FLAG4 -Encoding ASCII

$serviceNote = @"
ARCHIVE INDEX SERVICE HANDOFF

The archive index still runs under BLACKGLASS\svc_sql.
Deployment automation was delegated to BLACKGLASS\svc_deploy.
Review directory object control before the next Tier0 Support roster change.
"@
Set-Content -LiteralPath "$archivePath\service-handoff.txt" -Value $serviceNote -Encoding UTF8

if (Get-SmbShare -Name "Archive$" -ErrorAction SilentlyContinue) {
    Remove-SmbShare -Name "Archive$" -Force
}

$shareParameters = @{
    Name = "Archive$"
    Path = $archivePath
    ReadAccess = "BLACKGLASS\svc_sql"
    FullAccess = "BUILTIN\Administrators"
}
New-SmbShare @shareParameters | Out-Null

& icacls.exe $archivePath /inheritance:r | Out-Null
& icacls.exe $archivePath /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" "BLACKGLASS\svc_sql:(OI)(CI)R" | Out-Null

Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force | Out-Null
Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"

if (-not (Get-NetFirewallRule -DisplayName "Blackglass Corp SMB" -ErrorAction SilentlyContinue)) {
    $firewallParameters = @{
        DisplayName = "Blackglass Corp SMB"
        Direction = "Inbound"
        Action = "Allow"
        Protocol = "TCP"
        LocalPort = 445
        RemoteAddress = "10.60.20.0/24"
    }
    New-NetFirewallRule @firewallParameters | Out-Null
}

$localVagrant = Get-LocalUser -Name "vagrant" -ErrorAction SilentlyContinue
if ($localVagrant) {
    $managementPassword = ConvertTo-SecureString $MGMT_PASSWORD -AsPlainText -Force
    Set-LocalUser -Name "vagrant" -Password $managementPassword
}

Remove-Item -LiteralPath $secretsPath -Force
Set-Content -LiteralPath "C:\blackglass-ready.txt" -Value "file01 ready"
Write-Host "file01 configuration complete"
