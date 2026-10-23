function Get-AbrRibbonSWeEdgeTelephonyMapping {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge telephony mapping information.
    .DESCRIPTION
        Documents the cause code reroute, message translation, SIP to Q.850 and tone tables of
        a Ribbon SBC in Word/HTML/Text formats using PScribo.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeTelephonyMapping
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.TelephonyMapping)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Mapping = Resolve-AbrRibbonTelephonyMapping -Config $script:RibbonConfig

            $HasContent = $Mapping.RerouteTable -or $Mapping.MessageTranslation -or
                $Mapping.SipToQ850 -or $Mapping.Q850ToSip -or $Mapping.ToneTable

            if (-not $HasContent) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                BlankLine

                #region Reroute tables
                if ($Mapping.RerouteTable) {
                    Section -Style Heading3 $LocalizedData.RerouteHeading {

                        $RerouteInfo = foreach ($Table in $Mapping.RerouteTable) {
                            $Row = [Ordered]@{
                                $LocalizedData.TableName = $Table.Description
                                $LocalizedData.State     = $Table.State
                            }

                            # At summary level the codes alone are enough. Naming every cause
                            # is only useful when reviewing the table in detail.
                            $Row[$LocalizedData.CauseCodes] = if ($InfoLevel.TelephonyMapping -ge 3) {
                                ($Table.CauseName -join ', ')
                            } else {
                                ($Table.CauseCode -join ', ')
                            }

                            [PSCustomObject]$Row
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.RerouteTable
                            List         = $false
                            ColumnWidths = 30, 12, 58
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $RerouteInfo | Table @TableParams
                    }
                }
                #endregion Reroute tables

                #region Message translation tables
                if ($Mapping.MessageTranslation) {
                    Section -Style Heading3 $LocalizedData.MessageHeading {

                        $SummaryInfo = foreach ($Table in $Mapping.MessageTranslation) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.TableName  = $Table.Description
                                $LocalizedData.EntryCount = @($Table.Entry).Count
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.MessageTable
                            List         = $false
                            ColumnWidths = 75, 25
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $SummaryInfo | Table @TableParams

                        # The rules are what actually change the call, so they are worth
                        # showing as soon as the reader has asked for more than a summary.
                        if ($InfoLevel.TelephonyMapping -ge 3) {
                            foreach ($Table in $Mapping.MessageTranslation) {
                                if (-not $Table.Entry) {
                                    continue
                                }

                                Section -Style Heading4 $Table.Description {

                                    $EntryInfo = foreach ($Entry in $Table.Entry) {
                                        $Row = [Ordered]@{
                                            $LocalizedData.Rule        = $Entry.Description
                                            $LocalizedData.InMessage   = $Entry.InMessage
                                            $LocalizedData.OutMessage  = $Entry.OutMessage
                                            $LocalizedData.SendMessage = $Entry.SendMessage
                                        }

                                        if ($InfoLevel.TelephonyMapping -ge 4) {
                                            $Row[$LocalizedData.InIeType] = $Entry.InIeType
                                            $Row[$LocalizedData.OutIeType] = $Entry.OutIeType
                                            $Row[$LocalizedData.EarlyMedia] = $Entry.EarlyMediaStatus
                                            $Row[$LocalizedData.MediaCutThrough] = $Entry.MediaCutThrough
                                        }

                                        if ($InfoLevel.TelephonyMapping -ge 5) {
                                            $Row[$LocalizedData.PiPresent] = $Entry.PiPresent
                                            $Row[$LocalizedData.PiSelection] = $Entry.PiSelection
                                            $Row[$LocalizedData.PiValue] = $Entry.PiValue
                                            $Row[$LocalizedData.State] = $Entry.State
                                        }

                                        [PSCustomObject]$Row
                                    }

                                    $TableParams = @{
                                        Name         = $LocalizedData.MessageEntry
                                        List         = $false
                                        ColumnWidths = switch ($InfoLevel.TelephonyMapping) {
                                            { $_ -ge 5 } { 14, 9, 9, 9, 9, 9, 8, 9, 5, 5, 5, 9 }
                                            4 { 22, 12, 12, 12, 11, 11, 10, 10 }
                                            default { 40, 20, 20, 20 }
                                        }
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $EntryInfo | Table @TableParams
                                }
                            }
                        }
                    }
                }
                #endregion Message translation tables

                #region SIP and Q.850 cause mapping
                $CauseGroup = @(
                    @{ Rows = $Mapping.SipToQ850; Heading = $LocalizedData.SipQ850Heading; Caption = $LocalizedData.SipQ850Table; Entry = $LocalizedData.SipQ850Entry }
                    @{ Rows = $Mapping.Q850ToSip; Heading = $LocalizedData.Q850SipHeading; Caption = $LocalizedData.Q850SipTable; Entry = $LocalizedData.Q850SipEntry }
                )

                foreach ($Group in $CauseGroup) {
                    if (-not $Group.Rows) {
                        continue
                    }

                    Section -Style Heading3 $Group.Heading {

                        $SummaryInfo = foreach ($Table in $Group.Rows) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.TableName  = $Table.Description
                                $LocalizedData.EntryCount = @($Table.Entry).Count
                            }
                        }

                        $TableParams = @{
                            Name         = $Group.Caption
                            List         = $false
                            ColumnWidths = 75, 25
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $SummaryInfo | Table @TableParams

                        if ($InfoLevel.TelephonyMapping -ge 3) {
                            foreach ($Table in $Group.Rows) {
                                if (-not $Table.Entry) {
                                    continue
                                }

                                Section -Style Heading4 $Table.Description {

                                    $EntryInfo = foreach ($Entry in $Table.Entry) {
                                        # The cause is named where Q.850 defines one, so the
                                        # reader does not have to look the number up.
                                        $Row = [Ordered]@{
                                            $LocalizedData.SipResponse = $Entry.Sip
                                            $LocalizedData.Q850Cause   = $Entry.Q850Named
                                        }

                                        if ($InfoLevel.TelephonyMapping -ge 5) {
                                            $Row[$LocalizedData.State] = $Entry.State
                                        }

                                        [PSCustomObject]$Row
                                    }

                                    $TableParams = @{
                                        Name         = $Group.Entry
                                        List         = $false
                                        ColumnWidths = if ($InfoLevel.TelephonyMapping -ge 5) { 20, 60, 20 } else { 25, 75 }
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $EntryInfo | Table @TableParams
                                }
                            }
                        }
                    }
                }
                #endregion SIP and Q.850 cause mapping

                #region Tone tables
                if ($Mapping.ToneTable) {
                    Section -Style Heading3 $LocalizedData.ToneHeading {

                        $SummaryInfo = foreach ($Table in $Mapping.ToneTable) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.TableName  = $Table.Description
                                $LocalizedData.EntryCount = @($Table.Profile).Count
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.ToneTable
                            List         = $false
                            ColumnWidths = 75, 25
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $SummaryInfo | Table @TableParams

                        if ($InfoLevel.TelephonyMapping -ge 3) {
                            foreach ($Table in $Mapping.ToneTable) {
                                if (-not $Table.Profile) {
                                    continue
                                }

                                Section -Style Heading4 $Table.Description {

                                    $ToneInfo = foreach ($Tone in $Table.Profile) {
                                        # Which tones a table defines is useful on its own.
                                        # The frequencies and cadences only matter when
                                        # comparing against a national specification.
                                        $Row = [Ordered]@{
                                            $LocalizedData.ToneType = $Tone.ToneType
                                        }

                                        if ($InfoLevel.TelephonyMapping -ge 4) {
                                            $Row[$LocalizedData.Frequency] = ($Tone.Frequency -join ' / ')
                                            $Row[$LocalizedData.Amplitude] = ($Tone.Amplitude -join ' / ')
                                            $Row[$LocalizedData.CadenceOn] = $Tone.CadenceOn
                                            $Row[$LocalizedData.CadenceOff] = $Tone.CadenceOff
                                        }

                                        if ($InfoLevel.TelephonyMapping -ge 5) {
                                            $Row[$LocalizedData.Cadence2On] = $Tone.Cadence2On
                                            $Row[$LocalizedData.Cadence2Off] = $Tone.Cadence2Off
                                            $Row[$LocalizedData.State] = $Tone.State
                                        }

                                        [PSCustomObject]$Row
                                    }

                                    $TableParams = @{
                                        Name         = $LocalizedData.ToneEntry
                                        List         = $false
                                        ColumnWidths = switch ($InfoLevel.TelephonyMapping) {
                                            { $_ -ge 5 } { 18, 14, 14, 11, 11, 11, 11, 10 }
                                            4 { 24, 20, 20, 18, 18 }
                                            default { 100 }
                                        }
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    $ToneInfo | Table @TableParams
                                }
                            }
                        }
                    }
                }
                #endregion Tone tables
            }
        } catch {
            Write-PScriboMessage -IsWarning "TelephonyMapping: $($_.Exception.Message)"
        }
    }

    end {}
}
