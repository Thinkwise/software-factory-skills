# Creates a local root CA plus a localhost TLS certificate signed by it, trusts
# the CA machine-wide, and binds the certificate to HTTPS on the IIS site that
# hosts the Indicium application. A CA-issued leaf is needed because
# Electron/BoringSSL (and Chromium) reject a bare self-signed leaf as its own
# trust anchor. Re-running rotates both certificates. Must run elevated.
param(
    [string]$OutDir = $PSScriptRoot,
    [string]$AppPath = '/indicium',
    [int]$Port = 443
)
$ErrorActionPreference = 'Stop'
$caSubject = 'CN=Indicium Local Dev CA'
$leafName = 'Indicium localhost'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Start-Transcript -Path (Join-Path $OutDir 'New-LocalhostCert.log') -Force | Out-Null
try {
    # 0. Remove certificates created by earlier runs of this script
    Get-ChildItem Cert:\LocalMachine\My, Cert:\LocalMachine\Root | Where-Object {
        $_.Subject -eq $caSubject -or $_.FriendlyName -eq $leafName
    } | ForEach-Object {
        Write-Host "Removing old $($_.Subject) $($_.Thumbprint) from $($_.PSParentPath -replace '.*::')"
        Remove-Item $_.PSPath -DeleteKey
    }

    # 1. Root CA (private key is deleted again after signing the leaf)
    $ca = New-SelfSignedCertificate `
        -Subject $caSubject `
        -FriendlyName 'Indicium Local Dev CA' `
        -KeyUsage CertSign, CRLSign, DigitalSignature `
        -TextExtension @('2.5.29.19={critical}{text}ca=1&pathlength=0') `
        -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
        -NotAfter (Get-Date).AddYears(10) `
        -CertStoreLocation 'Cert:\LocalMachine\My'

    # 2. Leaf for localhost, loopback IPs and the machine name
    $san = "2.5.29.17={text}DNS=localhost&DNS=$($env:COMPUTERNAME)&IPAddress=127.0.0.1&IPAddress=::1"
    $leaf = New-SelfSignedCertificate `
        -Subject 'CN=localhost' `
        -FriendlyName $leafName `
        -Signer $ca `
        -KeyUsage DigitalSignature, KeyEncipherment `
        -TextExtension @($san, '2.5.29.37={text}1.3.6.1.5.5.7.3.1', '2.5.29.19={critical}{text}ca=0') `
        -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 `
        -KeyExportPolicy Exportable `
        -NotAfter (Get-Date).AddYears(5) `
        -CertStoreLocation 'Cert:\LocalMachine\My'
    Write-Host "Created CA $($ca.Thumbprint) and leaf $($leaf.Thumbprint)"

    # 3. Trust the CA (public part only) and export it for Node/Electron
    $cerPath = Join-Path $OutDir 'localhost-ca.cer'
    $pemPath = Join-Path $OutDir 'localhost.pem'
    Export-Certificate -Cert $ca -FilePath $cerPath -Force | Out-Null
    $b64 = [Convert]::ToBase64String($ca.RawData, 'InsertLineBreaks')
    Set-Content -Path $pemPath -Value "-----BEGIN CERTIFICATE-----`r`n$b64`r`n-----END CERTIFICATE-----" -Encoding Ascii
    Import-Certificate -FilePath $cerPath -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null
    Remove-Item $ca.PSPath -DeleteKey
    Write-Host "Trusted CA in LocalMachine\Root; exported $cerPath and $pemPath; CA private key deleted"

    # 4. HTTPS binding on the IIS site that hosts the Indicium application
    Import-Module WebAdministration
    $site = Get-ChildItem IIS:\Sites | Where-Object {
        Get-WebApplication -Site $_.Name | Where-Object { $_.Path -eq $AppPath }
    } | Select-Object -First 1
    if (-not $site) { $site = Get-Item 'IIS:\Sites\Default Web Site' }
    Write-Host "Using IIS site '$($site.Name)'"

    if (-not (Get-WebBinding -Name $site.Name -Protocol https -Port $Port)) {
        New-WebBinding -Name $site.Name -Protocol https -Port $Port -IPAddress '*'
    }
    $binding = Get-WebBinding -Name $site.Name -Protocol https -Port $Port
    try { $binding.RemoveSslCertificate() } catch { }
    $binding.AddSslCertificate($leaf.Thumbprint, 'My')
    Write-Host "Bound certificate to https://*:$Port on '$($site.Name)'"
    Write-Host "Next: set NODE_EXTRA_CA_CERTS to $pemPath for Node/Electron clients and restart them."
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Stop-Transcript | Out-Null
}
