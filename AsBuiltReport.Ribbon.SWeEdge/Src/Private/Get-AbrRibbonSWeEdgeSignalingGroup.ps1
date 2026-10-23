function Get-AbrRibbonSWeEdgeSignalingGroup {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge signaling group information.
    .DESCRIPTION
        Documents the signaling groups of a Ribbon SBC in Word/HTML/Text formats using
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
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeSignalingGroup
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.SignalingGroup)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Groups = @(Resolve-AbrRibbonSignalingGroup -Config $script:RibbonConfig)

            if (-not $Groups) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            # A drained signaling group is the dangerous state. It still answers OPTIONS,
            # so monitoring shows it up, but it rejects any call offered to it with a 4xx.
            # Draining is a maintenance step, so finding one in a finished build usually
            # means somebody forgot to put it back into service. Only explain this to the
            # reader when the health check is on AND there is actually one to explain.
            $HighlightDrain = [bool]$ReportConfig.HealthCheck.SignalingGroup.DrainState -and
                ($Groups | Where-Object { $_.State -eq $LocalizedData.Drain })

            # A disabled group is a deliberate act rather than a fault, but it is routinely
            # the reason a trunk that looks configured does not carry calls, so it is worth
            # pointing at rather than leaving the reader to scan the State column.
            $HighlightDisabled = [bool]$ReportConfig.HealthCheck.SignalingGroup.DisabledGroup -and
                ($Groups | Where-Object { $_.State -eq $LocalizedData.Disabled })

            # A reference that no longer resolves means the referenced object was deleted and
            # the reference left behind. The group does not behave the way the configuration
            # reads, so this is a fault rather than a choice and is highlighted accordingly.
            $HighlightUnresolved = [bool]$ReportConfig.HealthCheck.SignalingGroup.UnresolvedReference -and
                ($Groups | Where-Object { $_.HasUnresolvedReference })

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                if ($HighlightDrain) {
                    Paragraph $LocalizedData.DrainInfo
                }
                if ($HighlightDisabled) {
                    Paragraph $LocalizedData.DisabledInfo
                }
                if ($HighlightUnresolved) {
                    Paragraph $LocalizedData.UnresolvedInfo
                }
                if ($Groups | Where-Object { $_.IsRecorder }) {
                    Paragraph $LocalizedData.RecorderInfo
                }
                BlankLine

                #region Summary
                $SummaryInfo = foreach ($Group in $Groups) {
                    $Row = [Ordered]@{
                        $LocalizedData.GroupId    = $Group.ID
                        $LocalizedData.GroupType  = $Group.Type
                        $LocalizedData.GroupName  = $Group.Description
                        $LocalizedData.State      = $Group.State
                        $LocalizedData.RouteTable = $Group.RouteTableName
                    }

                    if ($InfoLevel.SignalingGroup -ge 2) {
                        $Row[$LocalizedData.MediaList] = $Group.MediaListName
                        $Row[$LocalizedData.SipServer] = $Group.SipServerName
                    }

                    [PSCustomObject]$Row
                }

                # One summary row is produced per group, in order, so the two collections can
                # be walked together rather than matched back up by identifier. Critical is
                # applied last so a broken reference outranks a state highlight on the same
                # row.
                if ($HighlightDrain -or $HighlightDisabled -or $HighlightUnresolved) {
                    for ($Index = 0; $Index -lt @($SummaryInfo).Count; $Index++) {
                        $Row = @($SummaryInfo)[$Index]
                        $Group = @($Groups)[$Index]

                        if (($HighlightDrain -and $Group.State -eq $LocalizedData.Drain) -or
                            ($HighlightDisabled -and $Group.State -eq $LocalizedData.Disabled)) {
                            $Row | Set-Style -Style Warning
                        }

                        if ($HighlightUnresolved -and $Group.HasUnresolvedReference) {
                            $Row | Set-Style -Style Critical
                        }
                    }
                }

                $TableParams = @{
                    Name         = $LocalizedData.SummaryTable
                    List         = $false
                    ColumnWidths = if ($InfoLevel.SignalingGroup -ge 2) { 8, 8, 22, 10, 18, 17, 17 } else { 10, 10, 40, 15, 25 }
                }
                if ($Report.ShowTableCaptions) {
                    $TableParams['Caption'] = "- $($TableParams.Name)"
                }
                $SummaryInfo | Table @TableParams
                #endregion Summary

                #region Per group detail
                if ($InfoLevel.SignalingGroup -ge 3) {
                    foreach ($Group in $Groups) {
                        Section -Style Heading3 ('{0} ({1})' -f $Group.Description, $Group.Type) {

                            $Detail = [Ordered]@{
                                $LocalizedData.State      = $Group.State
                                $LocalizedData.RouteTable = $Group.RouteTableName
                                $LocalizedData.MediaList  = $Group.MediaListName
                            }

                            # Physical ports only exist on ISDN and CAS groups.
                            if (-not [String]::IsNullOrWhiteSpace($Group.Port)) {
                                $Detail[$LocalizedData.PhysicalPort] = $Group.Port
                            }

                            if ($Group.Type -eq 'SIP') {
                                $Detail[$LocalizedData.SipProfile] = $Group.SipProfileName
                                $Detail[$LocalizedData.SipServer] = $Group.SipServerName
                                $Detail[$LocalizedData.SignalingIf] = $Group.SignalingInterface
                                $Detail[$LocalizedData.MediaIf] = $Group.MediaInterface

                                $Detail[$LocalizedData.ListenPorts] = if ($Group.ListenPort) {
                                    # The TLS profile only means anything on a TLS port, and
                                    # only at the level where the reader asked for detail.
                                    (($Group.ListenPort | ForEach-Object {
                                        if ($InfoLevel.SignalingGroup -ge 4 -and -not [String]::IsNullOrWhiteSpace($_.TlsProfile)) {
                                            '{0}/{1} ({2})' -f $_.Port, $_.Protocol, $_.TlsProfile
                                        } else {
                                            '{0}/{1}' -f $_.Port, $_.Protocol
                                        }
                                    }) -join ', ')
                                } else {
                                    $LocalizedData.None
                                }

                                $Detail[$LocalizedData.FederatedHosts] = if ($Group.FederatedHost) {
                                    ($Group.FederatedHost -join ', ')
                                } else {
                                    $LocalizedData.None
                                }

                                $Detail[$LocalizedData.NatPublic] = ConvertTo-AbrRibbonAddressText -Value $Group.NatPublicAddress -Placeholder $LocalizedData.NotSet
                                $Detail[$LocalizedData.InboundNat] = if ($Group.InboundNatDetect -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }

                                # Private media source only applies when media optimization is
                                # enabled, otherwise the value is inert and would mislead.
                                if ($Group.MediaOptimization -eq '1') {
                                    $Detail[$LocalizedData.PrivateMedia] = $Group.PrivateMediaSource
                                }

                                $Detail[$LocalizedData.OutboundProxy] = if ([String]::IsNullOrWhiteSpace($Group.OutboundProxy)) {
                                    $LocalizedData.NotSet
                                } elseif ([String]::IsNullOrWhiteSpace($Group.OutboundProxyPort)) {
                                    $Group.OutboundProxy
                                } else {
                                    '{0}:{1}' -f $Group.OutboundProxy, $Group.OutboundProxyPort
                                }

                                # Message manipulation changes what the far end actually
                                # receives, so it belongs with the rest of the detail rather
                                # than behind an advanced level. The resolver already renders
                                # an empty list as --None--.
                                $Detail[$LocalizedData.IngressRules] = $Group.IngressMessageRule
                                $Detail[$LocalizedData.EgressRules] = $Group.EgressMessageRule
                                $Detail[$LocalizedData.SipToQ850] = $Group.SipToQ850Table
                                $Detail[$LocalizedData.Q850ToSip] = $Group.Q850ToSipTable
                            }

                            $Detail[$LocalizedData.ToneTable] = $Group.ToneTableName
                            $Detail[$LocalizedData.ActionSet] = $Group.ActionSetName

                            if (-not [String]::IsNullOrWhiteSpace($Group.Channels)) {
                                $Detail[$LocalizedData.Channels] = $Group.Channels
                            }

                            #region Adv Detailed
                            if ($InfoLevel.SignalingGroup -ge 4) {

                                # Media handling. Reported for every group type because a
                                # proxied group behaves very differently to a DSP one when
                                # troubleshooting media paths.
                                if (-not [String]::IsNullOrWhiteSpace($Group.AudioMode)) {
                                    $Detail[$LocalizedData.AudioMode] = $Group.AudioMode
                                }
                                if (-not [String]::IsNullOrWhiteSpace($Group.VideoMode)) {
                                    $Detail[$LocalizedData.VideoMode] = $Group.VideoMode
                                }

                                if ($Group.Type -eq 'SIP') {
                                    $Detail[$LocalizedData.ServerSelection] = $Group.ServerSelection
                                    $Detail[$LocalizedData.NatTraversal] = $Group.NatTraversal
                                }

                                # Populated only on ISDN groups, so an empty value means the
                                # group is not ISDN rather than that the setting is unset.
                                if (-not [String]::IsNullOrWhiteSpace($Group.IsdnSwitchVariant)) {
                                    $Detail[$LocalizedData.IsdnVariant] = $Group.IsdnSwitchVariant
                                    $Detail[$LocalizedData.IsdnOrientation] = $Group.IsdnOrientation
                                    $Detail[$LocalizedData.IsdnHuntMethod] = $Group.IsdnHuntMethod
                                    $Detail[$LocalizedData.IsdnChannel] = $Group.IsdnIndicatedChan
                                }
                            }
                            #endregion Adv Detailed

                            $TableParams = @{
                                Name         = '{0} - {1}' -f $LocalizedData.DetailTable, $Group.Description
                                List         = $true
                                ColumnWidths = 40, 60
                            }
                            if ($Report.ShowTableCaptions) {
                                $TableParams['Caption'] = "- $($TableParams.Name)"
                            }
                            [PSCustomObject]$Detail | Table @TableParams

                            #region Comprehensive
                            # The protocol switches are a long list of Enabled/Disabled rows
                            # that would swamp the detail table, so they get their own two
                            # column table and only at the level that asked for everything.
                            if ($InfoLevel.SignalingGroup -ge 5 -and $Group.Type -eq 'SIP') {

                                $OptionInfo = @(
                                    [Ordered]@{ Name = $LocalizedData.ChallengeRequest; Value = $Group.ChallengeRequest }
                                    [Ordered]@{ Name = $LocalizedData.Early183; Value = $Group.Early183 }
                                    [Ordered]@{ Name = $LocalizedData.IceSupport; Value = $Group.IceSupport }
                                    [Ordered]@{ Name = $LocalizedData.RegisterKeepAlive; Value = $Group.RegisterKeepAlive }
                                    [Ordered]@{ Name = $LocalizedData.RtcpMultiplexing; Value = $Group.RtcpMultiplexing }
                                    [Ordered]@{ Name = $LocalizedData.QoeReporting; Value = $Group.QoeReporting }
                                ) | ForEach-Object {
                                    [PSCustomObject][Ordered]@{
                                        $LocalizedData.Option  = $_.Name
                                        $LocalizedData.Setting = $_.Value
                                    }
                                }

                                $TableParams = @{
                                    Name         = '{0} - {1}' -f $LocalizedData.OptionsTable, $Group.Description
                                    List         = $false
                                    ColumnWidths = 60, 40
                                }
                                if ($Report.ShowTableCaptions) {
                                    $TableParams['Caption'] = "- $($TableParams.Name)"
                                }
                                $OptionInfo | Table @TableParams
                            }
                            #endregion Comprehensive
                        }
                    }
                }
                #endregion Per group detail
            }
        } catch {
            Write-PScriboMessage -IsWarning "SignalingGroup: $($_.Exception.Message)"
        }
    }

    end {}
}
