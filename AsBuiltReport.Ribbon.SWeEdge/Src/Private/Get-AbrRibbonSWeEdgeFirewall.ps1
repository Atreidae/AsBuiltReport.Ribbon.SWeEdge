function Get-AbrRibbonSWeEdgeFirewall {
    <#
    .SYNOPSIS
        Renders the firewall requirements section of a Ribbon SWeEdge As Built Report.
    .DESCRIPTION
        Presents the network flows the appliance needs, derived from its own configuration
        rather than from a generic vendor requirements list, followed by the access control
        list applied on the appliance itself.

        The section is controlled by the ShowFirewallTable report option as well as the
        InfoLevel, because the flow table is an aid for the network team rather than a record
        of configuration, and not every reader wants it in their document.
    .OUTPUTS
        None. Emits PScribo document objects.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Get-AbrRibbonSWeEdgeFirewall
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeFirewall
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Firewall)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Firewall = Resolve-AbrRibbonFirewallRule -Config $script:RibbonConfig

            if (-not $Firewall.Flow -and -not $Firewall.AccessControl) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            Section -Style Heading2 $LocalizedData.Heading {
                Paragraph $LocalizedData.SectionInfo
                BlankLine

                #region Derived flows
                if ($Firewall.Flow) {
                    Section -Style Heading3 $LocalizedData.FlowHeading {
                        Paragraph $LocalizedData.FlowInfo
                        BlankLine

                        $FlowInfo = foreach ($Rule in $Firewall.Flow) {
                            $Row = [Ordered]@{
                                $LocalizedData.Purpose     = $Rule.Purpose
                                $LocalizedData.Direction   = $Rule.Direction
                                $LocalizedData.Source      = $Rule.Source
                                $LocalizedData.Destination = $Rule.Destination
                                $LocalizedData.Protocol    = $Rule.Protocol
                                $LocalizedData.DestPort    = $Rule.DestinationPort
                            }

                            # The source port is only interesting on the flows where it is
                            # not ephemeral, so it earns a column only when the reader asked
                            # for detail.
                            if ($InfoLevel.Firewall -ge 3) {
                                $Row[$LocalizedData.SourcePort] = $Rule.SourcePort
                            }

                            if ($InfoLevel.Firewall -ge 3) {
                                $Row[$LocalizedData.Note] = $Rule.Note
                            }

                            [PSCustomObject]$Row
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.FlowTable
                            List         = $false
                            ColumnWidths = if ($InfoLevel.Firewall -ge 3) { 14, 7, 17, 17, 7, 8, 8, 22 } else { 20, 10, 26, 26, 8, 10 }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $FlowInfo | Table @TableParams
                    }
                }
                #endregion Derived flows

                #region Detected providers
                if ($Firewall.KnownPeer) {
                    Section -Style Heading3 $LocalizedData.PeerHeading {
                        Paragraph $LocalizedData.PeerInfo
                        BlankLine

                        $PeerInfo = foreach ($Peer in $Firewall.KnownPeer) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.Provider         = $Peer.Name
                                $LocalizedData.SignalingNetwork = $Peer.SignalingNetwork
                                $LocalizedData.MediaNetwork     = $Peer.MediaNetwork
                                $LocalizedData.MediaPort        = $Peer.MediaPort
                                $LocalizedData.RelayPort        = $Peer.RelayPort
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.PeerTable
                            List         = $false
                            ColumnWidths = 28, 20, 20, 16, 16
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $PeerInfo | Table @TableParams
                    }
                }
                #endregion Detected providers

                #region Address translation
                if ($Firewall.Nat) {
                    Section -Style Heading3 $LocalizedData.NatHeading {
                        Paragraph $LocalizedData.NatInfo
                        BlankLine

                        $NatInfo = foreach ($Entry in $Firewall.Nat) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.SignalingGroup = $Entry.Group
                                $LocalizedData.PrivateAddress = $Entry.Interface
                                $LocalizedData.PublicAddress  = $Entry.PublicAddress
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.NatTable
                            List         = $false
                            ColumnWidths = 44, 30, 26
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $NatInfo | Table @TableParams
                    }
                }
                #endregion Address translation

                #region On box access control list
                # The appliance's own rules are a separate concern from the upstream firewall
                # and run to several hundred lines on a default build, so they are reserved
                # for the most verbose level.
                if ($Firewall.AccessControl -and $InfoLevel.Firewall -ge 5) {
                    Section -Style Heading3 $LocalizedData.AclHeading {
                        Paragraph $LocalizedData.AclInfo
                        BlankLine

                        foreach ($List in $Firewall.AccessControl) {
                            if (-not $List.Rule) {
                                continue
                            }

                            Section -Style Heading4 ('{0} ({1})' -f $List.Description, $List.Family) {

                                $RuleInfo = foreach ($Rule in $List.Rule) {
                                    $Row = [Ordered]@{
                                        $LocalizedData.Action      = $Rule.Action
                                        $LocalizedData.Protocol    = $Rule.Protocol
                                        $LocalizedData.Source      = $Rule.Source
                                        $LocalizedData.SourcePort  = $Rule.SourcePort
                                        $LocalizedData.Destination = $Rule.Destination
                                        $LocalizedData.DestPort    = $Rule.DestPort
                                    }

                                    if ($InfoLevel.Firewall -ge 4) {
                                        $Row[$LocalizedData.Interface] = $Rule.Interface
                                        $Row[$LocalizedData.Precedence] = $Rule.Precedence
                                    }

                                    if ($InfoLevel.Firewall -ge 5) {
                                        $Row[$LocalizedData.State] = $Rule.State
                                    }

                                    [PSCustomObject]$Row
                                }

                                $TableParams = @{
                                    Name         = $LocalizedData.AclTable
                                    List         = $false
                                    ColumnWidths = switch ($InfoLevel.Firewall) {
                                        { $_ -ge 5 } { 8, 8, 17, 9, 17, 9, 16, 8, 8 }
                                        4 { 9, 9, 19, 10, 19, 10, 16, 8 }
                                        default { 12, 12, 24, 12, 28, 12 }
                                    }
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $RuleInfo | Table @TableParams
                            }
                        }
                    }
                }
                #endregion On box access control list
            }
        } catch {
            Write-PScriboMessage -IsWarning "Firewall: $($_.Exception.Message)"
        }
    }

    end {}
}
