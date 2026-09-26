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

$featureParameters = @{
    Online = $true
    FeatureName = "IIS-WebServerRole"
    All = $true
    NoRestart = $true
}
Enable-WindowsOptionalFeature @featureParameters | Out-Null

$webRoot = "C:\inetpub\wwwroot"
$archivePath = Join-Path $webRoot "archive"
New-Item -ItemType Directory -Path $archivePath -Force | Out-Null

$indexPage = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Blackglass Employee Communications</title>
  <style>
    body { background:#111722; color:#e0e7ef; font-family:Segoe UI,sans-serif; }
    main { max-width:800px; margin:8vh auto; padding:2rem; border:1px solid #3e5065; }
    h1 { color:#95d5ff; }
  </style>
</head>
<body><main>
  <h1>Blackglass Employee Communications</h1>
  <p>Reflecting tomorrow since 1998.</p>
  <p>The 2026 archive-index modernization is now in production.</p>
  <p>Legacy notices have been removed from navigation but remain retained for compliance.</p>
</main></body></html>
"@
Set-Content -LiteralPath (Join-Path $webRoot "index.html") -Value $indexPage -Encoding UTF8

$robotsText = @"
User-agent: *
Disallow: /archive/credential-standard.html
"@
Set-Content -LiteralPath (Join-Path $webRoot "robots.txt") -Value $robotsText -Encoding ASCII

$policyPage = @"
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>Retired Credential Standard</title></head>
<body>
  <h1>Retired Service Credential Standard</h1>
  <p>This notice remains for migration reference only.</p>
  <p>Legacy archive services used the product name, four-digit rollout year,
  and an exclamation mark. The 2026 migration must replace that convention.</p>
</body></html>
"@
Set-Content -LiteralPath (Join-Path $archivePath "credential-standard.html") -Value $policyPage -Encoding UTF8

if (-not (Get-NetFirewallRule -DisplayName "Blackglass Corp Portal" -ErrorAction SilentlyContinue)) {
    $firewallParameters = @{
        DisplayName = "Blackglass Corp Portal"
        Direction = "Inbound"
        Action = "Allow"
        Protocol = "TCP"
        LocalPort = 80
        RemoteAddress = "10.60.20.0/24"
    }
    New-NetFirewallRule @firewallParameters | Out-Null
}

Start-Service W3SVC
Set-Service W3SVC -StartupType Automatic

$localVagrant = Get-LocalUser -Name "vagrant" -ErrorAction SilentlyContinue
if ($localVagrant) {
    $managementPassword = ConvertTo-SecureString $MGMT_PASSWORD -AsPlainText -Force
    Set-LocalUser -Name "vagrant" -Password $managementPassword
}

Remove-Item -LiteralPath $secretsPath -Force
Set-Content -LiteralPath "C:\blackglass-ready.txt" -Value "ws01 ready"
Write-Host "ws01 configuration complete"
