<#
.SYNOPSIS
    Reports which enumeration values actually occur across the sample configurations.
.DESCRIPTION
    Greig's script carries very large enumeration tables, but only a fraction of the values
    appear in real configurations. This reports the values actually in use for a given field
    so translation tables can be built from evidence rather than transcribed wholesale.
.PARAMETER XPath
    The node set to sample, relative to the Configuration element.
.PARAMETER Field
    The field within each row to tally.
.EXAMPLE
    PS C:\> .\Dev\Get-AbrRibbonFieldUsage.ps1 -XPath "Token[@name='Transformation']/ID/ID" -Field InputField
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [String] $XPath,

    [Parameter(Mandatory = $true)]
    [String] $Field
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

foreach ($Function in Get-ChildItem -Path (Join-Path $RepoRoot 'AsBuiltReport.Ribbon.SWeEdge\Src\Private') -Filter '*.ps1') {
    . $Function.FullName
}

$Samples = foreach ($Folder in @('Dev\Samples', 'Dev\Private Samples', 'Dev\More Samples')) {
    $Full = Join-Path $RepoRoot $Folder
    if (Test-Path -LiteralPath $Full) {
        Get-ChildItem -Path $Full -Filter '*.tar' -File
    }
}

$Values = foreach ($Sample in $Samples) {
    try {
        $Config = Import-AbrRibbonSWeEdgeConfig -Path $Sample.FullName
        foreach ($Row in @($Config.RawXml.Configuration.SelectNodes($XPath) | ConvertFrom-AbrRibbonIeNode)) {
            $Value = $Row.$Field
            if ($null -ne $Value) {
                [PSCustomObject]@{
                    Value   = [String]$Value
                    Release = $Config.SystemRelease
                }
            }
        }
    } catch {
        Write-Warning "$($Sample.Name): $($_.Exception.Message)"
    }
}

Write-Host "`n=== $Field values in use ($XPath) ===" -ForegroundColor Green
$Values |
    Group-Object -Property Value |
    Sort-Object { [Int]$_.Name } |
    ForEach-Object {
        [PSCustomObject]@{
            Value    = $_.Name
            Count    = $_.Count
            Releases = (($_.Group.Release | Sort-Object -Unique) -join ', ')
        }
    } |
    Format-Table -AutoSize -Wrap
