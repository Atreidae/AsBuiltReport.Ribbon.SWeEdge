function Resolve-AbrRibbonCallRoute {
    <#
    .SYNOPSIS
        Resolves Ribbon call routing tables, route entries and transformation tables.
    .DESCRIPTION
        Route entries and transformation rules are evaluated in the order held in the parent
        table's base64 Sequence field, which is not the same as identifier order. The importer
        applies that ordering, and it is preserved here.

        Destination handling follows the SBC. A Deny route has no destination signaling group,
        and a Trunk Group route routes by trunk rather than by signaling group, so neither
        should present a signaling group list.

        Transformation rules carry a requirement. A table only succeeds when every enabled
        Mandatory rule matches, so an Optional rule failing does not fail the table. Reporting
        rules without that flag would misrepresent routing behaviour.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with RouteTable and TransformationTable.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonCallRoute -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml

    #region Lookups
    $SignalingGroupLookup = @{}
    foreach ($Type in 'SIP', 'ISDN', 'CAS') {
        foreach ($Group in @($Config.SignalingGroups.$Type)) {
            $SignalingGroupLookup[[String]$Group.ID] = [String]$Group.Description
        }
    }

    $TransformationLookup = @{}
    foreach ($Table in $Config.TransformationTables) {
        $TransformationLookup[[String]$Table.ID] = [String]$Table.Description
    }

    $MediaLookup = @{}
    foreach ($List in (Resolve-AbrRibbonMediaProfile -Config $Config).MediaList) {
        $MediaLookup[[String]$List.ID] = [String]$List.Description
    }

    $TimeOfDayLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='TimeOfDay']/ID") | ConvertFrom-AbrRibbonIeNode)
    #endregion Lookups

    $RouteTable = foreach ($Table in $Config.RoutingTables) {

        $Route = foreach ($Entry in $Table.Routes) {

            $DestinationType = switch ([String]$Entry.DestinationType) {
                '0' { 'Normal' }
                '1' { 'Registrar' }
                '2' { 'Deny' }
                '3' { 'Trunk Group' }
                default { "Unknown ($($Entry.DestinationType))" }
            }

            # A Deny route blocks the call, and a Trunk Group route selects a trunk rather
            # than a signaling group. Neither has a meaningful destination group list.
            $Destination = switch ([String]$Entry.DestinationType) {
                '2' { @() }
                '3' { @() }
                default { @($Entry.SignalingGroupNames) }
            }

            $ResolvedRoute = [PSCustomObject]@{
                ExecutionOrder      = $Entry.ExecutionOrder
                ID                  = $Entry.ID
                Description         = $Entry.Description
                State               = if ($Entry.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                DestinationType     = $DestinationType
                Destination         = $Destination
                TransformationTable = $Entry.TransformationTableName
                # A route level media selection overrides the signaling group's media list.
                MediaOverride       = Resolve-AbrRibbonReference -Id ([String]$Entry.MediaSelection) -Lookup $MediaLookup
                TimeOfDay           = Resolve-AbrRibbonReference -Id ([String]$Entry.TimeOfDay) -Lookup $TimeOfDayLookup
                Priority            = switch ([String]$Entry.CallPriority) {
                    '0' { 'Non-Urgent' }
                    '1' { 'Standard' }
                    '2' { 'Urgent' }
                    '3' { 'Emergency' }
                    default { '' }
                }
            }

            # A route pointing at a signaling group or transformation table that no longer
            # exists does not route the call it appears to route. The destination list is
            # already empty for Deny and Trunk Group routes, so those cannot false positive.
            $ResolvedRoute | Add-Member -NotePropertyName 'HasUnresolvedReference' -NotePropertyValue (
                Test-AbrRibbonUnresolvedReference -Value @(
                    $ResolvedRoute.Destination
                    $ResolvedRoute.TransformationTable
                    $ResolvedRoute.MediaOverride
                    $ResolvedRoute.TimeOfDay
                )
            ) -Force

            $ResolvedRoute
        }

        [PSCustomObject]@{
            ID          = $Table.ID
            Description = $Table.Description
            State       = if ($Table.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            Route       = @($Route)
        }
    }

    $TransformationTable = foreach ($Table in $Config.TransformationTables) {

        $Rule = foreach ($Entry in $Table.Rules) {
            [PSCustomObject]@{
                ExecutionOrder = $Entry.ExecutionOrder
                ID             = $Entry.ID
                Description    = $Entry.Description
                State          = if ($Entry.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                # The table only succeeds when every enabled Mandatory rule matches.
                Requirement    = switch ([String]$Entry.MatchType) {
                    '0' { 'Mandatory' }
                    '1' { 'Optional' }
                    default { "Unknown ($($Entry.MatchType))" }
                }
                InputField     = ConvertTo-AbrRibbonTransformField -Value ([String]$Entry.InputField)
                InputValue     = $Entry.InputFieldValue
                OutputField    = ConvertTo-AbrRibbonTransformField -Value ([String]$Entry.OutputField)
                OutputValue    = $Entry.OutputFieldValue
            }
        }

        [PSCustomObject]@{
            ID          = $Table.ID
            Description = $Table.Description
            State       = if ($Table.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
            Rule        = @($Rule)
            UsedBy      = @(
                foreach ($Parent in $RouteTable) {
                    foreach ($Entry in $Parent.Route) {
                        if ($Entry.TransformationTable -eq $Table.Description) {
                            $Parent.Description
                            break
                        }
                    }
                }
            ) | Sort-Object -Unique
        }
    }

    [PSCustomObject]@{
        RouteTable          = @($RouteTable)
        TransformationTable = @($TransformationTable)
    }
}
