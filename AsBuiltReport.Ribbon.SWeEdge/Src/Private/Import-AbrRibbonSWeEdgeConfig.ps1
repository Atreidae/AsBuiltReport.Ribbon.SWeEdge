function Import-AbrRibbonSWeEdgeConfig {
    <#
    .SYNOPSIS
        Imports a Ribbon SBC configuration export and normalises it for reporting.
    .DESCRIPTION
        Accepts either a raw symphonyconfig.xml export or a TAR/TGZ archive produced by the
        SBC backup process, and returns a single object describing the configuration.

        Every field present on a configuration row is preserved verbatim. Cross-references
        between objects are numeric identifiers, so discarding fields at import time makes
        those references impossible to resolve later.
    .PARAMETER Path
        Path to a Ribbon SBC configuration export (.xml, .tar, .tgz or .tar.gz).
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Version:    0.2.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Import-AbrRibbonSWeEdgeConfig -Path 'C:\Configs\SBC_Config_sbc01.tar'
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [String] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Ribbon SBC configuration file not found: $Path"
    }

    $ResolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $XmlPath = $null
    $TempDirectory = $null

    try {
        switch -Regex ($ResolvedPath) {
            '\.xml$' {
                $XmlPath = $ResolvedPath
                break
            }
            '\.(tar|tgz|tar\.gz)$' {
                $TempDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('RibbonSWeEdge_{0}' -f [Guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Path $TempDirectory -Force | Out-Null

                # Music on hold WAV files inside the archive can carry names that are invalid
                # on Windows. tar reports those on stderr, which PowerShell escalates to a
                # terminating error when ErrorActionPreference is Stop, so it is suppressed
                # locally. The extraction failures are not fatal, the XML still lands.
                $PreviousErrorAction = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    & tar -xf $ResolvedPath -C $TempDirectory 2>&1 | Out-Null
                } finally {
                    $ErrorActionPreference = $PreviousErrorAction
                }

                $XmlCandidate = Get-ChildItem -Path $TempDirectory -Recurse -Filter 'symphonyconfig.xml' -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $XmlCandidate) {
                    throw "Could not find symphonyconfig.xml inside the archive: $ResolvedPath"
                }

                $XmlPath = $XmlCandidate.FullName
                break
            }
            default {
                throw "Unsupported configuration file type: $ResolvedPath. Supply a .xml, .tar, .tgz or .tar.gz export."
            }
        }

        [Xml] $ConfigXml = Get-Content -LiteralPath $XmlPath -Encoding UTF8 -Raw

        #region Signaling groups
        $SignalingGroups = [Ordered]@{
            ISDN = @()
            SIP  = @()
            CAS  = @()
        }

        foreach ($SignalingGroupType in @('ISDN', 'SIP', 'CAS')) {
            $Rows = @($ConfigXml.Configuration.SelectNodes("Token[@name='SignalingGroups']/Token[@name='$SignalingGroupType']/ID") | ConvertFrom-AbrRibbonIeNode)

            foreach ($Row in $Rows) {
                # ISDN groups name these fields RouteTableNumber, SIP and CAS use RouteTableID.
                $RouteTable = $Row.RouteTableID
                if ([String]::IsNullOrWhiteSpace($RouteTable)) {
                    $RouteTable = $Row.RouteTableNumber
                }

                $Row | Add-Member -NotePropertyName 'Type' -NotePropertyValue $SignalingGroupType -Force
                $Row | Add-Member -NotePropertyName 'RouteTable' -NotePropertyValue $RouteTable -Force

                # Identifiers at or above 50000 are SIPREC recorders rather than trunks.
                $Row | Add-Member -NotePropertyName 'IsRecorder' -NotePropertyValue ([Int]$Row.ID -ge 50000) -Force

                $SignalingGroups[$SignalingGroupType] += $Row
            }
        }

        $SignalingGroupLookup = @{}
        foreach ($SignalingGroupType in @('ISDN', 'SIP', 'CAS')) {
            foreach ($Row in $SignalingGroups[$SignalingGroupType]) {
                $SignalingGroupLookup[[String]$Row.ID] = [String]$Row.Description
            }
        }
        #endregion Signaling groups

        #region Transformation tables
        $TransformationTables = @()

        foreach ($TableNode in @($ConfigXml.Configuration.SelectNodes("Token[@name='Transformation']/ID"))) {
            $Table = ConvertFrom-AbrRibbonIeNode -Node $TableNode
            if (-not $Table) {
                continue
            }

            $Rules = @($TableNode.SelectNodes('ID') | ConvertFrom-AbrRibbonIeNode)
            $Order = ConvertFrom-AbrRibbonSequence -EncodedSequence $Table.Sequence -ByteCount 2

            $TransformationTables += [PSCustomObject]@{
                ID          = $Table.ID
                Description = $Table.Description
                Enabled     = $Table.Enabled
                Rules       = @(Get-AbrRibbonOrderedRow -Row $Rules -Order $Order)
            }
        }

        $TransformationLookup = @{}
        foreach ($Table in $TransformationTables) {
            $TransformationLookup[[String]$Table.ID] = [String]$Table.Description
        }
        #endregion Transformation tables

        #region Routing tables
        $RoutingTables = @()

        foreach ($TableNode in @($ConfigXml.Configuration.SelectNodes("Token[@name='CallRouting']/Token[@name='RoutingTable']/ID"))) {
            $Table = ConvertFrom-AbrRibbonIeNode -Node $TableNode
            if (-not $Table) {
                continue
            }

            $Routes = @($TableNode.SelectNodes('ID') | ConvertFrom-AbrRibbonIeNode)
            $Order = ConvertFrom-AbrRibbonSequence -EncodedSequence $Table.Sequence -ByteCount 2

            foreach ($Route in $Routes) {
                $DestinationSignalingGroups = @(ConvertFrom-AbrRibbonSequence -EncodedSequence $Route.SignalingGroupList -ByteCount 2)

                $TransformationName = switch ($Route.DestinationType) {
                    '2' { '--Deny--' }
                    default { Resolve-AbrRibbonReference -Id $Route.TransformationTable -Lookup $TransformationLookup }
                }

                $Route | Add-Member -NotePropertyName 'SignalingGroupIds' -NotePropertyValue $DestinationSignalingGroups -Force
                $Route | Add-Member -NotePropertyName 'SignalingGroupNames' -NotePropertyValue @(
                    foreach ($Id in $DestinationSignalingGroups) {
                        Resolve-AbrRibbonReference -Id ([String]$Id) -Lookup $SignalingGroupLookup
                    }
                ) -Force
                $Route | Add-Member -NotePropertyName 'TransformationTableName' -NotePropertyValue $TransformationName -Force
            }

            $RoutingTables += [PSCustomObject]@{
                ID          = $Table.ID
                Description = $Table.Description
                Enabled     = $Table.Enabled
                Routes      = @(Get-AbrRibbonOrderedRow -Row $Routes -Order $Order)
            }
        }
        #endregion Routing tables

        [PSCustomObject]@{
            SourceFile           = $ResolvedPath
            SourceXmlFile        = $XmlPath
            SystemRelease        = $ConfigXml.Configuration.SystemRelease
            PlatformType         = $ConfigXml.Configuration.PlatformType
            RawXml               = $ConfigXml
            SignalingGroups      = $SignalingGroups
            RoutingTables        = $RoutingTables
            TransformationTables = $TransformationTables
        }
    } finally {
        if ($TempDirectory -and (Test-Path -LiteralPath $TempDirectory)) {
            Remove-Item -LiteralPath $TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
