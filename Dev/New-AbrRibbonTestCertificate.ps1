<#
.SYNOPSIS
    Generates a throwaway certificate chain for loading into a lab SBC.
.DESCRIPTION
    Produces the two files a Ribbon SBC actually needs, which is the thing most quick
    certificate generators get wrong. A lone self signed certificate will not import cleanly,
    because the appliance wants the issuing authority in its trusted store before it will
    accept the certificate that authority signed.

    Two files are written:

    - <name>-root-ca.cer, a PEM encoded root certificate. Import this first, under
      Settings > Security > SBC Certificates > Trusted CA Certificates.
    - <name>.pfx, a PKCS#12 bundle holding the appliance certificate and its private key.
      Import this second, under Settings > Security > SBC Certificates > SBC Primary
      Certificate, choosing the PKCS12 option and supplying the password.

    Both certificates are generated in the current user's certificate store, exported, and
    then removed from the store again, so nothing is left behind on the machine.

    Intended for building sanitised sample configurations and for lab use. These certificates
    are signed by an authority that nothing trusts, so they prove nothing about identity.
.PARAMETER Domain
    The domain the certificate is issued for. Defaults to a documentation domain.
.PARAMETER DnsName
    Subject alternative names. Defaults to the host name and domain used by the sample
    configurations, so a generated certificate matches what samples.md documents. Teams Direct
    Routing matches on the subject alternative name, so the appliance FQDN must appear here.
.PARAMETER Organisation
    Organisation name placed in the subject of both certificates.
.PARAMETER Password
    Password protecting the PKCS#12 file. Prompted for if not supplied.
.PARAMETER ValidityDays
    How long the appliance certificate is valid for. Set this low to produce a certificate
    that exercises the certificate expiry health check.
.PARAMETER OutputPath
    Folder to write the files to. Defaults to Dev\output\certificates.
.PARAMETER KeepInStore
    Leave the generated certificates in the current user's personal store instead of removing
    them after export.
.EXAMPLE
    PS C:\> .\Dev\New-AbrRibbonTestCertificate.ps1

    Generates a chain for contoso.com valid for two years.
.EXAMPLE
    PS C:\> .\Dev\New-AbrRibbonTestCertificate.ps1 -ValidityDays 20

    Generates a certificate expiring in twenty days, which triggers the certificate expiry
    health check at its default sixty day warning threshold.
.NOTES
    Version:    0.1.0
    Author:     James Arber
.LINK
    https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [String] $Domain = 'contoso.com',

    [Parameter(Mandatory = $false)]
    [String[]] $DnsName,

    [Parameter(Mandatory = $false)]
    [String] $Organisation = 'Contoso',

    [Parameter(Mandatory = $false)]
    [SecureString] $Password,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 7300)]
    [Int] $ValidityDays = 730,

    [Parameter(Mandatory = $false)]
    [String] $OutputPath,

    [Parameter(Mandatory = $false)]
    [Switch] $KeepInStore
)

$ErrorActionPreference = 'Stop'

if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot 'output\certificates'
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# The appliance FQDN has to be present as a subject alternative name. Modern clients ignore
# the common name entirely, and Teams Direct Routing matches the SAN.
#
# sbc1 rather than sbc, to match the naming convention documented in Dev\Samples\samples.md.
# Keeping every sample on one host name makes them interchangeable during validation.
if (-not $DnsName) {
    $DnsName = @("sbc1.$Domain", $Domain)
}

if (-not $Password) {
    # Read directly as a SecureString. Never build one from plaintext: it is an Error level
    # PSScriptAnalyzer finding and this repository fails its build on errors.
    $Password = Read-Host -Prompt 'Password to protect the .pfx file' -AsSecureString
}

if ($Password.Length -eq 0) {
    throw 'A password is required. Ribbon will not import a PKCS#12 file without one.'
}

$Store = 'Cert:\CurrentUser\My'
$Generated = @()

