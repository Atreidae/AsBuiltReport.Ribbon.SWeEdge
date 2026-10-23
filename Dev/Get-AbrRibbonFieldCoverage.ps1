<#
.SYNOPSIS
    Reports which configuration fields the report module does not consume.
.DESCRIPTION
    The sample set only contains what the sample appliances happened to have configured, so
    "we render everything in our samples" is a weaker claim than it sounds. This script
    measures two different gaps:

    Present but unused
        Fields that appear in the sample configurations but are never referenced anywhere in
        the module source. These are real, immediately actionable gaps: the data is in front
        of us, so a field can be implemented and verified against actual values today.

    Referenced elsewhere but absent
        Field names that another tool handles but which appear in none of the samples. These
        cannot be implemented safely from here, because there is no data to verify the meaning
        or the enumeration against. They are a list of things to go and look for on an
        appliance, not a list of things to write code for.

    The second list is a discovery aid, not a specification. That is a verification concern
    rather than a licensing one: another author's reading of a field is not evidence of what
    the field means, and at least one such reading has already proven wrong in this project.
    Confirm against a real configuration or the WebUI before implementing anything from it.

    Not every unused field is a gap. The export also carries internal state that the WebUI
    never exposes, which an administrator cannot have configured and which therefore does not
    belong in a document describing how the appliance was built. PasswordHashType is one such
    field: it appears only on 13.x, always holds the same value, and has no control anywhere in
    the interface. Before implementing a field from this list, confirm there is somewhere in
    the WebUI an administrator could have set it.
.PARAMETER SampleFolder
    Folders to scan for configurations. Defaults to the published and working sample folders.
.PARAMETER ComparePath
    Optional script to mine for additional field names, used to build the second list.
.PARAMETER ClassName
    Restrict output to information element classes matching this pattern.
.PARAMETER MinimumOccurrence
    Ignore fields appearing fewer times than this across all samples, which filters one off
    artefacts of a single appliance.
.EXAMPLE
    PS C:\> .\Dev\Get-AbrRibbonFieldCoverage.ps1

    Lists every field present in the samples that the module never reads.
.EXAMPLE
    PS C:\> .\Dev\Get-AbrRibbonFieldCoverage.ps1 -ClassName 'SIP_SG'

    Restricts the report to SIP signalling group fields.
.NOTES
    Version:    0.1.0
    Author:     James Arber
.LINK
    https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [String[]] $SampleFolder,

    [Parameter(Mandatory = $false)]
    [String] $ComparePath,

    [Parameter(Mandatory = $false)]
    [String] $ClassName,

    [Parameter(Mandatory = $false)]
    [Int] $MinimumOccurrence = 1,

    [Parameter(Mandatory = $false)]
    [Switch] $ShowFixed
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = Join-Path $RepoRoot 'AsBuiltReport.Ribbon.SWeEdge'

foreach ($Function in Get-ChildItem -Path (Join-Path $ModuleRoot 'Src\Private') -Filter '*.ps1') {
    . $Function.FullName
}

if (-not $SampleFolder) {
    $SampleFolder = @(
        Join-Path $RepoRoot 'Samples'
        Join-Path $RepoRoot 'Dev\Samples'
        Join-Path $RepoRoot 'Dev\Private Samples'
        Join-Path $RepoRoot 'Dev\More Samples'
    )
}

$SampleFolder = @($SampleFolder | Where-Object { Test-Path -LiteralPath $_ })
if (-not $SampleFolder) {
    throw 'No sample folders found.'
}

#region Module source
# The whole module as one string. A field is considered handled if its name appears anywhere,
# which over reports slightly where a name is generic, but never claims a field is missing
# when it is actually read. Erring that way keeps the output trustworthy.
$Source = (Get-ChildItem -Path (Join-Path $ModuleRoot 'Src') -Filter '*.ps1' -Recurse |
        ForEach-Object { Get-Content -Path $_.FullName -Raw }) -join "`n"
#endregion Module source

#region Sample fields
$Sample = foreach ($Folder in $SampleFolder) {
    Get-ChildItem -Path $Folder -Include '*.tar', '*.tgz', '*.xml' -File -Recurse -ErrorAction SilentlyContinue
}

$Catalogue = @{}
$Scanned = 0

foreach ($File in $Sample) {
    try {
        $Config = Import-AbrRibbonSWeEdgeConfig -Path $File.FullName
    } catch {
        Write-Warning ("Skipped {0}: {1}" -f $File.Name, $_.Exception.Message)
        continue
    }

    $Scanned++

    foreach ($Element in $Config.RawXml.SelectNodes('//IE')) {
        $Class = $Element.GetAttribute('classname')
        if (-not $Class) { continue }
        if ($ClassName -and $Class -notmatch $ClassName) { continue }

        if (-not $Catalogue.ContainsKey($Class)) {
            $Catalogue[$Class] = @{}
        }

        foreach ($Child in $Element.ChildNodes) {
            $Name = $Child.LocalName
            if (-not $Catalogue[$Class].ContainsKey($Name)) {
                $Catalogue[$Class][$Name] = [PSCustomObject]@{
                    Count    = 0
                    Populated = 0
                    Example  = ''
                    Value    = [System.Collections.Generic.HashSet[String]]::new()
                }
            }

            $Entry = $Catalogue[$Class][$Name]
            $Entry.Count++

            $Value = [String]$Child.InnerText

            # Distinct values are the single most useful signal for whether a field is a
            # setting or a fixed internal default. A field that holds the same value in every
            # configuration, across every release, was almost certainly never configurable.
            if ($Value.Length -le 64) {
                [void]$Entry.Value.Add($Value)
            }

            if (-not [String]::IsNullOrWhiteSpace($Value)) {
                $Entry.Populated++
                if (-not $Entry.Example) {
                    $Entry.Example = if ($Value.Length -gt 40) { $Value.Substring(0, 40) + '...' } else { $Value }
                }
            }
        }
    }
}
#endregion Sample fields

