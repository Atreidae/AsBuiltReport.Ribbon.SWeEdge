<#
.SYNOPSIS
    Prints the derived firewall flows for a sample configuration.
.DESCRIPTION
    Development probe only. Runs Resolve-AbrRibbonFirewallRule and prints the derived flow
    table, detected providers and on box access control list so the output can be sanity
    checked against the appliance before the section is written.
.PARAMETER Path
    Sample configuration to resolve. Defaults to the sanitised sample.
.PARAMETER ShowAcl
    Also print the on box access control list rules.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [String] $Path = 'Dev\Samples\SBC_Config_sbc1_13.1.0_b43_2026_08_01.tar',

    [Parameter(Mandatory = $false)]
    [Switch] $ShowAcl
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = Join-Path $RepoRoot 'AsBuiltReport.Ribbon.SWeEdge'

foreach ($Function in Get-ChildItem -Path (Join-Path $ModuleRoot 'Src\Private') -Filter '*.ps1') {
    . $Function.FullName
}

if (-not [System.IO.Path]::IsPathRooted($Path)) {
    $Path = Join-Path $RepoRoot $Path
}

$Config = Import-AbrRibbonSWeEdgeConfig -Path $Path
$Firewall = Resolve-AbrRibbonFirewallRule -Config $Config

Write-Host ("Media port range : {0}" -f $Firewall.MediaPortRange) -ForegroundColor Cyan
Write-Host ("SBC addresses    : {0}" -f $Firewall.SbcAddress) -ForegroundColor Cyan
Write-Host ("Detected peers   : {0}" -f (@($Firewall.KnownPeer | ForEach-Object { $_.Name }) -join ', ')) -ForegroundColor Cyan
Write-Host ("NAT mappings     : {0}" -f @($Firewall.Nat).Count) -ForegroundColor Cyan
Write-Host ''

$Firewall.Flow |
    Format-Table -Wrap -Property Purpose, Direction, Source, SourcePort, Destination, DestinationPort, Protocol |
    Out-String -Width 200 |
    Write-Host

if ($ShowAcl) {
    foreach ($List in $Firewall.AccessControl) {
        Write-Host ("--- {0} [{1}] {2}" -f $List.Description, $List.Family, $List.State) -ForegroundColor Yellow
        $List.Rule |
            Format-Table -Property Action, Protocol, Source, SourcePort, Destination, DestPort, Interface, Precedence, State |
            Out-String -Width 200 |
            Write-Host
    }
}