try {
    #region Root authority
    # pathlength=0 means this authority may only sign end entity certificates, not further
    # authorities. That is all a lab chain needs and it keeps the certificate honest.
    Write-Host "Creating root authority for $Domain" -ForegroundColor Cyan

    $RootParams = @{
        Subject           = "CN=$Organisation Test Root CA, O=$Organisation"
        KeyExportPolicy   = 'Exportable'
        KeyUsage          = 'CertSign', 'CRLSign', 'DigitalSignature'
        KeyAlgorithm      = 'RSA'
        KeyLength         = 2048
        HashAlgorithm     = 'SHA256'
        CertStoreLocation = $Store
        TextExtension     = @('2.5.29.19={text}CA=true&pathlength=0')

        # The authority must outlive anything it signs, or the chain fails validation before
        # the certificate itself expires.
        NotAfter          = (Get-Date).AddDays($ValidityDays + 365)
    }

    $Root = New-SelfSignedCertificate @RootParams
    $Generated += $Root
    #endregion Root authority

    #region Appliance certificate
    Write-Host "Creating appliance certificate for $($DnsName -join ', ')" -ForegroundColor Cyan

    $LeafParams = @{
        Subject           = "CN=$($DnsName[0]), O=$Organisation"
        DnsName           = $DnsName
        Signer            = $Root
        KeyExportPolicy   = 'Exportable'
        KeyUsage          = 'DigitalSignature', 'KeyEncipherment'
        KeyAlgorithm      = 'RSA'
        KeyLength         = 2048
        HashAlgorithm     = 'SHA256'
        CertStoreLocation = $Store

        # Server and client authentication. A trunk doing mutual TLS presents its certificate
        # as a client as well as a server, so both usages are required.
        TextExtension     = @('2.5.29.37={text}1.3.6.1.5.5.7.3.1,1.3.6.1.5.5.7.3.2')
        NotAfter          = (Get-Date).AddDays($ValidityDays)
    }

    $Leaf = New-SelfSignedCertificate @LeafParams
    $Generated += $Leaf
    #endregion Appliance certificate

    #region Export
    $Safe = ($DnsName[0] -replace '[^\w\.\-]', '_')
    $RootFile = Join-Path $OutputPath "$Safe-root-ca.cer"
    $PfxFile = Join-Path $OutputPath "$Safe.pfx"

    # PEM rather than DER. Ribbon accepts both, but a text file can be opened and checked,
    # and pasted into the WebUI where a file upload is not offered.
    $RootBytes = $Root.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $Pem = @(
        '-----BEGIN CERTIFICATE-----'
        [Convert]::ToBase64String($RootBytes, [Base64FormattingOptions]::InsertLineBreaks)
        '-----END CERTIFICATE-----'
    ) -join "`n"

    Set-Content -Path $RootFile -Value $Pem -Encoding Ascii

    # End entity only. The root is imported separately as a trusted authority, which is the
    # order the appliance expects, and it keeps the two concerns visibly separate.
    Export-PfxCertificate -Cert $Leaf -FilePath $PfxFile -Password $Password -ChainOption EndEntityCertOnly | Out-Null
    #endregion Export

    Write-Host ''
    Write-Host 'Import into the SBC in this order:' -ForegroundColor Green
    Write-Host "  1. Trusted CA Certificates   <- $RootFile"
    Write-Host "  2. SBC Primary Certificate   <- $PfxFile (PKCS12, with the password above)"
    Write-Host ''
    Write-Host ("Appliance certificate expires {0} ({1} days)" -f $Leaf.NotAfter.ToString('yyyy-MM-dd'), $ValidityDays)
    Write-Host ("Subject alternative names: {0}" -f ($DnsName -join ', '))

    [PSCustomObject]@{
        RootCertificate     = $RootFile
        ApplianceCertificate = $PfxFile
        Subject             = $Leaf.Subject
        NotAfter            = $Leaf.NotAfter
        Thumbprint          = $Leaf.Thumbprint
    }
} finally {
    # Generated in the personal store because that is the only way to create them, but there
    # is no reason to leave a fake authority sitting in it afterwards.
    if (-not $KeepInStore) {
        foreach ($Certificate in $Generated) {
            Remove-Item -Path (Join-Path $Store $Certificate.Thumbprint) -Force -ErrorAction SilentlyContinue
        }
    }
}
