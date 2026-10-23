function Get-AbrRibbonSWeEdgeSystem {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge system section information.
    .DESCRIPTION
        Documents the system level configuration of a Ribbon SBC in Word/HTML/Text formats
        using PScribo.
    .NOTES
        Version:    0.2.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeSystem
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.System)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Xml = $script:RibbonConfig.RawXml

            # System level settings are a singleton, the IE sits directly under the token
            # rather than being wrapped in an ID element.
            $SystemNet = ConvertFrom-AbrRibbonIeNode -Node $Xml.Configuration.SelectSingleNode("Token[@name='System']/Token[@name='SystemNet']/IE")

            if (-not $SystemNet) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                BlankLine

                #region Node information
                Section -Style Heading3 $LocalizedData.NodeHeading {

                    $NodeInfo = [Ordered]@{
                        $LocalizedData.NodeName      = $SystemNet.NodeName
                        $LocalizedData.DomainName    = $SystemNet.DomainName
                        $LocalizedData.PlatformType  = $script:RibbonConfig.PlatformType
                        $LocalizedData.SystemRelease = $script:RibbonConfig.SystemRelease
                    }

                    if ($InfoLevel.System -ge 2) {
                        $NodeInfo[$LocalizedData.Contact] = if ([String]::IsNullOrWhiteSpace($SystemNet.sysContact)) { $LocalizedData.NotSet } else { $SystemNet.sysContact }
                        $NodeInfo[$LocalizedData.Location] = if ([String]::IsNullOrWhiteSpace($SystemNet.sysLocation)) { $LocalizedData.NotSet } else { $SystemNet.sysLocation }
                        $NodeInfo[$LocalizedData.Description] = if ([String]::IsNullOrWhiteSpace($SystemNet.sysDescription)) { $LocalizedData.NotSet } else { $SystemNet.sysDescription }
                    }

                    if ($InfoLevel.System -ge 4) {
                        $NodeInfo[$LocalizedData.CountryCode] = $SystemNet.CountryCode
                    }

                    $TableParams = @{
                        Name         = $LocalizedData.NodeTable
                        List         = $true
                        ColumnWidths = 40, 60
                    }
                    if ($Report.ShowTableCaptions) {
                        $TableParams['Caption'] = "- $($TableParams.Name)"
                    }
                    [PSCustomObject]$NodeInfo | Table @TableParams
                }
                #endregion Node information

                #region Time and NTP
                # An SBC with no time source is a real fault rather than an untidy setting.
                # Certificate validity, call detail records and log correlation all depend on
                # the clock, and drift presents as TLS failures that look like certificate
                # problems. Only a complete absence of time sync is flagged: a disabled
                # secondary alongside an enabled primary is an ordinary configuration.
                # The table itself only renders at InfoLevel 2, so the check cannot justify
                # a paragraph below that level.
                $HighlightNtp = [bool]$ReportConfig.HealthCheck.System.NtpEnabled -and
                    $InfoLevel.System -ge 2 -and
                    $SystemNet.IsNtp1Enabled -ne '1' -and $SystemNet.IsNtp2Enabled -ne '1'

                if ($InfoLevel.System -ge 2) {
                    Section -Style Heading3 $LocalizedData.TimeHeading {

                        Paragraph ('{0}: {1}' -f $LocalizedData.TimeZone, $SystemNet.TimeZoneGeoName)
                        if ($HighlightNtp) {
                            Paragraph $LocalizedData.NtpInfo
                        }
                        BlankLine

                        # Ribbon writes 0.0.0.0 rather than an empty value when a server is
                        # not configured, so it is treated as unset here.
                        $TimeInfo = @(
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.NtpServer        = $LocalizedData.NtpPrimary
                                $LocalizedData.NtpEnabled       = if ($SystemNet.IsNtp1Enabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                $LocalizedData.HostName         = if ([String]::IsNullOrWhiteSpace($SystemNet.Ntp1ServerName) -or $SystemNet.Ntp1ServerName -eq '0.0.0.0') { $LocalizedData.NotSet } else { $SystemNet.Ntp1ServerName }
                                $LocalizedData.NtpAuthenticated = if ($SystemNet.IsNtp1AuthEnabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                            }
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.NtpServer        = $LocalizedData.NtpSecondary
                                $LocalizedData.NtpEnabled       = if ($SystemNet.IsNtp2Enabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                $LocalizedData.HostName         = if ([String]::IsNullOrWhiteSpace($SystemNet.Ntp2ServerName) -or $SystemNet.Ntp2ServerName -eq '0.0.0.0') { $LocalizedData.NotSet } else { $SystemNet.Ntp2ServerName }
                                $LocalizedData.NtpAuthenticated = if ($SystemNet.IsNtp2AuthEnabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                            }
                        )

                        # Both rows are disabled whenever this fires, by definition of the
                        # check, so every Enabled cell in the table is flagged.
                        if ($HighlightNtp) {
                            foreach ($Row in $TimeInfo) {
                                $Row | Set-Style -Style Critical -Property $LocalizedData.NtpEnabled
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.TimeTable
                            List         = $false
                            ColumnWidths = 20, 15, 45, 20
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $TimeInfo | Table @TableParams
                    }
                }
                #endregion Time and NTP

                #region DNS
                if ($InfoLevel.System -ge 2) {
                    Section -Style Heading3 $LocalizedData.DnsHeading {

                        $DnsInfo = [Ordered]@{
                            $LocalizedData.DnsPrimary   = ConvertTo-AbrRibbonAddressText -Value $SystemNet.PrimaryDNSServer -Placeholder $LocalizedData.NotSet
                            $LocalizedData.DnsSecondary = ConvertTo-AbrRibbonAddressText -Value $SystemNet.SecondaryDNSServer -Placeholder $LocalizedData.NotSet
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.DnsTable
                            List         = $true
                            ColumnWidths = 40, 60
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        [PSCustomObject]$DnsInfo | Table @TableParams

                        if ($InfoLevel.System -ge 3) {
                            # Split DNS entries are child rows of the split DNS list row.
                            $SplitDns = @($Xml.Configuration.SelectNodes("Token[@name='System']/Token[@name='SplitDnsList']/ID/ID") | ConvertFrom-AbrRibbonIeNode)

                            if ($SplitDns) {
                                Section -Style Heading4 $LocalizedData.SplitDnsHeading {

                                    $SplitDnsInfo = foreach ($Entry in $SplitDns) {
                                        # The WebUI has no enable toggle for a split DNS entry.
                                        # It either exists or it does not, so the state is only
                                        # shown at the most verbose level.
                                        $Row = [Ordered]@{
                                            $LocalizedData.SplitDnsDomain = $Entry.DomainName
                                            $LocalizedData.SplitDnsServer = $Entry.DNSServerIP
                                        }

                                        if ($InfoLevel.System -ge 5) {
                                            $Row[$LocalizedData.Enabled] = if ($Entry.Enabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                        }

                                        [PSCustomObject]$Row
                                    }

                                    $TableParams = @{
                                        Name         = $LocalizedData.SplitDnsTable
                                        List         = $false
                                        ColumnWidths = if ($InfoLevel.System -ge 5) { 50, 30, 20 } else { 60, 40 }
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $SplitDnsInfo | Table @TableParams
                                }
                            }
                        }
                    }
                }
                #endregion DNS

                #region Static hosts
                if ($InfoLevel.System -ge 3) {
                    $HostEntry = @($Xml.Configuration.SelectNodes("Token[@name='System']/Token[@name='HOSTS']/ID") | ConvertFrom-AbrRibbonIeNode)

                    if ($HostEntry) {
                        Section -Style Heading3 $LocalizedData.HostsHeading {

                            $HostInfo = foreach ($Entry in $HostEntry) {
                                # As with split DNS, a static host entry has no enable toggle.
                                $Row = [Ordered]@{
                                    $LocalizedData.HostName  = $Entry.HostName
                                    $LocalizedData.IpAddress = $Entry.IPAddress
                                }

                                if ($InfoLevel.System -ge 5) {
                                    $Row[$LocalizedData.Enabled] = if ($Entry.Enabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                }

                                [PSCustomObject]$Row
                            }

                            $TableParams = @{
                                Name         = $LocalizedData.HostsTable
                                List         = $false
                                ColumnWidths = if ($InfoLevel.System -ge 5) { 50, 30, 20 } else { 60, 40 }
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            $HostInfo | Sort-Object $LocalizedData.HostName | Table @TableParams
                        }
                    }
                }
                #endregion Static hosts

                #region Media system settings
                if ($InfoLevel.System -ge 3) {
                    $MediaSystem = ConvertFrom-AbrRibbonIeNode -Node $Xml.Configuration.SelectSingleNode("Token[@name='System']/Token[@name='Media']/IE")

                    if ($MediaSystem) {
                        Section -Style Heading3 $LocalizedData.MediaHeading {

                            $PortStart = [Int]$MediaSystem.RTPRTCP_PortStart
                            $PortCount = [Int]$MediaSystem.RTPRTCP_PortCount

                            $MediaInfo = [Ordered]@{
                                $LocalizedData.RtpPortRange   = '{0} - {1}' -f $PortStart, ($PortStart + $PortCount - 1)
                                $LocalizedData.MediaDryupTime = $MediaSystem.MediaDryupTime
                            }

                            if ($InfoLevel.System -ge 4) {
                                $MediaInfo[$LocalizedData.DhcpServer] = if ($SystemNet.IsDHCPServerEnabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                            }

                            $TableParams = @{
                                Name         = $LocalizedData.MediaTable
                                List         = $true
                                ColumnWidths = 40, 60
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            [PSCustomObject]$MediaInfo | Table @TableParams
                        }
                    }
                }
                #endregion Media system settings
            }
        } catch {
            Write-PScriboMessage -IsWarning "System: $($_.Exception.Message)"
        }
    }

    end {}
}
