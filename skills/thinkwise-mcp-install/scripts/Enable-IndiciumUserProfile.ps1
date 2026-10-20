# Enables "Load User Profile" on the IIS application pool that runs /indicium,
# so Indicium can create/read its OpenID signing certificate in the pool
# identity's Current User certificate store. Must run elevated.
param([string]$AppPath = '/indicium')
$ErrorActionPreference = 'Stop'
Import-Module WebAdministration

$app = Get-ChildItem IIS:\Sites | ForEach-Object {
    Get-WebApplication -Site $_.Name | Where-Object { $_.Path -eq $AppPath }
} | Select-Object -First 1
if (-not $app) { throw "No IIS application found at $AppPath" }
$pool = $app.applicationPool
Write-Host "Application pool: $pool"

Set-ItemProperty "IIS:\AppPools\$pool" -Name processModel.loadUserProfile -Value $true
Set-ItemProperty "IIS:\AppPools\$pool" -Name processModel.setProfileEnvironment -Value $true
Restart-WebAppPool -Name $pool
Write-Host "loadUserProfile = $((Get-Item "IIS:\AppPools\$pool").processModel.loadUserProfile); pool recycled"