#region Report
# Fields the appliance writes into every export regardless of configuration. They describe the
# record rather than the setting, so they are not gaps.
$Structural = @('SystemRelease', 'Sequence', 'SequenceSupported', 'ClassName', 'ID')

$Result = foreach ($Class in $Catalogue.Keys | Sort-Object) {
    foreach ($Name in $Catalogue[$Class].Keys | Sort-Object) {
        if ($Structural -contains $Name) { continue }

        $Entry = $Catalogue[$Class][$Name]
        if ($Entry.Count -lt $MinimumOccurrence) { continue }

        # Only count a field as handled when it is populated somewhere. A field that is always
        # empty in every sample cannot be verified even if the code references it.
        $Handled = $Source -match ('(?<![A-Za-z0-9_]){0}(?![A-Za-z0-9_])' -f [Regex]::Escape($Name))

        [PSCustomObject]@{
            Class     = $Class
            Field     = $Name
            Handled   = $Handled
            Rows      = $Entry.Count
            Populated = $Entry.Populated
            Distinct  = $Entry.Value.Count
            Example   = $Entry.Example
        }
    }
}

$Unused = @($Result | Where-Object { -not $_.Handled -and $_.Populated -gt 0 })
$Empty = @($Result | Where-Object { -not $_.Handled -and $_.Populated -eq 0 })

Write-Host ''
Write-Host ("Samples scanned : {0}" -f $Scanned) -ForegroundColor Cyan
Write-Host ("Classes         : {0}" -f $Catalogue.Keys.Count) -ForegroundColor Cyan
Write-Host ("Fields          : {0} total, {1} handled, {2} unused with data, {3} unused and always empty" -f `
        @($Result).Count, @($Result | Where-Object Handled).Count, $Unused.Count, $Empty.Count) -ForegroundColor Cyan
Write-Host ''

if ($Unused) {
    Write-Host 'Present in the samples, populated, and never read by the module:' -ForegroundColor Yellow
    Write-Host 'Distinct of 1 means every configuration holds the same value, which usually means a fixed default.' -ForegroundColor DarkGray
    $Unused |
        Sort-Object Class, Field |
        Format-Table Class, Field, Populated, Distinct, Example -AutoSize |
        Out-String -Width 180 |
        Write-Host
}

if ($ShowFixed) {
    # Fields the module already renders but which never vary. Worth reviewing: if there is no
    # WebUI control for one, it is internal state being reported as though it were a choice.
    $Fixed = @($Result | Where-Object { $_.Handled -and $_.Distinct -eq 1 -and $_.Populated -gt 0 })

    Write-Host ''
    Write-Host ('Rendered by the module but identical in every configuration ({0}):' -f $Fixed.Count) -ForegroundColor Yellow
    Write-Host 'Check each against the WebUI. A field with no control is a default, not a setting.' -ForegroundColor DarkGray
    $Fixed |
        Sort-Object Class, Field |
        Format-Table Class, Field, Example -AutoSize |
        Out-String -Width 180 |
        Write-Host
}

if ($ComparePath) {
    if (-not (Test-Path -LiteralPath $ComparePath)) {
        throw "Comparison script not found at $ComparePath"
    }

    # Identifiers that look like configuration field names, taken from another tool to produce
    # a list of things to go and verify. The meaning of each still has to be confirmed against
    # a real configuration or the WebUI, because a field name alone says nothing about its
    # enumeration or polarity.
    $Text = Get-Content -Path $ComparePath -Raw
    $Known = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Class in $Catalogue.Keys) {
        foreach ($Name in $Catalogue[$Class].Keys) { [void]$Known.Add($Name) }
    }

    $Candidate = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Match in [Regex]::Matches($Text, "'([A-Za-z][A-Za-z0-9_]{4,40})'")) {
        [void]$Candidate.Add($Match.Groups[1].Value)
    }

    $Missing = @($Candidate | Where-Object { -not $Known.Contains($_) } | Sort-Object)

    Write-Host ''
    Write-Host ("Named in {0} but present in no sample: {1}" -f (Split-Path $ComparePath -Leaf), $Missing.Count) -ForegroundColor Yellow
    Write-Host ('These cannot be verified from the sample set. Treat as a list to investigate on an appliance,') -ForegroundColor DarkGray
    Write-Host ('rather than a specification. A field name says nothing about its enumeration or polarity.') -ForegroundColor DarkGray
    Write-Host ''
    $Missing -join ', ' | Write-Host
}
#endregion Report
