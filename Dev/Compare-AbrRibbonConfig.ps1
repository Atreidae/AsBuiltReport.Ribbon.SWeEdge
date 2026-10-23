<#
.SYNOPSIS
    Compares two or more Ribbon configuration exports field by field.
.DESCRIPTION
    Renders every configuration export to a flat map of path to value, then reports the paths
    where the exports disagree. Intended for appliances that are meant to be identical, where
    the interesting information is the handful of fields that drifted.

    This works on the raw configuration rather than on rendered report output, so it covers
    areas the report does not yet render, SIP message manipulation in particular.

    Rows are keyed by the identifiers in the export. That is reliable for appliances built by
    restoring a common backup, and unreliable for appliances built by hand, where the same
    logical object can hold different identifiers. Read a large diff as a hint to check how
    the appliances were built, not as a list of faults.
.PARAMETER Path
    Two or more configuration exports, .tar or .xml.
.PARAMETER Filter
    Regular expression limiting which paths are compared. Matched against the full path.
.PARAMETER ExcludeField
    Field names ignored during comparison. Defaults to fields expected to differ between
    appliances.
.PARAMETER IncludeIdentical
    Also list paths where every export agrees.
.EXAMPLE
    PS C:\> .\Dev\Compare-AbrRibbonConfig.ps1 -Path (Get-ChildItem .\Configs\*.tar).FullName

    Every difference across the set.
.EXAMPLE
    PS C:\> .\Dev\Compare-AbrRibbonConfig.ps1 -Path $Configs -Filter 'SIPSPRMessageRules'

    Only the SIP message manipulation tables.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String[]] $Path,

    [Parameter(Mandatory = $false)]
    [String] $Filter,

    [Parameter(Mandatory = $false)]
    [String[]] $ExcludeField = @(
        'SystemRelease', 'ClassName',
        'NodeName', 'HostName', 'SerialNumber', 'MACAddress',
        'IPAddress', 'IPAddressV6', 'PrimaryAddress', 'SecondaryAddress',
        'CertFileContent', 'PrivateKey',
        'LastModified', 'TimeStamp'
    ),

    [Parameter(Mandatory = $false)]
    [Switch] $IncludeIdentical
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

foreach ($Function in Get-ChildItem -Path (Join-Path $RepoRoot 'AsBuiltReport.Ribbon.SWeEdge\Src\Private') -Filter '*.ps1') {
    . $Function.FullName
}

if ($Path.Count -lt 2) {
    throw 'Supply at least two configuration exports to compare.'
}

# Walks the configuration tree, emitting one entry per leaf value. The key is the position in
# the tree rather than an index, so the same logical field lines up across exports even when
# rows are written in a different order.
function ConvertTo-FlatMap {
    param (
        [System.Xml.XmlNode] $Node,
        [String] $Prefix,
        [System.Collections.Specialized.OrderedDictionary] $Map
    )

    foreach ($Child in $Node.ChildNodes) {
        if ($Child.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }

        switch ($Child.LocalName) {
            'Token' {
                ConvertTo-FlatMap -Node $Child -Prefix ('{0}/{1}' -f $Prefix, $Child.name) -Map $Map
            }
            'ID' {
                ConvertTo-FlatMap -Node $Child -Prefix ('{0}[{1}]' -f $Prefix, $Child.value) -Map $Map
            }
            'IE' {
                foreach ($Field in $Child.ChildNodes) {
                    if ($Field.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
                    if ($ExcludeField -contains $Field.LocalName) { continue }
                    $Map['{0}.{1}' -f $Prefix, $Field.LocalName] = $Field.InnerText
                }
            }
            default {
                if ($ExcludeField -notcontains $Child.LocalName) {
                    $Map['{0}.{1}' -f $Prefix, $Child.LocalName] = $Child.InnerText
                }
            }
        }
    }
}

$Maps = [Ordered]@{}

foreach ($Item in $Path) {
    $Config = Import-AbrRibbonSWeEdgeConfig -Path $Item
    $Label = [System.IO.Path]::GetFileNameWithoutExtension($Item)
    $Map = [Ordered]@{}
    ConvertTo-FlatMap -Node $Config.RawXml.Configuration -Prefix '' -Map $Map
    $Maps[$Label] = $Map
    Write-Verbose ('{0}: {1} fields' -f $Label, $Map.Count)
}

$Labels = @($Maps.Keys)

$AllKeys = [System.Collections.Generic.HashSet[String]]::new()
foreach ($Label in $Labels) {
    foreach ($Key in $Maps[$Label].Keys) { $null = $AllKeys.Add($Key) }
}

$Results = foreach ($Key in ($AllKeys | Sort-Object)) {
    if ($Filter -and $Key -notmatch $Filter) { continue }

    $Values = foreach ($Label in $Labels) {
        if ($Maps[$Label].Contains($Key)) { [String]$Maps[$Label][$Key] } else { "`u{2205}" }
    }

    $Distinct = @($Values | Sort-Object -Unique)
    if ($Distinct.Count -eq 1 -and -not $IncludeIdentical) { continue }

    $Row = [Ordered]@{ Path = $Key }
    for ($i = 0; $i -lt $Labels.Count; $i++) { $Row[$Labels[$i]] = $Values[$i] }
    $Row['Differs'] = ($Distinct.Count -gt 1)
    [PSCustomObject]$Row
}

$Results
