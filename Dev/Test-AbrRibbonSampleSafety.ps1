<#
.SYNOPSIS
    Scans a sanitised configuration export for data that should not be published.
.DESCRIPTION
    Sanitising a configuration by hand is the right approach, because the appliance regenerates
    a valid export and nothing downstream can be silently corrupted. The weakness of doing it
    by hand is that a Ribbon export runs to tens of thousands of lines and a single missed
    field is easy to overlook.

    This script is the automated half of that. It walks every field of the export and reports
    anything that does not match the conventions documented in Dev\Samples\samples.md:

    - Routable IPv4 addresses that are not RFC 5737 documentation ranges or RFC 1918 private
      space. Published provider ranges, such as Microsoft Teams, are allowed because a genuine
      Teams configuration contains them.
    - Host names and domains outside the sample domain and the known provider domains.
    - Telephone numbers outside the ACMA fictitious range used by the samples.
    - Email addresses outside the sample domain.
    - Certificate and private key material.
    - Credential fields that still hold a value.
    - Local user accounts, listed in full, because a leftover administrator account is easy to
      miss and impossible to spot from a diff.
    - Any string supplied through -MustNotContain, which is how a real customer name, domain or
      number range gets checked explicitly.

    A clean result is not a guarantee. It means nothing matched the patterns, not that nothing
    was missed. Read the findings, then read the export.
.PARAMETER Path
    The sanitised configuration export to scan.
.PARAMETER MustNotContain
    Strings that must not appear anywhere in the export. Use this for the real customer name,
    domain, address ranges and number ranges the sample was built from.
.PARAMETER AllowedDomain
    Domains considered safe. Defaults to the sample domain and the published provider domains.
.PARAMETER Detailed
    List every occurrence rather than a capped sample of each finding.
.OUTPUTS
    System.Management.Automation.PSCustomObject describing each finding. Sets the exit code to
    1 when anything is found, so it can gate a publication step.
.EXAMPLE
    PS C:\> .\Dev\Test-AbrRibbonSampleSafety.ps1 -Path '.\Dev\Samples\SBC_Config_sbc1.tar'
.EXAMPLE
    PS C:\> .\Dev\Test-AbrRibbonSampleSafety.ps1 -Path '.\Dev\Samples\sbc1.tar' -MustNotContain 'contoso-real.com', 'Real Customer Pty Ltd', '203.15.'

    Checks the generic patterns and additionally fails if any of those exact strings survive.
.NOTES
    Version:    0.1.0
    Author:     James Arber
.LINK
    https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $Path,

    [Parameter(Mandatory = $false)]
    [String[]] $MustNotContain,

    [Parameter(Mandatory = $false)]
    [String[]] $AllowedDomain = @(
        'contoso.com', 'pstnhub.microsoft.com', 'localhost', 'localdomain'

        # Public certificate authorities. Their names appear in the trusted root store that
        # ships on the appliance and say nothing about who the customer was.
        'entrust.net', 'digicert.com', 'sectigo.com', 'ssl.com', 'comodoca.com'
        'usertrust.com', 'globalsign.com', 'letsencrypt.org', 'geotrust.com'
        'godaddy.com', 'amazontrust.com', 'pki.goog', 'microsoft.com', 'verisign.com'

        # Ribbon's own default certificate is issued to sales@rbbn.com. Every appliance ships
        # with it, so it identifies the vendor rather than the customer.
        'rbbn.com', 'sonus.net'
    ),

    [Parameter(Mandatory = $false)]
    [String[]] $AllowedNumber = @(
        # Carrier network service numbers. These belong to the carrier, not to any customer,
        # and appear in configurations that reference the service. 198339100 is Telstra
        # Talking SMS, which sample configurations block inbound calls from.
        '198339100'
    ),

    [Parameter(Mandatory = $false)]
    [Switch] $Detailed
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = Join-Path $RepoRoot 'AsBuiltReport.Ribbon.SWeEdge'

