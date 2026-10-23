<#
.SYNOPSIS
    Development harness for the AsBuiltReport.Ribbon.SWeEdge private functions.
.DESCRIPTION
    Dot-sources every private function and imports a sample configuration, then prints a
    summary of what was parsed and how cross-references resolved. Replaces the pile of
    single-use debug scripts that used to live in this folder.

    Secrets are redacted via redact_helper.ps1 before anything is written to the console.
.PARAMETER Path
    Sample configuration to load. Defaults to the first .tar found in Dev\Samples.
.PARAMETER Section
    Which summary to print. Defaults to All.
.EXAMPLE
    PS C:\> .\Dev\Test-AbrRibbonImport.ps1
.EXAMPLE
    PS C:\> .\Dev\Test-AbrRibbonImport.ps1 -Section SignalingGroup
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [String] $Path,

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'Summary', 'SignalingGroup', 'Route', 'Transformation', 'Media', 'Order', 'Token', 'Interface')]
    [String] $Section = 'All',

    [Parameter(Mandatory = $false)]
    [String] $TokenPath
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

foreach ($Function in Get-ChildItem -Path (Join-Path $RepoRoot 'AsBuiltReport.Ribbon.SWeEdge\Src\Private') -Filter '*.ps1') {
    . $Function.FullName
}

$RedactHelper = Join-Path $PSScriptRoot 'redact_helper.ps1'
if (Test-Path -LiteralPath $RedactHelper) {
    . $RedactHelper
}

if (-not $Path) {
    $Sample = Get-ChildItem -Path (Join-Path $RepoRoot 'Dev\Samples') -Filter '*.tar' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $Sample) {
        throw 'No sample .tar found in Dev\Samples. Pass -Path explicitly.'
    }
    $Path = $Sample.FullName
}

Write-Host "Loading $Path" -ForegroundColor Cyan
$Config = Import-AbrRibbonSWeEdgeConfig -Path $Path

if ($Section -eq 'Token') {
    # Explores the raw configuration tree. Without -TokenPath it lists the top level groups
    # and their immediate child tokens. With -TokenPath it dumps the fields of the rows in
    # that group, so section content can be built from what is actually present rather than
    # from assumptions.
    $Xml = $Config.RawXml

    if (-not $TokenPath) {
        Write-Host "`n=== Top level tokens ===" -ForegroundColor Green
        foreach ($Token in $Xml.Configuration.SelectNodes('Token')) {
            $Children = @($Token.SelectNodes('Token') | ForEach-Object { $_.GetAttribute('name') })
            $Rows = @($Token.SelectNodes('ID')).Count
            [PSCustomObject]@{
                Token    = $Token.GetAttribute('name')
                Rows     = $Rows
                Children = ($Children -join ', ')
            }
        }
        return
    }

    Write-Host "`n=== $TokenPath ===" -ForegroundColor Green
    $Nodes = $Xml.Configuration.SelectNodes($TokenPath)
    if (-not $Nodes -or $Nodes.Count -eq 0) {
        Write-Host 'No nodes matched that path.' -ForegroundColor Yellow
        return
    }

    foreach ($Node in $Nodes) {
        # Use LocalName, not Name. PowerShell's XML adapter exposes attributes as properties,
        # so $Node.Name on <Token name="Certificates"> returns "Certificates", not "Token".
        if ($Node.LocalName -in @('ID', 'IE')) {
            $Row = ConvertFrom-AbrRibbonIeNode -Node $Node
            if ($Row) {
                if (Get-Command -Name 'Redact-ObjectProperties' -ErrorAction SilentlyContinue) {
                    $Row = Redact-ObjectProperties $Row
                }

                # Certificate and key material runs to tens of kilobytes of base64. Truncate
                # every long value so the console stays readable and no key material is dumped.
                $Trimmed = [Ordered]@{}
                foreach ($Property in $Row.PSObject.Properties) {
                    $Value = [String]$Property.Value
                    if ($Value.Length -gt 120) {
                        $Value = '{0}... [{1} chars truncated]' -f $Value.Substring(0, 60), ($Value.Length - 60)
                    }
                    $Trimmed[$Property.Name] = $Value
                }

                [PSCustomObject]$Trimmed | Format-List
            }
        } elseif ($Node.LocalName -eq 'Token') {
            [PSCustomObject]@{
                Token    = $Node.GetAttribute('name')
                Rows     = @($Node.SelectNodes('ID')).Count
                HasIE    = $null -ne $Node.SelectSingleNode('IE')
                Children = (@($Node.SelectNodes('Token') | ForEach-Object { $_.GetAttribute('name') }) -join ', ')
            }
        } else {
            $Node.InnerXml
        }
    }

    return
}

if ($Section -in @('All', 'Summary')) {
    Write-Host "`n=== Summary ===" -ForegroundColor Green
    [PSCustomObject]@{
        SystemRelease        = $Config.SystemRelease
        PlatformType         = $Config.PlatformType
        SipGroups            = @($Config.SignalingGroups.SIP).Count
        IsdnGroups           = @($Config.SignalingGroups.ISDN).Count
        CasGroups            = @($Config.SignalingGroups.CAS).Count
        RoutingTables        = @($Config.RoutingTables).Count
        TransformationTables = @($Config.TransformationTables).Count
    } | Format-List
}

