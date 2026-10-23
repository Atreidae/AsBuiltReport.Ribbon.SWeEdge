function Get-AbrRibbonSWeEdgeCallRouting {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge call routing information.
    .DESCRIPTION
        Documents the call routing and transformation configuration of a Ribbon SBC in
        Word/HTML/Text formats using PScribo.
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        Routes and rules are rendered in SBC evaluation order rather than identifier order,
        and transformation rules show their Mandatory or Optional requirement, because a rule
        can match while the table as a whole fails.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeCallRouting
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.CallRouting)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Routing = Resolve-AbrRibbonCallRoute -Config $script:RibbonConfig

            if (-not $Routing.RouteTable) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            # Route entries only render at InfoLevel 2, so neither check can justify a
            # paragraph below that level even when a flagged entry exists.
            $AllRoute = @($Routing.RouteTable.Route)

            # A disabled route is a deliberate act, but it is the usual explanation for a
            # route table that looks correct and does not route.
            $HighlightDisabledRoute = [bool]$ReportConfig.HealthCheck.CallRouting.DisabledRoute -and
                $InfoLevel.CallRouting -ge 2 -and
                ($AllRoute | Where-Object { $_.State -eq $LocalizedData.Disabled })

            # A destination or transformation table that no longer exists is a fault. The
            # route cannot do what it appears to do.
            $HighlightUnresolvedRoute = [bool]$ReportConfig.HealthCheck.CallRouting.UnresolvedReference -and
                $InfoLevel.CallRouting -ge 2 -and
                ($AllRoute | Where-Object { $_.HasUnresolvedReference })

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                Paragraph $LocalizedData.OrderInfo
                if ($HighlightDisabledRoute) {
                    Paragraph $LocalizedData.DisabledRouteInfo
                }
                if ($HighlightUnresolvedRoute) {
                    Paragraph $LocalizedData.UnresolvedInfo
                }
                BlankLine

                #region Route tables
                Section -Style Heading3 $LocalizedData.RouteHeading {

                    $SummaryInfo = foreach ($Table in $Routing.RouteTable) {
                        # A route table has no enable toggle in the WebUI. Its individual
                        # route entries do, and those keep their state at every level.
                        $Row = [Ordered]@{
                            $LocalizedData.TableName  = $Table.Description
                            $LocalizedData.RouteCount = @($Table.Route).Count
                        }

                        if ($InfoLevel.CallRouting -ge 5) {
                            $Row[$LocalizedData.State] = $Table.State
                        }

                        [PSCustomObject]$Row
                    }

                    $TableParams = @{
                        Name         = $LocalizedData.RouteSummary
                        List         = $false
                        ColumnWidths = if ($InfoLevel.CallRouting -ge 5) { 60, 20, 20 } else { 75, 25 }
                    }
                    if ($Report.ShowTableCaptions) {
                        $TableParams['Caption'] = "- $($TableParams.Name)"
                    }
                    $SummaryInfo | Table @TableParams

                    if ($InfoLevel.CallRouting -ge 2) {
                        foreach ($Table in $Routing.RouteTable) {
                            if (-not $Table.Route) {
                                continue
                            }

                            Section -Style Heading4 $Table.Description {

                                $RouteInfo = foreach ($Route in $Table.Route) {
                                    $Row = [Ordered]@{
                                        $LocalizedData.Order       = $Route.ExecutionOrder
                                        $LocalizedData.RouteName   = $Route.Description
                                        $LocalizedData.State       = $Route.State
                                        $LocalizedData.RouteType   = $Route.DestinationType
                                        # Deny and Trunk Group routes have no destination
                                        # signaling group, so the column is left empty rather
                                        # than implying one.
                                        $LocalizedData.Destination = if ($Route.Destination) { ($Route.Destination -join ', ') } else { '' }
                                        $LocalizedData.Transformation = $Route.TransformationTable
                                    }

                                    if ($InfoLevel.CallRouting -ge 3) {
                                        $Row[$LocalizedData.MediaOverride] = $Route.MediaOverride
                                        $Row[$LocalizedData.TimeOfDay] = $Route.TimeOfDay
                                    }

                                    [PSCustomObject]$Row
                                }

                                # One row per route entry, in order, so the two collections
                                # can be walked together. Critical is applied last so a broken
                                # reference outranks a disabled highlight on the same row.
                                if ($HighlightDisabledRoute -or $HighlightUnresolvedRoute) {
                                    for ($Index = 0; $Index -lt @($RouteInfo).Count; $Index++) {
                                        $Row = @($RouteInfo)[$Index]
                                        $Entry = @($Table.Route)[$Index]

                                        if ($HighlightDisabledRoute -and $Entry.State -eq $LocalizedData.Disabled) {
                                            $Row | Set-Style -Style Warning
                                        }

                                        if ($HighlightUnresolvedRoute -and $Entry.HasUnresolvedReference) {
                                            $Row | Set-Style -Style Critical
                                        }
                                    }
                                }

                                $TableParams = @{
                                    Name         = '{0} - {1}' -f $LocalizedData.RouteEntryTable, $Table.Description
                                    List         = $false
                                    ColumnWidths = if ($InfoLevel.CallRouting -ge 3) { 6, 22, 9, 10, 17, 18, 9, 9 } else { 8, 30, 10, 12, 20, 20 }
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $RouteInfo | Table @TableParams
                            }
                        }
                    }
                }
                #endregion Route tables

                #region Transformation tables
                if ($InfoLevel.CallRouting -ge 2 -and $Routing.TransformationTable) {
                    Section -Style Heading3 $LocalizedData.TransformHeading {

                        Paragraph $LocalizedData.MatchInfo
                        BlankLine

                        $TransformSummary = foreach ($Table in $Routing.TransformationTable) {
                            # As with route tables, the table itself has no enable toggle.
                            $Row = [Ordered]@{
                                $LocalizedData.TableName = $Table.Description
                                $LocalizedData.RuleCount = @($Table.Rule).Count
                            }

                            if ($InfoLevel.CallRouting -ge 5) {
                                $Row[$LocalizedData.State] = $Table.State
                            }

                            [PSCustomObject]$Row
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.TransformSummary
                            List         = $false
                            ColumnWidths = if ($InfoLevel.CallRouting -ge 5) { 60, 20, 20 } else { 75, 25 }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $TransformSummary | Table @TableParams

                        if ($InfoLevel.CallRouting -ge 3) {
                            foreach ($Table in $Routing.TransformationTable) {
                                if (-not $Table.Rule) {
                                    continue
                                }

                                Section -Style Heading4 $Table.Description {

                                    $RuleInfo = foreach ($Rule in $Table.Rule) {
                                        [PSCustomObject][Ordered]@{
                                            $LocalizedData.Order       = $Rule.ExecutionOrder
                                            $LocalizedData.State       = $Rule.State
                                            $LocalizedData.Requirement = $Rule.Requirement
                                            $LocalizedData.InputField  = $Rule.InputField
                                            $LocalizedData.InputValue  = $Rule.InputValue
                                            $LocalizedData.OutputField = $Rule.OutputField
                                            $LocalizedData.OutputValue = $Rule.OutputValue
                                        }
                                    }

                                    $TableParams = @{
                                        Name         = '{0} - {1}' -f $LocalizedData.RuleTable, $Table.Description
                                        List         = $false
                                        ColumnWidths = 6, 10, 12, 18, 18, 18, 18
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $RuleInfo | Table @TableParams
                                }
                            }
                        }
                    }
                }
                #endregion Transformation tables
            }
        } catch {
            Write-PScriboMessage -IsWarning "CallRouting: $($_.Exception.Message)"
        }
    }

    end {}
}
