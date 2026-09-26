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

$secretsPath = "C:\Windows\Temp\bg-dc.env"
if (-not (Test-Path -LiteralPath $secretsPath)) {
    throw "Missing domain controller secrets file."
}

Import-EnvFile -Path $secretsPath

$computerSystem = Get-CimInstance Win32_ComputerSystem
if ($computerSystem.DomainRole -ge 4) {
    Write-Host "dc01 is already a domain controller."
    exit 0
}

$corpAddress = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -eq "10.60.20.10" } |
    Select-Object -First 1

if (-not $corpAddress) {
    throw "The corporate interface address 10.60.20.10 is unavailable."
}

Set-DnsClientServerAddress -InterfaceIndex $corpAddress.InterfaceIndex -ServerAddresses "127.0.0.1"
Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null

$postPromoteScript = @'
$ErrorActionPreference = "SilentlyContinue"
Import-Module ActiveDirectory

for ($attempt = 0; $attempt -lt 120; $attempt++) {
    try {
        Get-ADDomain | Out-Null
        break
    }
    catch {
        Start-Sleep -Seconds 5
    }
}

$password = ConvertTo-SecureString "vagrant" -AsPlainText -Force
if (-not (Get-ADUser -Filter "SamAccountName -eq 'vagrant'" -ErrorAction SilentlyContinue)) {
    $userParameters = @{
        Name = "Vagrant Provisioner"
        SamAccountName = "vagrant"
        UserPrincipalName = "vagrant@BLACKGLASS.LAB"
        AccountPassword = $password
        Enabled = $true
        PasswordNeverExpires = $true
    }
    New-ADUser @userParameters
}

Add-ADGroupMember -Identity "Domain Admins" -Members "vagrant" -ErrorAction SilentlyContinue
Enable-PSRemoting -Force
Set-Content -LiteralPath "C:\bg-postpromote.ready" -Value "ready"
Unregister-ScheduledTask -TaskName "Blackglass-PostPromote" -Confirm:$false -ErrorAction SilentlyContinue
'@

Set-Content -LiteralPath "C:\Windows\Temp\bg-postpromote.ps1" -Value $postPromoteScript -Encoding UTF8

$actionParameters = @{
    Execute = "PowerShell.exe"
    Argument = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Temp\bg-postpromote.ps1"
}
$action = New-ScheduledTaskAction @actionParameters
$trigger = New-ScheduledTaskTrigger -AtStartup
$taskParameters = @{
    TaskName = "Blackglass-PostPromote"
    Action = $action
    Trigger = $trigger
    User = "SYSTEM"
    RunLevel = "Highest"
    Force = $true
}
Register-ScheduledTask @taskParameters | Out-Null

$safeModePassword = ConvertTo-SecureString $DSRM_PASSWORD -AsPlainText -Force
$forestParameters = @{
    DomainName = $DOMAIN_FQDN
    DomainNetbiosName = $DOMAIN_NETBIOS
    SafeModeAdministratorPassword = $safeModePassword
    InstallDns = $true
    NoRebootOnCompletion = $true
    Force = $true
}
Install-ADDSForest @forestParameters

Write-Host "Forest promotion completed; Vagrant will reboot dc01."
