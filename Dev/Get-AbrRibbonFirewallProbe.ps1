<#
.SYNOPSIS
    Dumps the configuration branches that feed the firewall section.
.DESCRIPTION
    Development probe only. Prints the field names and values of the access control list,
    NAT, DNS, NTP, media port range, syslog and SNMP branches so the resolver can be written
    against the real field names rather than assumed ones.
.PARAMETER Path
    Sample configuration to probe.
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [String] $Path = 'Dev\Samples\SBC_Config_sbc1_13.1.0_b43_2026_08_01.tar',

    [Parameter(Mandatory = $false)]
    [Int] $MaxRows = 3
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ModuleRoot = Join-Path $RepoRoot 'AsBuiltReport.Ribbon.SWeEdge'

# The importer is a private function, so the private folder is dot-sourced rather than
# imported through the manifest.
foreach ($Function in Get-ChildItem -Path (Join-Path $ModuleRoot 'Src\Private') -Filter '*.ps1') {
    . $Function.FullName
}

if (-not [System.IO.Path]::IsPathRooted($Path)) {
    $Path = Join-Path $RepoRoot $Path
}

$Config = Import-AbrRibbonSWeEdgeConfig -Path $Path
$Xml = $Config.RawXml

$Branch = @(
    "Token[@name='IPRouting']/Token[@name='AccessCntrlList']"
    "Token[@name='IPRouting']/Token[@name='IPv6AccessCntrlList']"
    "Token[@name='IPRouting']/Token[@name='NATInterface']"
    "Token[@name='IPRouting']/Token[@name='NATPortForward']"
    "Token[@name='IPRouting']/Token[@name='LinkMonitorConfig']"
    "Token[@name='System']/Token[@name='SystemNet']"
    "Token[@name='System']/Token[@name='TimingConfig']"
    "Token[@name='System']/Token[@name='Media']"
    "Token[@name='System']/Token[@name='QOE']"
    "Token[@name='System']/Token[@name='VQServer']"
    "Token[@name='Logging']/Token[@name='SyslogServer']"
    "Token[@name='Logging']/Token[@name='WebUI']"
    "Token[@name='SNMP']/Token[@name='SNMPMgrTable']"
    "Token[@name='GlobalSecurityOptions']"
    "Token[@name='AD']"
    "Token[@name='RAD']"
)

foreach ($Xpath in $Branch) {
    Write-Host ''
    Write-Host "===== $Xpath" -ForegroundColor Cyan

    $Node = $Xml.Configuration.SelectNodes($Xpath)
    if (-not $Node -or $Node.Count -eq 0) {
        Write-Host '  (branch absent)' -ForegroundColor DarkGray
        continue
    }

    $Elements = $Node[0].SelectNodes('.//IE')
    Write-Host ("  rows: {0}" -f $Elements.Count)

    $Shown = 0
    foreach ($Element in $Elements) {
        if ($Shown -ge $MaxRows) { break }
        Write-Host ("  --- classname: {0}" -f $Element.GetAttribute('classname')) -ForegroundColor Yellow
        foreach ($Field in $Element.ChildNodes) {
            $Value = $Field.InnerText
            if ($Value.Length -gt 80) { $Value = $Value.Substring(0, 80) + '...' }
            Write-Host ("      {0,-32} {1}" -f $Field.LocalName, $Value)
        }
        $Shown++
    }
}
