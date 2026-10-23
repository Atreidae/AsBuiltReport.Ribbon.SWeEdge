<#
.SYNOPSIS
    Extracts dropdown option values and labels from a saved WebUI page.
.DESCRIPTION
    Development probe. A saved copy of a Ribbon WebUI configuration page contains the
    authoritative mapping between the numbers stored in a configuration export and the labels
    an administrator actually sees. Reading them from the page is both faster and more reliable
    than transcribing them by hand.

    Only the page's own select elements are read. Nothing is inferred: a field with no select
    element on the page is reported as absent rather than guessed at.
.PARAMETER Path
    The saved HTML page.
.PARAMETER Field
    Restrict output to select elements whose name or id matches this pattern.
.EXAMPLE
    PS C:\> .\Dev\Get-AbrRibbonWebUiEnum.ps1 -Path '.\.copilot\Create SIP Signaling Group.html'
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [String] $Path,

    [Parameter(Mandatory = $false)]
    [String] $Field
)

$ErrorActionPreference = 'Stop'

$Html = Get-Content -Path $Path -Raw

# Each select element with everything up to its closing tag, so options stay with their field.
$SelectPattern = [Regex]'(?is)<select\b([^>]*)>(.*?)</select>'
$AttributePattern = [Regex]'(?i)\b(name|id)\s*=\s*["'']([^"'']+)["'']'
$OptionPattern = [Regex]'(?is)<option\b([^>]*)>(.*?)</option>'
$ValuePattern = [Regex]'(?i)\bvalue\s*=\s*["'']([^"'']*)["'']'

$Result = foreach ($Select in $SelectPattern.Matches($Html)) {

    $Attributes = $Select.Groups[1].Value
    $Name = $null
    foreach ($Attribute in $AttributePattern.Matches($Attributes)) {
        if ($Attribute.Groups[1].Value -ieq 'name') { $Name = $Attribute.Groups[2].Value; break }
        if (-not $Name) { $Name = $Attribute.Groups[2].Value }
    }

    if (-not $Name) { continue }
    if ($Field -and $Name -notmatch $Field) { continue }

    $Options = foreach ($Option in $OptionPattern.Matches($Select.Groups[2].Value)) {
        $Value = $ValuePattern.Match($Option.Groups[1].Value)

        # Strip markup and collapse whitespace so the label reads as it does on screen.
        $Label = $Option.Groups[2].Value -replace '<[^>]+>', ''
        $Label = [System.Net.WebUtility]::HtmlDecode($Label).Trim() -replace '\s+', ' '

        if ($Value.Success -and $Label) {
            '{0}={1}' -f $Value.Groups[1].Value, $Label
        }
    }

    if ($Options) {
        [PSCustomObject]@{
            Field   = $Name
            Count   = @($Options).Count
            Options = ($Options -join '  |  ')
        }
    }
}

if (-not $Result) {
    Write-Host 'No select elements matched.' -ForegroundColor Yellow
    return
}

$Result | Sort-Object Field
