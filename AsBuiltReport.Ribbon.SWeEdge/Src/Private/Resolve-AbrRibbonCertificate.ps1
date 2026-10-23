function Resolve-AbrRibbonCertificate {
    <#
    .SYNOPSIS
        Resolves the certificates and TLS profiles of a Ribbon SBC.
    .DESCRIPTION
        Certificate rows carry both metadata and the certificate itself. The PEM content runs
        to several kilobytes of base64 and is never returned, along with the key identifier
        and the encrypted password.

        Validity dates are stored as Unix epoch seconds and are converted here so that expiry
        can be reported and health checked.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with Certificate and TlsProfile.
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        CertFileType distinguishes a user supplied certificate from the Ribbon default and
        from trusted roots, which matters when judging whether an expiry is actionable.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonCertificate -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml
    $Now = Get-Date

    $CertificateNode = @(
        $Xml.Configuration.SelectNodes("Token[@name='System']/Token[@name='Certificates']/ID")
        $Xml.Configuration.SelectNodes("Token[@name='System']/Token[@name='SupplementCertificates']/ID")
    )

    $Certificate = foreach ($Row in @($CertificateNode | ConvertFrom-AbrRibbonIeNode)) {

        $NotBefore = $null
        $NotAfter = $null
        $Epoch = 0

        if ([Int64]::TryParse([String]$Row.CertStartDateEpoch, [ref]$Epoch) -and $Epoch -gt 0) {
            $NotBefore = [DateTimeOffset]::FromUnixTimeSeconds($Epoch).LocalDateTime
        }
        if ([Int64]::TryParse([String]$Row.CertEndDateEpoch, [ref]$Epoch) -and $Epoch -gt 0) {
            $NotAfter = [DateTimeOffset]::FromUnixTimeSeconds($Epoch).LocalDateTime
        }

        [PSCustomObject]@{
            ID              = $Row.ID
            CommonName      = $Row.CertCommonName
            SubjectAltName  = $Row.CertExtendedSubjectAltName
            Issuer          = $Row.CertIssuerName
            Subject         = $Row.CertSubjectName
            SerialNumber    = $Row.CertSerialNumber
            SignatureAlgo   = $Row.CertSignatureAlgo
            VerifyStatus    = $Row.CertVerifyStatus
            NotBefore       = $NotBefore
            NotAfter        = $NotAfter
            DaysRemaining   = if ($NotAfter) { [Math]::Floor(($NotAfter - $Now).TotalDays) } else { $null }
            Type            = switch ([String]$Row.CertFileType) {
                '1' { 'SBC Certificate' }
                '3' { 'Trusted Root' }
                '4' { 'Ribbon Default' }
                '5' { 'Supplementary' }
                default { "Unknown ($($Row.CertFileType))" }
            }
            # CertFileContent, CertKeyId and EncryptedPassword are deliberately not carried.
        }
    }

    $TlsProfile = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='Security']/Token[@name='TLSProfile']/ID") | ConvertFrom-AbrRibbonIeNode)) {
        [PSCustomObject]@{
            ID              = $Row.ID
            Description     = $Row.Description
            State           = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            TlsVersion      = switch ([String]$Row.TLSVersion) {
                '0' { 'TLS 1.2 Only' }
                '1' { 'TLS 1.0 Only' }
                '2' { 'TLS 1.0-1.2' }
                '3' { 'TLS 1.0-1.3' }
                '4' { 'TLS 1.2-1.3' }
                '5' { 'TLS 1.3 Only' }
                default { "Unknown ($($Row.TLSVersion))" }
            }
            MutualAuth      = if ($Row.MutualAuth -eq '1') { 'Enabled' } else { 'Disabled' }
            VerifyPeer      = if ($Row.VerifyPeersCertificate -eq '1') { 'Enabled' } else { 'Disabled' }
            ValidateServer  = if ($Row.ValidateServerFQDN -eq '1') { 'Enabled' } else { 'Disabled' }
            ValidateClient  = if ($Row.ValidateClientFQDN -eq '1') { 'Enabled' } else { 'Disabled' }
            OcspStapling    = if ($Row.OCSPStapling -eq '1') { 'Enabled' } else { 'Disabled' }
            # Cipher order is a comma separated list, not a base64 sequence.
            CipherCount     = @(($Row.ServerCipherSequence -split ',') | Where-Object { $_ }).Count
            ClientCertId    = $Row.ClientCertificate
            ServerCertId    = $Row.ServerCertificate
        }
    }

    [PSCustomObject]@{
        Certificate = @($Certificate)
        TlsProfile  = @($TlsProfile)
    }
}
