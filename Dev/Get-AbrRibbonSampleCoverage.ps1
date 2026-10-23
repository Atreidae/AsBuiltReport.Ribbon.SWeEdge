<#
.SYNOPSIS
    Reports which sample configurations exercise which parts of the parser.
.DESCRIPTION
    Walks every sample configuration and summarises the object counts that matter for test
    coverage, so fixtures can be chosen deliberately rather than by guesswork. ISDN and CAS
    signaling groups in particular use different field names to SIP, so at least one sample
    of each is needed before those code paths can be trusted.
.PARAMETER Path
    Folders to scan. Defaults to both sample folders under Dev.
.PARAMETER SignalingGroupField
    Instead of the coverage summary, report the distribution of these signaling group fields
    across every sample. Useful for working out whether a field's behaviour is version
    specific, and for finding a sample on a release you can still check against hardware.
.PARAMETER MediaListField
    As above, but reports the distribution of media list profile fields.
.EXAMPLE
    PS C:\> .\Dev\Get-AbrRibbonSampleCoverage.ps1
.EXAMPLE
    PS C:\> .\Dev\Get-AbrRibbonSampleCoverage.ps1 -SignalingGroupField SignalingSourceIPType
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [String[]] $Path,

    [Parameter(Mandatory = $false)]
    [String[]] $SignalingGroupField,

    [Parameter(Mandatory = $false)]
    [String[]] $MediaListField
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot

foreach ($Function in Get-ChildItem -Path (Join-Path $RepoRoot 'AsBuiltReport.Ribbon.SWeEdge\Src\Private') -Filter '*.ps1') {
    . $Function.FullName
}

if (-not $Path) {
    $Path = @(
        (Join-Path $RepoRoot 'Dev\Samples')
        (Join-Path $RepoRoot 'Dev\Private Samples')
        (Join-Path $RepoRoot 'Dev\More Samples')
    )
}

$Samples = foreach ($Folder in $Path) {
    if (Test-Path -LiteralPath $Folder) {
        Get-ChildItem -Path $Folder -Filter '*.tar' -File
        Get-ChildItem -Path $Folder -Filter '*.xml' -File
    }
}

$Results = foreach ($Sample in $Samples) {
    try {
        $Config = Import-AbrRibbonSWeEdgeConfig -Path $Sample.FullName
        $Xml = $Config.RawXml

        if ($MediaListField) {
            foreach ($List in (Resolve-AbrRibbonMediaProfile -Config $Config).MediaList) {
                $Row = [Ordered]@{
                    Release = $Config.SystemRelease
                    Platform = $Config.PlatformType
                    Sample = $Sample.Name
                    ListName = $List.Description
                }

                $KeyParts = @($Config.SystemRelease)
                foreach ($Field in $MediaListField) {
                    $Value = $List.$Field
                    $Text = if ([String]::IsNullOrWhiteSpace($Value)) { '(absent)' } else { [String]$Value }
                    $Row[$Field] = $Text
                    $KeyParts += $Text
                }

                $Row['GroupKey'] = $KeyParts -join ' | '
                [PSCustomObject]$Row
            }
        } elseif ($SignalingGroupField) {
            foreach ($Type in 'SIP', 'ISDN', 'CAS') {
                foreach ($Group in @($Config.SignalingGroups.$Type)) {
                    $Row = [Ordered]@{
                        Release = $Config.SystemRelease
                        Platform = $Config.PlatformType
                        Sample = $Sample.Name
                        Type = $Type
                        SG = $Group.ID
                    }

                    $KeyParts = @($Config.SystemRelease)
                    foreach ($Field in $SignalingGroupField) {
                        $Value = $Group.$Field
                        $Text = if ([String]::IsNullOrWhiteSpace($Value)) { '(empty)' } else { [String]$Value }
                        $Row[$Field] = $Text
                        $KeyParts += $Text
                    }

                    $Row['GroupKey'] = $KeyParts -join ' | '
                    [PSCustomObject]$Row
                }
            }
        } else {
            [PSCustomObject]@{
                Sample     = $Sample.Name
                Platform   = $Config.PlatformType
                Release    = $Config.SystemRelease
                SIP        = @($Config.SignalingGroups.SIP).Count
                ISDN       = @($Config.SignalingGroups.ISDN).Count
                CAS        = @($Config.SignalingGroups.CAS).Count
                LineCards  = @($Xml.Configuration.SelectNodes("Token[@name='NodeHardware']/Token[@name='LineCards']//ID")).Count
                Routes     = @($Config.RoutingTables).Count
                Transforms = @($Config.TransformationTables).Count
                Legacy     = @($Xml.Configuration.SelectNodes("Token[@name='Translation']/ID")).Count
                Error      = ''
            }
        }
    } catch {
        [PSCustomObject]@{
            Sample     = $Sample.Name
            Platform   = ''
            Release    = ''
            SIP        = 0
            ISDN       = 0
            CAS        = 0
            LineCards  = 0
            Routes     = 0
            Transforms = 0
            Legacy     = 0
            Error      = $_.Exception.Message
        }
    }
}

if ($SignalingGroupField -or $MediaListField) {
    $Fields = if ($MediaListField) { $MediaListField } else { $SignalingGroupField }

    $Results |
        Where-Object { $_.GroupKey } |
        Group-Object -Property GroupKey |
        Sort-Object Name |
        ForEach-Object {
            $First = $_.Group[0]
            $Row = [Ordered]@{
                Release = $First.Release
                Count   = $_.Count
            }
            foreach ($Field in $Fields) {
                $Row[$Field] = $First.$Field
            }
            $Row['Example'] = if ($First.ListName) { $First.ListName } else { $First.Sample }
            [PSCustomObject]$Row
        } |
        Format-Table -AutoSize -Wrap

    return
}

$Results | Sort-Object Release | Format-Table -AutoSize

Write-Host "`n=== Coverage gaps ===" -ForegroundColor Green
foreach ($Feature in 'ISDN', 'CAS', 'LineCards', 'Legacy') {
    $Covered = @($Results | Where-Object { $_.$Feature -gt 0 })
    if ($Covered) {
        Write-Host ("{0,-10} covered by {1}" -f $Feature, (($Covered | Select-Object -First 3).Sample -join ', ')) -ForegroundColor Gray
    } else {
        Write-Host ("{0,-10} NOT COVERED by any sample" -f $Feature) -ForegroundColor Yellow
    }
}

$Failed = @($Results | Where-Object { $_.Error })
if ($Failed) {
    Write-Host "`n=== Failed to parse ===" -ForegroundColor Red
    $Failed | Select-Object Sample, Error | Format-List
}