foreach ($Function in Get-ChildItem -Path (Join-Path $ModuleRoot 'Src\Private') -Filter '*.ps1') {
    . $Function.FullName
}

if (-not [System.IO.Path]::IsPathRooted($Path)) {
    $Path = Join-Path (Get-Location) $Path
}

$Config = Import-AbrRibbonSWeEdgeConfig -Path $Path
$Xml = $Config.RawXml

#region Field walk
# Every leaf field in the export, with a readable path built from the enclosing tokens and row
# identifiers, so a finding can be located in the WebUI rather than just reported as present.
$Field = [System.Collections.Generic.List[PSObject]]::new()

foreach ($Element in $Xml.SelectNodes('//IE')) {

    $Segment = [System.Collections.Generic.List[String]]::new()
    $Node = $Element.ParentNode
    while ($Node -and $Node.LocalName -ne 'Configuration') {
        if ($Node.LocalName -eq 'Token') {
            $Segment.Insert(0, $Node.GetAttribute('name'))
        } elseif ($Node.LocalName -eq 'ID') {
            $Segment.Insert(0, '[{0}]' -f $Node.GetAttribute('value'))
        }
        $Node = $Node.ParentNode
    }

    $Location = ($Segment -join '/')

    foreach ($Child in $Element.ChildNodes) {
        if ($Child.HasChildNodes -and $Child.FirstChild.NodeType -ne 'Text') {
            continue
        }

        $Value = [String]$Child.InnerText
        if ([String]::IsNullOrWhiteSpace($Value)) {
            continue
        }

        $Field.Add([PSCustomObject]@{
                Location = $Location
                Class    = $Element.GetAttribute('classname')
                Name     = $Child.LocalName
                Value    = $Value
            })
    }
}
#endregion Field walk

$Finding = [System.Collections.Generic.List[PSObject]]::new()

$Add = {
    param([String] $Category, [String] $Severity, [PSObject] $Source, [String] $Detail)

    $Finding.Add([PSCustomObject]@{
            Category = $Category
            Severity = $Severity
            Location = $Source.Location
            Field    = $Source.Name
            Value    = $Detail
        })
}

#region Address checks
# Fields that hold base64 or opaque data and would otherwise generate noise.
$OpaqueField = @('Sequence', 'CauseCodes', 'CertFileContent', 'SystemRelease', 'Thumbprint')

# Certificate file names are generated by the appliance and contain an import timestamp, which
# looks like both a host name and a telephone number to a pattern matcher.
$GeneratedNameField = @('CertFileName', 'CertNewFileName')

# Subsystem logger names are dotted Java package names, not host names.
$NotAHostField = @('LoggerName')

# Ranges that are safe to publish. RFC 1918 private space is fine because it says nothing about
# who the customer was. RFC 5737 is the documentation range the samples are supposed to use.
# The Microsoft ranges are published by Microsoft and appear in any genuine Teams deployment.
$SafeNetwork = @(
    @{ Name = 'RFC 1918 private'; Test = { param($o) $o[0] -eq 10 -or ($o[0] -eq 172 -and $o[1] -ge 16 -and $o[1] -le 31) -or ($o[0] -eq 192 -and $o[1] -eq 168) } }
    @{ Name = 'RFC 5737 documentation'; Test = { param($o) ($o[0] -eq 192 -and $o[1] -eq 0 -and $o[2] -eq 2) -or ($o[0] -eq 198 -and $o[1] -eq 51 -and $o[2] -eq 100) -or ($o[0] -eq 203 -and $o[1] -eq 0 -and $o[2] -eq 113) } }
    @{ Name = 'Loopback or unspecified'; Test = { param($o) $o[0] -eq 127 -or ($o[0] -eq 0) } }
    @{ Name = 'Link local'; Test = { param($o) $o[0] -eq 169 -and $o[1] -eq 254 } }
    @{ Name = 'Multicast or reserved'; Test = { param($o) $o[0] -ge 224 } }
    @{ Name = 'Benchmarking'; Test = { param($o) $o[0] -eq 198 -and ($o[1] -eq 18 -or $o[1] -eq 19) } }
    @{ Name = 'Shared CGNAT'; Test = { param($o) $o[0] -eq 100 -and $o[1] -ge 64 -and $o[1] -le 127 } }
    @{ Name = 'Microsoft Teams published'; Test = { param($o) $o[0] -eq 52 -and $o[1] -ge 112 -and $o[1] -le 123 } }
)