if ($Section -in @('All', 'SignalingGroup')) {
    Write-Host "`n=== Signaling groups (references preserved from import) ===" -ForegroundColor Green

    # Field names differ by type. SIP uses RouteTableID, CAS uses RouteTableId and ISDN uses
    # RouteTableNumber, so all three are shown to prove the importer normalises them.
    foreach ($Type in 'SIP', 'ISDN', 'CAS') {
        $Groups = @($Config.SignalingGroups.$Type)
        if (-not $Groups) {
            continue
        }

        Write-Host "-- $Type --" -ForegroundColor Yellow
        $Groups |
            Select-Object ID, Description, RouteTable, MediaConfigID, ApplyToPortName, IsRecorder |
            Format-Table -AutoSize
    }

    Write-Host "=== Resolved signaling groups ===" -ForegroundColor Green
    Resolve-AbrRibbonSignalingGroup -Config $Config |
        Select-Object ID, Type, Description, State, RouteTableName, MediaListName, SignalingInterface |
        Format-Table -AutoSize

    Write-Host "=== Federated hosts and listen ports ===" -ForegroundColor Green
    Resolve-AbrRibbonSignalingGroup -Config $Config |
        Select-Object ID, Description,
            @{ Name = 'ListenPorts'; Expression = { ($_.ListenPort | ForEach-Object { '{0}/{1}' -f $_.Port, $_.Protocol }) -join ', ' } },
            @{ Name = 'Federated'; Expression = { $_.FederatedHost -join '; ' } } |
        Format-Table -AutoSize -Wrap
}

if ($Section -in @('All', 'Route')) {
    Write-Host "`n=== Route tables (in SBC evaluation order) ===" -ForegroundColor Green
    foreach ($Table in $Config.RoutingTables) {
        Write-Host ("Route table {0}: {1}" -f $Table.ID, $Table.Description) -ForegroundColor Yellow
        $Table.Routes |
            Select-Object ExecutionOrder, ID, Description, Enabled, TransformationTableName, @{ Name = 'Destination'; Expression = { $_.SignalingGroupNames -join ', ' } } |
            Format-Table -AutoSize
    }
}

if ($Section -in @('All', 'Transformation')) {
    Write-Host "`n=== Transformation tables (rule order matters) ===" -ForegroundColor Green
    foreach ($Table in $Config.TransformationTables) {
        Write-Host ("Transformation table {0}: {1}" -f $Table.ID, $Table.Description) -ForegroundColor Yellow
        $Table.Rules |
            Select-Object ExecutionOrder, ID, Enabled, MatchType, InputField, InputFieldValue, OutputField, OutputFieldValue |
            Format-Table -AutoSize
    }
}

if ($Section -in @('All', 'Interface')) {
    Write-Host "`n=== Logical interfaces (port names derived from VLAN descriptions) ===" -ForegroundColor Green
    Resolve-AbrRibbonNetworkInterface -Config $Config |
        Select-Object Name, DisplayName, VlanTag, IPv4Primary, IPv4PrimaryMask, InterfaceIndex |
        Format-Table -AutoSize
}

if ($Section -in @('All', 'Media')) {
    Write-Host "`n=== Media lists ===" -ForegroundColor Green
    $Media = Resolve-AbrRibbonMediaProfile -Config $Config
    $Media.MediaList |
        Select-Object ID, Description, @{ Name = 'Codecs'; Expression = { $_.CodecNames -join ', ' } }, CryptoProfileName |
        Format-Table -AutoSize
}

if ($Section -in @('All', 'Order')) {
    # The base64 Sequence tag on a parent table defines evaluation order. Where that differs
    # from numeric identifier order, rendering rows in document order would misrepresent the
    # configuration. This lists every table where the two disagree.
    Write-Host "`n=== Tables where Sequence order differs from ID order ===" -ForegroundColor Green

    $Mismatches = @()

    foreach ($Table in $Config.TransformationTables) {
        $Sequenced = @($Table.Rules.ID)
        $Numeric = @($Table.Rules.ID | Sort-Object)
        if (($Sequenced -join ',') -ne ($Numeric -join ',')) {
            $Mismatches += [PSCustomObject]@{
                Kind        = 'Transformation'
                Table       = $Table.Description
                SequenceIds = $Sequenced -join ','
            }
        }
    }

    foreach ($Table in $Config.RoutingTables) {
        $Sequenced = @($Table.Routes.ID)
        $Numeric = @($Table.Routes.ID | Sort-Object)
        if (($Sequenced -join ',') -ne ($Numeric -join ',')) {
            $Mismatches += [PSCustomObject]@{
                Kind        = 'Route'
                Table       = $Table.Description
                SequenceIds = $Sequenced -join ','
            }
        }
    }

    if ($Mismatches) {
        $Mismatches | Format-Table -AutoSize -Wrap
    } else {
        Write-Host 'No differences found in this configuration.' -ForegroundColor Yellow
    }
}
