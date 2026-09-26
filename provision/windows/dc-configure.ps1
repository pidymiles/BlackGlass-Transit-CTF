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

function Ensure-OrganizationalUnit {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $existing = Get-ADOrganizationalUnit -LDAPFilter "(ou=$Name)" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $false | Out-Null
    }
}

function Ensure-DomainUser {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SamAccountName,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Description = ""
    )

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force
    $user = Get-ADUser -Filter "SamAccountName -eq '$SamAccountName'" -ErrorAction SilentlyContinue

    if (-not $user) {
        $parameters = @{
            Name = $Name
            SamAccountName = $SamAccountName
            UserPrincipalName = $UserPrincipalName
            AccountPassword = $securePassword
            Enabled = $true
            PasswordNeverExpires = $true
            Path = $Path
            Description = $Description
        }
        New-ADUser @parameters
    }
    else {
        Set-ADAccountPassword -Identity $user -Reset -NewPassword $securePassword
        Enable-ADAccount -Identity $user
        Set-ADUser -Identity $user -PasswordNeverExpires $true -Description $Description
    }
}

function Grant-GenericAll {
    param(
        [Parameter(Mandatory = $true)][System.Security.Principal.SecurityIdentifier]$TrusteeSid,
        [Parameter(Mandatory = $true)][string]$TargetDistinguishedName
    )

    $path = "AD:\$TargetDistinguishedName"
    $acl = Get-Acl -Path $path
    $rule = [System.DirectoryServices.ActiveDirectoryAccessRule]::new(
        $TrusteeSid,
        [System.DirectoryServices.ActiveDirectoryRights]::GenericAll,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    [void]$acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
}

function Grant-DcsyncRights {
    param(
        [Parameter(Mandatory = $true)][System.Security.Principal.SecurityIdentifier]$TrusteeSid,
        [Parameter(Mandatory = $true)][string]$DomainDistinguishedName
    )

    $rights = @(
        [Guid]"1131f6aa-9c07-11d1-f79f-00c04fc2dcd2",
        [Guid]"1131f6ad-9c07-11d1-f79f-00c04fc2dcd2",
        [Guid]"89e95b76-444d-4c62-991a-0facbeda640c"
    )

    $path = "AD:\$DomainDistinguishedName"
    $acl = Get-Acl -Path $path

    foreach ($rightGuid in $rights) {
        $rule = [System.DirectoryServices.ActiveDirectoryAccessRule]::new(
            $TrusteeSid,
            [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
            [System.Security.AccessControl.AccessControlType]::Allow,
            $rightGuid
        )
        [void]$acl.AddAccessRule($rule)
    }

    Set-Acl -Path $path -AclObject $acl
}

$secretsPath = "C:\Windows\Temp\bg-dc.env"
Import-EnvFile -Path $secretsPath

for ($attempt = 0; $attempt -lt 120; $attempt++) {
    if (Test-Path -LiteralPath "C:\bg-postpromote.ready") {
        break
    }
    Start-Sleep -Seconds 5
}

if (-not (Test-Path -LiteralPath "C:\bg-postpromote.ready")) {
    throw "The post-promotion bootstrap did not complete."
}

Import-Module ActiveDirectory
$domain = Get-ADDomain
$domainDn = $domain.DistinguishedName
$serviceOu = "OU=Service Accounts,$domainDn"
$staffOu = "OU=Staff,$domainDn"
$groupsOu = "OU=Security Groups,$domainDn"

Ensure-OrganizationalUnit -Name "Service Accounts" -Path $domainDn
Ensure-OrganizationalUnit -Name "Staff" -Path $domainDn
Ensure-OrganizationalUnit -Name "Security Groups" -Path $domainDn

Ensure-DomainUser -Name "Directory Audit Reader" -SamAccountName "audit.reader" -UserPrincipalName "audit.reader@blackglass.lab" -Password $AUDIT_PASSWORD -Path $serviceOu -Description "Transit inventory directory survey account"
Ensure-DomainUser -Name "Archive SQL Service" -SamAccountName "svc_sql" -UserPrincipalName "svc_sql@blackglass.lab" -Password $SQL_PASSWORD -Path $serviceOu -Description "FILE01 archive index service"
Ensure-DomainUser -Name "Deployment Automation" -SamAccountName "svc_deploy" -UserPrincipalName "svc_deploy@blackglass.lab" -Password $DEPLOY_PASSWORD -Path $serviceOu -Description "Tier-zero deployment workflow owner"
Ensure-DomainUser -Name "Morgan Vesper" -SamAccountName "m.vesper" -UserPrincipalName "m.vesper@blackglass.lab" -Password "Vesper-Aa9!LocalOnly" -Path $staffOu -Description "Infrastructure documentation coordinator"

$tierZeroGroup = Get-ADGroup -Filter "SamAccountName -eq 'Tier0Support'" -ErrorAction SilentlyContinue
if (-not $tierZeroGroup) {
    $groupParameters = @{
        Name = "Tier0 Support"
        SamAccountName = "Tier0Support"
        GroupCategory = "Security"
        GroupScope = "Global"
        Path = $groupsOu
        Description = "Emergency directory replication support"
        PassThru = $true
    }
    $tierZeroGroup = New-ADGroup @groupParameters
}

& setspn.exe -S "MSSQLSvc/file01.blackglass.lab:1433" "BLACKGLASS\svc_sql" | Out-Null
Set-ADUser -Identity "svc_sql" -Replace @{ "msDS-SupportedEncryptionTypes" = 4 }

$sqlSid = (Get-ADUser -Identity "svc_sql").SID
$deployUser = Get-ADUser -Identity "svc_deploy"
Grant-GenericAll -TrusteeSid $sqlSid -TargetDistinguishedName $deployUser.DistinguishedName

$deploySid = $deployUser.SID
$tierZeroGroup = Get-ADGroup -Identity "Tier0Support"
Grant-GenericAll -TrusteeSid $deploySid -TargetDistinguishedName $tierZeroGroup.DistinguishedName
Grant-DcsyncRights -TrusteeSid $tierZeroGroup.SID -DomainDistinguishedName $domainDn

$deploymentPath = "C:\Deployment"
New-Item -ItemType Directory -Path $deploymentPath -Force | Out-Null
$handoff = @"
BLACKGLASS DEPLOYMENT HANDOFF

The svc_deploy identity owns the Tier0 Support roster for emergency automation.
Tier0 Support retains directory replication permissions during the migration.
Membership changes are audited by the quarterly control review.
"@
Set-Content -LiteralPath "$deploymentPath\handoff.txt" -Value $handoff -Encoding UTF8

if (Get-SmbShare -Name "Deployment$" -ErrorAction SilentlyContinue) {
    Remove-SmbShare -Name "Deployment$" -Force
}

$shareParameters = @{
    Name = "Deployment$"
    Path = $deploymentPath
    ReadAccess = "BLACKGLASS\svc_deploy"
    FullAccess = "BUILTIN\Administrators"
}
New-SmbShare @shareParameters | Out-Null

& icacls.exe $deploymentPath /inheritance:r | Out-Null
& icacls.exe $deploymentPath /grant:r "SYSTEM:(OI)(CI)F" "BUILTIN\Administrators:(OI)(CI)F" "BLACKGLASS\svc_deploy:(OI)(CI)R" | Out-Null

$administratorDesktop = "C:\Users\Administrator\Desktop"
New-Item -ItemType Directory -Path $administratorDesktop -Force | Out-Null
Set-Content -LiteralPath "$administratorDesktop\flag5.txt" -Value $FLAG5 -Encoding ASCII
& icacls.exe "$administratorDesktop\flag5.txt" /inheritance:r | Out-Null
& icacls.exe "$administratorDesktop\flag5.txt" /grant:r "SYSTEM:F" "BUILTIN\Administrators:F" | Out-Null

Enable-PSRemoting -Force
if (-not (Get-NetFirewallRule -DisplayName "Blackglass Corp WinRM" -ErrorAction SilentlyContinue)) {
    $firewallParameters = @{
        DisplayName = "Blackglass Corp WinRM"
        Direction = "Inbound"
        Action = "Allow"
        Protocol = "TCP"
        LocalPort = 5985
        RemoteAddress = "10.60.20.0/24"
    }
    New-NetFirewallRule @firewallParameters | Out-Null
}

$administratorPassword = ConvertTo-SecureString $DOMAIN_ADMIN_PASSWORD -AsPlainText -Force
Set-ADAccountPassword -Identity "Administrator" -Reset -NewPassword $administratorPassword

$provisioner = Get-ADUser -Identity "vagrant" -ErrorAction SilentlyContinue
if ($provisioner) {
    Add-ADGroupMember -Identity "Domain Admins" -Members $provisioner -ErrorAction SilentlyContinue
    Set-ADUser -Identity $provisioner -Description "Isolated range lifecycle management"
    $managementPassword = ConvertTo-SecureString $MGMT_PASSWORD -AsPlainText -Force
    Set-ADAccountPassword -Identity $provisioner -Reset -NewPassword $managementPassword
}

Remove-Item -LiteralPath $secretsPath -Force
Remove-Item -LiteralPath "C:\Windows\Temp\bg-postpromote.ps1" -Force -ErrorAction SilentlyContinue
Set-Content -LiteralPath "C:\blackglass-ready.txt" -Value "dc01 ready"
Write-Host "dc01 configuration complete"
