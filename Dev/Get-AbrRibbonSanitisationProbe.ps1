<#
.SYNOPSIS
    Prints certificate and directory details from a configuration for sanitisation review.
.DESCRIPTION
    Development probe. Certificate subjects and Active Directory entries are the two places a
    customer identity most often survives sanitisation, because neither is visible in the parts
    of the WebUI people usually think to clear.
.PARAMETER Path
    Configuration export to inspect.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $Path
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

Write-Host ''
Write-Host '=== Certificates ===' -ForegroundColor Cyan
Resolve-AbrRibbonCertificate -Config $Config |
    Select-Object -ExpandProperty Certificate |
    Format-Table ID, Type, CommonName, SubjectAltName, Issuer, NotAfter -AutoSize |
    Out-String -Width 200 |
    Write-Host

Write-Host '=== Active Directory ===' -ForegroundColor Cyan
$Directory = $Xml.Configuration.SelectNodes("Token[@name='AD']//IE")
if (-not $Directory.Count) {
    Write-Host '  none'
} else {
    foreach ($Element in $Directory) {
        $Row = [Ordered]@{ Class = $Element.GetAttribute('classname') }
        foreach ($Name in 'Enabled', 'DomainController', 'SearchScope', 'UserName', 'Attributes') {
            $Node = $Element.SelectSingleNode($Name)
            if ($Node -and -not [String]::IsNullOrWhiteSpace($Node.InnerText)) {
                $Row[$Name] = $Node.InnerText
            }
        }
        [PSCustomObject]$Row | Format-List | Out-String -Width 200 | Write-Host
    }
}

Write-Host '=== Local users ===' -ForegroundColor Cyan
$Users = $Xml.Configuration.SelectNodes("Token[@name='Users']//IE")
foreach ($Element in $Users) {
    $Row = [Ordered]@{ Class = $Element.GetAttribute('classname') }
    foreach ($Child in $Element.ChildNodes) {
        if ($Child.LocalName -match '(?i)name|class|level|enabled' -and -not [String]::IsNullOrWhiteSpace($Child.InnerText)) {
            $Row[$Child.LocalName] = $Child.InnerText
        }
    }
    [PSCustomObject]$Row | Format-List | Out-String -Width 200 | Write-Host
}