$IpPattern = [Regex]'\b((?:\d{1,3}\.){3}\d{1,3})\b'

foreach ($Item in $Field) {
    if ($OpaqueField -contains $Item.Name) { continue }

    foreach ($Match in $IpPattern.Matches($Item.Value)) {
        $Octet = $Match.Groups[1].Value -split '\.' | ForEach-Object { [Int]$_ }
        if (($Octet | Where-Object { $_ -gt 255 })) { continue }

        $Safe = $false
        foreach ($Network in $SafeNetwork) {
            if (& $Network.Test $Octet) { $Safe = $true; break }
        }

        if (-not $Safe) {
            & $Add 'Routable address' 'High' $Item $Match.Groups[1].Value
        }
    }
}
#endregion Address checks

#region Host name checks
$HostPattern = [Regex]'(?i)\b([a-z0-9](?:[a-z0-9\-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?)+)\b'

foreach ($Item in $Field) {
    if ($OpaqueField -contains $Item.Name) { continue }
    if ($GeneratedNameField -contains $Item.Name) { continue }
    if ($NotAHostField -contains $Item.Name) { continue }

    foreach ($Match in $HostPattern.Matches($Item.Value)) {
        $Candidate = $Match.Groups[1].Value.ToLowerInvariant()

        # Skip anything that is actually a dotted number, a version, or a file name.
        if ($Candidate -match '^[\d\.]+$') { continue }
        if ($Candidate -match '\.(wav|xml|tar|gz|log|txt|csv|json|pem|der|cer|crt|pfx|p12)$') { continue }
        if ($Candidate -notmatch '\.[a-z]{2,}$') { continue }

        $Allowed = $false
        foreach ($Domain in $AllowedDomain) {
            if ($Candidate -eq $Domain -or $Candidate.EndsWith(".$Domain", [StringComparison]::Ordinal)) {
                $Allowed = $true
                break
            }
        }

        if (-not $Allowed) {
            & $Add 'Host or domain' 'High' $Item $Match.Groups[1].Value
        }
    }
}
#endregion Host name checks

#region Number checks
# The samples use the ACMA fictitious range, which is 7010 followed by four digits within an
# Australian area code. Anything else that looks like a dialable number is reported.
$NumberPattern = [Regex]'\+?\d[\d]{6,}'

foreach ($Item in $Field) {
    if ($OpaqueField -contains $Item.Name) { continue }
    if ($GeneratedNameField -contains $Item.Name) { continue }

    foreach ($Match in $NumberPattern.Matches($Item.Value)) {
        $Number = $Match.Value

        # 7010 is the ACMA fictitious range the samples use. Transformation rules frequently
        # hold a partial number as a matching prefix, so a substring match is correct here
        # rather than requiring the full eight digit form.
        if ($Number -match '7010') { continue }

        # Long runs of repeated digits are self evidently placeholder numbers.
        if ($Number -match '5{4,}') { continue }

        if ($AllowedNumber -contains ($Number -replace '^\+', '')) { continue }

        # Ignore obvious non-numbers: timestamps, sizes and identifiers.
        if ($Item.Name -match '(?i)time|date|expiry|size|count|bytes|serial|version|id$') { continue }

        & $Add 'Possible telephone number' 'Medium' $Item $Number
    }
}
#endregion Number checks

#region Email checks
$EmailPattern = [Regex]'(?i)\b[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}\b'

