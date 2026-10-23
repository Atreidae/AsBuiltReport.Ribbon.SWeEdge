<#
.SYNOPSIS
    Generates a report from every sample configuration and reports any failures.
.DESCRIPTION
    A section that throws is caught and logged as a PScribo warning rather than stopping the
    report, which means a broken section can go unnoticed. This runs every sample through the
    full pipeline and surfaces any warnings, so regressions are visible.

    Output is written to Dev\output\regression and is gitignored.
.PARAMETER InfoLevel
    Level to render every section at. Higher levels exercise more code.
.PARAMETER Format
    Output formats. All three are included by default because the project's testing checklist
    requires Word, HTML and Text to be verified. Word is the strictest: it fails outright when
    the number of ColumnWidths does not match the number of columns, where Text and HTML
    silently tolerate the mismatch and render a misleading table.
.EXAMPLE
    PS C:\> .\Dev\Invoke-AbrRibbonRegression.ps1 -InfoLevel 3
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 5)]
    [Int] $InfoLevel = 3,

    [Parameter(Mandatory = $false)]
    [String[]] $Format = @('Text', 'Html', 'Word')
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = Join-Path $RepoRoot 'AsBuiltReport.Ribbon.SWeEdge'
$OutputFolder = Join-Path $PSScriptRoot 'output\regression'
# Deliberately not named AsBuiltConfig. AsBuiltReport.Core assigns a global variable of that
# name during a report run, which silently overwrites a script variable and makes every run
# after the first fail with a null path.
#
# Generate this once with New-AsBuiltConfig and save it as Dev\output\AsBuiltReport.json. It
# holds your own name and company details, so it is gitignored.
$AsBuiltConfigPath = Join-Path $PSScriptRoot 'output\AsBuiltReport.json'

if (-not (Test-Path -LiteralPath $AsBuiltConfigPath)) {
    $Existing = Get-ChildItem -Path (Join-Path $PSScriptRoot 'output') -Filter '*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'RibbonSWeEdge.json' } |
        Select-Object -First 1
    if ($Existing) {
        $AsBuiltConfigPath = $Existing.FullName
    } else {
        throw "No AsBuiltReport configuration found. Run New-AsBuiltConfig and save it as $AsBuiltConfigPath."
    }
}

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

Import-Module AsBuiltReport.Core -Force
if ($env:PSModulePath -notlike "*$RepoRoot*") {
    $env:PSModulePath = '{0}{1}{2}' -f $RepoRoot, [System.IO.Path]::PathSeparator, $env:PSModulePath
}
Import-Module (Join-Path $ModuleRoot 'AsBuiltReport.Ribbon.SWeEdge.psd1') -Force

$ReportConfigPath = Join-Path $OutputFolder 'RibbonSWeEdge.json'
$Config = Get-Content -Path (Join-Path $ModuleRoot 'AsBuiltReport.Ribbon.SWeEdge.json') -Raw | ConvertFrom-Json
foreach ($Property in $Config.InfoLevel.PSObject.Properties) {
    if ($Property.Name -ne '_comment_') {
        $Config.InfoLevel.$($Property.Name) = $InfoLevel
    }
}
$Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ReportConfigPath -Encoding UTF8

# This module never authenticates, so the mandatory Credential parameter is a placeholder.
# An empty SecureString avoids the Error level plaintext finding that would fail CI.
$Credential = [PSCredential]::new('unused', [System.Security.SecureString]::new())

$Samples = foreach ($Folder in @('Dev\Samples', 'Dev\Private Samples', 'Dev\More Samples')) {
    $Full = Join-Path $RepoRoot $Folder
    if (Test-Path -LiteralPath $Full) {
        Get-ChildItem -Path $Full -Filter '*.tar' -File
        Get-ChildItem -Path $Full -Filter '*.xml' -File
    }
}

$Results = foreach ($Sample in $Samples) {
    $Name = [System.IO.Path]::GetFileNameWithoutExtension($Sample.Name)
    $Warnings = @()

    try {
        # Section failures surface as warnings, so they are captured rather than ignored.
        New-AsBuiltReport -Report 'Ribbon.SWeEdge' `
            -Target $Sample.FullName `
            -Credential $Credential `
            -Format $Format `
            -OutputFolderPath $OutputFolder `
            -AsBuiltConfigFilePath $AsBuiltConfigPath `
            -ReportConfigFilePath $ReportConfigPath `
            -Filename $Name `
            -WarningVariable Warnings `
            -WarningAction SilentlyContinue | Out-Null

        $Output = Join-Path $OutputFolder "$Name.txt"
        $Size = if (Test-Path $Output) { (Get-Item $Output).Length } else { 0 }

        # Anything that should never appear in a rendered report. Both the text and HTML
        # renderings are scanned. They come from the same PScribo document so a leak should
        # appear in either, but the check is cheap and a false sense of safety here is
        # expensive. The Word file is a zip archive and is not scanned.
        $Leak = ''
        foreach ($Rendered in @("$Name.txt", "$Name.html")) {
            $RenderedPath = Join-Path $OutputFolder $Rendered
            if (-not (Test-Path -LiteralPath $RenderedPath)) {
                continue
            }

            $Text = Get-Content -Path $RenderedPath -Raw
            foreach ($Pattern in 'BEGIN CERTIFICATE', 'snmpCommunity', 'EncryptedPassword') {
                if ($Text -match [Regex]::Escape($Pattern) -and $Leak -notmatch [Regex]::Escape($Pattern)) {
                    $Leak += "$Pattern "
                }
            }
        }

        [PSCustomObject]@{
            Sample   = $Name
            Bytes    = $Size
            Warnings = @($Warnings | Where-Object { $_ -notmatch 'moh/|Invalid argument' }).Count
            Leak     = $Leak
            Error    = ''
        }
    } catch {
        [PSCustomObject]@{
            Sample   = $Name
            Bytes    = 0
            Warnings = 0
            Leak     = ''
            Error    = $_.Exception.Message
        }
    }
}

$Results | Format-Table -AutoSize

$Failed = @($Results | Where-Object { $_.Error -or $_.Bytes -eq 0 })
if ($Failed) {
    Write-Host "`n=== Failures ===" -ForegroundColor Red
    $Failed | Select-Object Sample, Error | Format-List
}

Write-Host "`n=== Summary ===" -ForegroundColor Green
Write-Host ("Samples          : {0}" -f @($Results).Count)
Write-Host ("Failed to render : {0}" -f @($Results | Where-Object { $_.Error -or $_.Bytes -eq 0 }).Count)
Write-Host ("With warnings    : {0}" -f @($Results | Where-Object { $_.Warnings -gt 0 }).Count)
Write-Host ("With leaks       : {0}" -f @($Results | Where-Object { $_.Leak }).Count)
