function Get-AbrRibbonSWeEdgeMediaConfiguration {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge media section information.
    .DESCRIPTION
        Documents the media configuration of a Ribbon SBC in Word/HTML/Text formats using
        PScribo.
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        Crypto key material and key lifetimes are deliberately excluded.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeMediaConfiguration
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Media)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Media = Resolve-AbrRibbonMediaProfile -Config $script:RibbonConfig

            if (-not $Media.MediaList -and -not $Media.VoiceCodecProfile) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                BlankLine

                #region Media lists
                if ($Media.MediaList) {
                    Section -Style Heading3 $LocalizedData.ListHeading {

                        $ListInfo = foreach ($List in $Media.MediaList) {
                            $Row = [Ordered]@{
                                $LocalizedData.ListName = $List.Description
                                # Codec order is the preference order from the encoded
                                # sequence and must not be sorted.
                                $LocalizedData.Codecs   = ($List.CodecNames -join ', ')
                            }

                            if ($InfoLevel.Media -ge 3) {
                                $Row[$LocalizedData.CryptoProfile] = $List.CryptoProfileName
                            }

                            if ($InfoLevel.Media -ge 4) {
                                $Row[$LocalizedData.DtlsProfile] = $List.DtlsProfileName
                            }

                            if ($InfoLevel.Media -ge 5) {
                                $Row[$LocalizedData.Dscp] = $List.DSCP
                            }

                            [PSCustomObject]$Row
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.ListTable
                            List         = $false
                            ColumnWidths = switch ($InfoLevel.Media) {
                                { $_ -ge 5 } { 24, 30, 18, 18, 10 }
                                4 { 26, 34, 20, 20 }
                                3 { 30, 45, 25 }
                                default { 35, 65 }
                            }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $ListInfo | Table @TableParams

                        #region Media list detail
                        if ($InfoLevel.Media -ge 3) {
                            foreach ($List in $Media.MediaList) {
                                Section -Style Heading4 $List.Description {

                                    # Polarity is per field and was verified against the WebUI.
                                    # Several of these read 0 for Enabled, so they cannot share
                                    # a single conversion.
                                    $Detail = [Ordered]@{
                                        $LocalizedData.DeadCall         = if ($List.DeadCallDetection -eq '0') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                        $LocalizedData.SilenceSupp      = if ($List.SilenceSuppression -eq '0') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                        $LocalizedData.CodecPriority    = if ($List.EnforceCodecPriority -eq '0') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                        $LocalizedData.ModemPassthrough = if ($List.ModemRelay -eq '0') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                        $LocalizedData.FaxPassthrough   = if ($List.FaxRelay -eq '0') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                        # Normal polarity, unlike the flags above.
                                        $LocalizedData.FaxToneDetect    = if ($List.FAXToneDetection -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                                        $LocalizedData.ChangeSsrc       = if ($List.ChangeSSRCValue -eq '1') { $LocalizedData.Enable } else { $LocalizedData.Disable }
                                        $LocalizedData.RtcpMode         = if ($List.MediaRTCPMode -eq '0') { 'RTCP' } else { $LocalizedData.Unknown -f $List.MediaRTCPMode }
                                        $LocalizedData.DigitRelayType   = if ($List.DigitRelayType -eq '1') { 'RFC 2833/RFC 4733' } else { $LocalizedData.Unknown -f $List.DigitRelayType }
                                        $LocalizedData.DigitPayload     = $List.DigitRelayPayloadType
                                    }

                                    $TableParams = @{
                                        Name         = '{0} - {1}' -f $LocalizedData.DetailTable, $List.Description
                                        List         = $true
                                        ColumnWidths = 40, 60
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }
                                    [PSCustomObject]$Detail | Table @TableParams
                                }
                            }
                        }
                        #endregion Media list detail
                    }
                }
                #endregion Media lists

                #region Voice codec profiles
                if ($Media.VoiceCodecProfile) {
                    Section -Style Heading3 $LocalizedData.VoiceHeading {

                        $VoiceInfo = foreach ($Codec in $Media.VoiceCodecProfile) {
                            $Row = [Ordered]@{
                                $LocalizedData.CodecName   = $Codec.Description
                                $LocalizedData.PayloadType = $Codec.PayloadType
                                $LocalizedData.PacketTime  = $Codec.PTimeInMilliSeconds
                            }

                            if ($InfoLevel.Media -ge 3) {
                                $Row[$LocalizedData.BitRate] = $Codec.VoiceRateInBitsPerSecond
                            }

                            [PSCustomObject]$Row
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.VoiceTable
                            List         = $false
                            ColumnWidths = if ($InfoLevel.Media -ge 3) { 40, 20, 20, 20 } else { 50, 25, 25 }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $VoiceInfo | Table @TableParams
                    }
                }
                #endregion Voice codec profiles

                #region Fax codec profiles
                if ($InfoLevel.Media -ge 2 -and $Media.FaxCodecProfile) {
                    Section -Style Heading3 $LocalizedData.FaxHeading {

                        $FaxInfo = foreach ($Codec in $Media.FaxCodecProfile) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.CodecName = $Codec.Description
                                $LocalizedData.Enabled   = if ($Codec.Enabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.FaxTable
                            List         = $false
                            ColumnWidths = 70, 30
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $FaxInfo | Table @TableParams
                    }
                }
                #endregion Fax codec profiles

                #region Crypto profiles
                if ($InfoLevel.Media -ge 4 -and $Media.CryptoProfile) {
                    Section -Style Heading3 $LocalizedData.CryptoHeading {

                        # Key lifetime and key identifier fields are omitted on purpose.
                        $CryptoInfo = foreach ($Crypto in $Media.CryptoProfile) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.ListName    = $Crypto.Description
                                $LocalizedData.CryptoSuite = $Crypto.CryptoSuite
                                $LocalizedData.Operation   = $Crypto.OperationOption
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.CryptoTable
                            List         = $false
                            ColumnWidths = 50, 25, 25
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $CryptoInfo | Table @TableParams
                    }
                }
                #endregion Crypto profiles
            }
        } catch {
            Write-PScriboMessage -IsWarning "Media: $($_.Exception.Message)"
        }
    }

    end {}
}

