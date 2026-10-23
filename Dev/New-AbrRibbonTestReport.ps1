<#
.SYNOPSIS
    Generates a real report from a sample configuration for development.
.DESCRIPTION
    Runs the module through AsBuiltReport.Core exactly as an end user would, so section
    layout, InfoLevel gating and localization can be checked against real output.

    Output lands in Dev\output, which is gitignored.
.PARAMETER Path
    Sample configuration to report on. Defaults to the sanitised test sample.
.PARAMETER InfoLevel
    Overrides every section InfoLevel so different levels can be checked quickly.
.PARAMETER Format
    PScribo output formats. Text is fastest to eyeball during development.
.PARAMETER AsBuiltConfigFilePath
    The saved AsBuiltReport configuration holding author and company details. Defaults to
    AsBuiltReport.json in the output folder. Without this, New-AsBuiltReport starts its
    interactive wizard on every run.
.PARAMETER Filename
    Overrides the output file name. Useful when the previous run is still open in Word,
    which holds a lock on the file and fails the export.
.PARAMETER StyleFilePath
    A custom PScribo style script. Defaults to the AsBuiltReport.Core style when omitted.
.PARAMETER Credential
    Credentials for a REST enabled account, used when Path is an appliance host name rather
    than a configuration export. Ignored for file based targets.
.EXAMPLE
    PS C:\> .\Dev\New-AbrRibbonTestReport.ps1 -InfoLevel 3
.EXAMPLE
    PS C:\> .\Dev\New-AbrRibbonTestReport.ps1 -Path 'sbc1.contoso.com' -Credential (Get-Credential)

    Collects from an appliance over REST instead of reading a file.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [String] $Path,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 5)]
    [Int] $InfoLevel = 3,

    [Parameter(Mandatory = $false)]
    [String[]] $Format = @('Text'),

    [Parameter(Mandatory = $false)]
    [Switch] $ShowTopologyDiagram,

    [Parameter(Mandatory = $false)]
    [String] $AsBuiltConfigFilePath,

    [Parameter(Mandatory = $false)]
    [String] $Filename,

    [Parameter(Mandatory = $false)]
    [String] $StyleFilePath,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.PSCredential] $Credential
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = Join-Path $RepoRoot 'AsBuiltReport.Ribbon.SWeEdge'
$OutputFolder = Join-Path $PSScriptRoot 'output'

if (-not (Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

if (-not $Path) {
    # Samples/ holds the sanitised export published with the module. Dev/Samples is a local
    # working folder that is not committed, so it only applies on a developer's machine.
    $SampleFolder = @(
        Join-Path $RepoRoot 'Samples'
        Join-Path $RepoRoot 'Dev\Samples'
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $Sample = Get-ChildItem -Path $SampleFolder -Filter '*.tar' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $Sample) {
        throw 'No sample configuration found in Samples or Dev\Samples. Pass -Path explicitly.'
    }
    $Path = $Sample.FullName
}

# A host name target collects over REST and needs real credentials.
if (-not (Test-Path -LiteralPath $Path) -and -not $Credential) {
    throw "'$Path' is not a file, so it is treated as an appliance to collect from. Supply -Credential for a REST enabled account."
}

Import-Module AsBuiltReport.Core -Force

# New-AsBuiltReport resolves -Report by looking for an AsBuiltReport.<Report> module on
# PSModulePath. The repo root is the module's parent folder, so adding it makes the local
# working copy discoverable without installing it.
if ($env:PSModulePath -notlike "*$RepoRoot*") {
    $env:PSModulePath = '{0}{1}{2}' -f $RepoRoot, [System.IO.Path]::PathSeparator, $env:PSModulePath
}

Import-Module (Join-Path $ModuleRoot 'AsBuiltReport.Ribbon.SWeEdge.psd1') -Force

# Build a report configuration with every section set to the requested level.
$ReportConfigPath = Join-Path $OutputFolder 'RibbonSWeEdge.json'
$Config = Get-Content -Path (Join-Path $ModuleRoot 'AsBuiltReport.Ribbon.SWeEdge.json') -Raw | ConvertFrom-Json

foreach ($Property in $Config.InfoLevel.PSObject.Properties) {
    if ($Property.Name -ne '_comment_') {
        $Config.InfoLevel.$($Property.Name) = $InfoLevel
    }
}

if ($ShowTopologyDiagram) {
    $Config.Options.ShowTopologyDiagram = $true
}

$Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ReportConfigPath -Encoding UTF8

# New-AsBuiltReport prompts interactively for author and company details unless it is given a
# saved configuration. Generate one once with New-AsBuiltConfig and save it as
# Dev\output\AsBuiltReport.json, or pass -AsBuiltConfigFilePath. The file is gitignored
# because it contains your own name and company details.
if (-not $AsBuiltConfigFilePath) {
    $AsBuiltConfigFilePath = Join-Path $OutputFolder 'AsBuiltReport.json'

    if (-not (Test-Path -LiteralPath $AsBuiltConfigFilePath)) {
        $Existing = Get-ChildItem -Path $OutputFolder -Filter '*.json' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'RibbonSWeEdge.json' } |
            Select-Object -First 1
        if ($Existing) {
            $AsBuiltConfigFilePath = $Existing.FullName
        }
    }
}

if (-not (Test-Path -LiteralPath $AsBuiltConfigFilePath)) {
    throw "AsBuilt configuration not found at $AsBuiltConfigFilePath. Run New-AsBuiltConfig once and save it there, or pass -AsBuiltConfigFilePath."
}

Write-Host "Reporting on $Path at InfoLevel $InfoLevel" -ForegroundColor Cyan

# AsBuiltReport.Core makes Credential mandatory because most report modules connect to a
# live system. A file based target never authenticates, so a placeholder is supplied unless
# real credentials were passed for a REST collection.
#
# An empty SecureString is used rather than ConvertTo-SecureString -AsPlainText. There is no
# secret here, but the plaintext form is an Error level PSScriptAnalyzer finding and CI fails
# the build on errors. Avoiding the call is better than suppressing the rule, because the
# suppression would then be copied into the REST code where the rule genuinely matters.
$PlaceholderCredential = if ($Credential) { $Credential } else { [PSCredential]::new('unused', [System.Security.SecureString]::new()) }

if (-not $Filename) {
    $Filename = 'RibbonSWeEdge_Level{0}' -f $InfoLevel
}

$ReportParams = @{
    Report                = 'Ribbon.SWeEdge'
    Target                = $Path
    Credential            = $PlaceholderCredential
    Format                = $Format
    OutputFolderPath      = $OutputFolder
    AsBuiltConfigFilePath = $AsBuiltConfigFilePath
    ReportConfigFilePath  = $ReportConfigPath
    Filename              = $Filename
}

if ($StyleFilePath) {
    if (-not (Test-Path -LiteralPath $StyleFilePath)) {
        throw "Style script not found at $StyleFilePath."
    }
    $ReportParams['StyleFilePath'] = $StyleFilePath
}

New-AsBuiltReport @ReportParams -Verbose

Get-ChildItem -Path $OutputFolder -Filter "$Filename*" | Select-Object Name, Length, LastWriteTime