foreach ($Item in $Field) {
    foreach ($Match in $EmailPattern.Matches($Item.Value)) {
        $Address = $Match.Value.ToLowerInvariant()
        $Allowed = $false
        foreach ($Domain in $AllowedDomain) {
            if ($Address.EndsWith("@$Domain", [StringComparison]::Ordinal) -or $Address.EndsWith(".$Domain", [StringComparison]::Ordinal)) {
                $Allowed = $true
                break
            }
        }
        if (-not $Allowed) {
            & $Add 'Email address' 'High' $Item $Match.Value
        }
    }
}
#endregion Email checks

#region Secret material
$SecretField = @(
    'CertFileContent', 'CertKeyId', 'EncryptedPassword', 'EncryptedAuthPassphrase',
    'EncryptedPrivPassphrase', 'snmpCommunity', 'Ntp1ServerKey', 'Ntp2ServerKey',
    'Secret', 'Password', 'SharedSecret', 'AuthPassword'
)

foreach ($Item in $Field) {
    if ($SecretField -contains $Item.Name) {
        # Reported at Medium because a sanitised sample legitimately carries the documented
        # sample credentials. The point is to make you confirm the value is the sample one and
        # not something carried over from the original appliance.
        & $Add 'Credential field populated (confirm it is the sample value)' 'Medium' $Item ('{0} characters' -f $Item.Value.Length)
    }

    if ($Item.Value -match 'BEGIN (CERTIFICATE|RSA PRIVATE KEY|PRIVATE KEY)') {
        & $Add 'Certificate or key material' 'High' $Item 'PEM block present'
    }
}
#endregion Secret material

#region Explicit deny list
foreach ($Term in $MustNotContain) {
    if ([String]::IsNullOrWhiteSpace($Term)) { continue }

    foreach ($Item in $Field) {
        if ($Item.Value -like "*$Term*") {
            & $Add "Denied term '$Term'" 'Critical' $Item $Item.Value
        }
    }
}
#endregion Explicit deny list

#region User accounts
# Reported rather than judged. A leftover administrator account is not detectable by pattern,
# but it is obvious the moment someone reads the list.
$Account = foreach ($Item in $Field | Where-Object { $_.Class -match 'USER' -and $_.Name -match '(?i)^(name|username|userid)$' }) {
    [PSCustomObject]@{ Location = $Item.Location; Field = $Item.Name; Account = $Item.Value }
}
#endregion User accounts

#region Report
Write-Host ''
Write-Host ("Sample : {0}" -f (Split-Path $Path -Leaf)) -ForegroundColor Cyan
Write-Host ("Release: {0}   Platform: {1}   Fields scanned: {2}" -f $Config.SystemRelease, $Config.PlatformType, $Field.Count) -ForegroundColor Cyan
Write-Host ''

if ($Account) {
    Write-Host 'Local accounts present (verify each is intentional):' -ForegroundColor Yellow
    $Account | Format-Table -AutoSize | Out-String -Width 160 | Write-Host
}

if (-not $Finding.Count) {
    Write-Host 'No findings. Nothing matched the patterns, which is not the same as nothing being missed.' -ForegroundColor Green
    exit 0
}

$Order = @{ 'Critical' = 0; 'High' = 1; 'Medium' = 2 }

foreach ($Group in $Finding | Group-Object Category | Sort-Object { $Order[($_.Group[0].Severity)] }, Name) {
    $Severity = $Group.Group[0].Severity
    $Colour = switch ($Severity) { 'Critical' { 'Red' } 'High' { 'Red' } default { 'Yellow' } }

    Write-Host ("[{0}] {1} ({2} occurrences, {3} distinct)" -f $Severity, $Group.Name, $Group.Count, (@($Group.Group.Value | Select-Object -Unique).Count)) -ForegroundColor $Colour

    $Rows = if ($Detailed) { $Group.Group } else { $Group.Group | Group-Object Value | ForEach-Object { $_.Group[0] } | Select-Object -First 15 }
    $Rows | Select-Object Value, Field, Location | Format-Table -AutoSize | Out-String -Width 160 | Write-Host
}

Write-Host ("{0} findings total. Review every one before publishing." -f $Finding.Count) -ForegroundColor Red
exit 1
#endregion Report
