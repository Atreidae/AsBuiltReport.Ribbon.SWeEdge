function Get-AbrRibbonSWeEdgeNetworking {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge networking section information.
    .DESCRIPTION
        Documents the network configuration of a Ribbon SBC in Word/HTML/Text formats using
        PScribo.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeNetworking
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Networking)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Xml = $script:RibbonConfig.RawXml
            $Interfaces = @(Resolve-AbrRibbonNetworkInterface -Config $script:RibbonConfig)

            if (-not $Interfaces) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            # IPv6 is rarely deployed on these appliances. The column is only worth showing
            # when at least one interface actually has an address.
            $HasIPv6 = [Bool]@($Interfaces | Where-Object {
                    -not [String]::IsNullOrWhiteSpace($_.IPv6Primary) -and $_.IPv6Primary -ne '::'
                }).Count

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                BlankLine

                #region Logical interfaces
                Section -Style Heading3 $LocalizedData.InterfaceHeading {

                    $InterfaceInfo = foreach ($Interface in $Interfaces) {
                        $Row = [Ordered]@{
                            $LocalizedData.InterfaceName = $Interface.DisplayName
                            $LocalizedData.IpAddress     = ConvertTo-AbrRibbonAddressText -Value $Interface.IPv4Primary -Placeholder $LocalizedData.NotSet
                            $LocalizedData.SubnetMask    = ConvertTo-AbrRibbonAddressText -Value $Interface.IPv4PrimaryMask -Placeholder $LocalizedData.NotSet
                        }

                        if ($InfoLevel.Networking -ge 3) {
                            $Row[$LocalizedData.SecondaryAddress] = ConvertTo-AbrRibbonAddressText -Value $Interface.IPv4Secondary -Placeholder $LocalizedData.NotSet
                        }

                        # IPv6 is rarely deployed. Showing an empty column on every interface
                        # is noise, so it appears only when at least one interface has one.
                        if ($InfoLevel.Networking -ge 3 -and $HasIPv6) {
                            $Row[$LocalizedData.IPv6Address] = ConvertTo-AbrRibbonAddressText -Value $Interface.IPv6Primary -Placeholder $LocalizedData.NotSet
                        }

                        if ($InfoLevel.Networking -ge 4) {
                            $Row[$LocalizedData.VlanTag] = if ($Interface.VlanTag) { $Interface.VlanTag } else { $LocalizedData.NotSet }
                        }

                        if ($InfoLevel.Networking -ge 5) {
                            $Row[$LocalizedData.SystemName] = $Interface.Name
                            $Row[$LocalizedData.InterfaceIndex] = $Interface.InterfaceIndex
                        }

                        [PSCustomObject]$Row
                    }

                    # One width per column, summing to 100. A mismatch renders in Text and
                    # HTML but fails the Word export with an index out of bounds error.
                    $Width = switch ($InfoLevel.Networking) {
                        { $_ -ge 5 } { if ($HasIPv6) { @(14, 13, 13, 13, 13, 10, 14, 10) } else { @(16, 15, 15, 15, 11, 16, 12) } }
                        4 { if ($HasIPv6) { @(20, 18, 18, 18, 16, 10) } else { @(24, 20, 20, 20, 16) } }
                        3 { if ($HasIPv6) { @(25, 20, 20, 17, 18) } else { @(28, 24, 24, 24) } }
                        default { @(34, 33, 33) }
                    }

                    $TableParams = @{
                        Name         = $LocalizedData.InterfaceTable
                        List         = $false
                        ColumnWidths = $Width
                    }
                    if ($Report.ShowTableCaptions) {
                        $TableParams['Caption'] = "- $($TableParams.Name)"
                    }
                    $InterfaceInfo | Table @TableParams
                }
                #endregion Logical interfaces

                #region VLANs
                if ($InfoLevel.Networking -ge 2) {
                    $Vlans = @($Xml.Configuration.SelectNodes("Token[@name='NodeHardware']/Token[@name='NetworkAdapter']/Token[@name='Bridge']/ID/ID") |
                            ConvertFrom-AbrRibbonIeNode |
                            Where-Object { $_.ClassName -eq 'NETSERV_VLAN_CFG_IE' })

                    if ($Vlans) {
                        Section -Style Heading3 $LocalizedData.VlanHeading {

                            $VlanInfo = foreach ($Vlan in $Vlans) {
                                [PSCustomObject][Ordered]@{
                                    $LocalizedData.VlanId          = $Vlan.vlan_id
                                    $LocalizedData.VlanDescription = $Vlan.vlan_description
                                    $LocalizedData.Enabled         = if ($Vlan.Enabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                }
                            }

                            $TableParams = @{
                                Name         = $LocalizedData.VlanTable
                                List         = $false
                                ColumnWidths = 20, 55, 25
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $VlanInfo | Table @TableParams
                        }
                    }
                }
                #endregion VLANs

                #region Static routes
                if ($InfoLevel.Networking -ge 2) {
                    $Routes = @($Xml.Configuration.SelectNodes("Token[@name='IPRouting']/Token[@name='StaticRoutes']/ID") | ConvertFrom-AbrRibbonIeNode)

                    if ($Routes) {
                        Section -Style Heading3 $LocalizedData.RouteHeading {

                            $RouteInfo = foreach ($Route in $Routes) {
                                # 0.0.0.0/0.0.0.0 is the default route. Naming it is clearer
                                # than printing the quad zero pair.
                                $Destination = if ($Route.ipDestinationAddr -eq '0.0.0.0' -and $Route.ipDestinationMask -eq '0.0.0.0') {
                                    $LocalizedData.DefaultRoute
                                } else {
                                    '{0} / {1}' -f $Route.ipDestinationAddr, $Route.ipDestinationMask
                                }

                                [PSCustomObject][Ordered]@{
                                    $LocalizedData.Destination = $Destination
                                    $LocalizedData.Gateway     = $Route.ipNexthopAddress
                                    $LocalizedData.Metric      = $Route.ipStaticRouteMetric
                                }
                            }

                            # A static route has no enable toggle in the WebUI, it either
                            # exists or it does not.
                            $TableParams = @{
                                Name         = $LocalizedData.RouteTable
                                List         = $false
                                ColumnWidths = 50, 30, 20
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $RouteInfo | Table @TableParams
                        }
                    }
                }
                #endregion Static routes

                #region DHCP
                if ($InfoLevel.Networking -ge 4) {
                    $Pools = @($Xml.Configuration.SelectNodes("Token[@name='DHCP']/Token[@name='DHCPPool']/ID") | ConvertFrom-AbrRibbonIeNode)

                    if ($Pools) {
                        Section -Style Heading3 $LocalizedData.DhcpHeading {

                            $PoolInfo = foreach ($Pool in $Pools) {
                                [PSCustomObject][Ordered]@{
                                    $LocalizedData.PoolName = $Pool.Description
                                    $LocalizedData.Enabled  = if ($Pool.Enabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                }
                            }

                            $TableParams = @{
                                Name         = $LocalizedData.DhcpPoolTable
                                List         = $false
                                ColumnWidths = 70, 30
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $PoolInfo | Table @TableParams
                        }
                    }
                }
                #endregion DHCP

                #region Static ARP
                if ($InfoLevel.Networking -ge 5) {
                    $Arp = @($Xml.Configuration.SelectNodes("Token[@name='IPRouting']/Token[@name='StaticARP']/ID") | ConvertFrom-AbrRibbonIeNode)

                    if ($Arp) {
                        Section -Style Heading3 $LocalizedData.ArpHeading {

                            $ArpInfo = foreach ($Entry in $Arp) {
                                [PSCustomObject][Ordered]@{
                                    $LocalizedData.IpAddress  = $Entry.ipAddress
                                    $LocalizedData.MacAddress = $Entry.macAddress
                                    $LocalizedData.Enabled    = if ($Entry.Enabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                }
                            }

                            $TableParams = @{
                                Name         = $LocalizedData.ArpTable
                                List         = $false
                                ColumnWidths = 40, 40, 20
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $ArpInfo | Table @TableParams
                        }
                    }
                }
                #endregion Static ARP
            }
        } catch {
            Write-PScriboMessage -IsWarning "Networking: $($_.Exception.Message)"
        }
    }

    end {}
}
