function Get-AbrRibbonSWeEdgeSip {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge SIP information.
    .DESCRIPTION
        Documents the SIP server tables and profiles of a Ribbon SBC in Word/HTML/Text formats
        using PScribo.
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        Remote authorization tables are reported by name only. No credential material is
        rendered.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeSip
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.SIP)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Sip = Resolve-AbrRibbonSipConfiguration -Config $script:RibbonConfig

            if (-not $Sip.ServerTable -and -not $Sip.SipProfile) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                BlankLine

                #region Server tables
                if ($Sip.ServerTable) {
                    Section -Style Heading3 $LocalizedData.ServerHeading {

                        Paragraph $LocalizedData.OrderInfo

                        # A table using more than one TLS profile is almost always a mistake.
                        $Mixed = @($Sip.ServerTable | Where-Object { -not $_.TlsProfileConsistent })
                        if ($ReportConfig.HealthCheck.SIP.ConsistentTlsProfile -and $Mixed) {
                            Paragraph $LocalizedData.MixedTlsWarning
                        }

                        BlankLine

                        $SummaryInfo = foreach ($Table in $Sip.ServerTable) {
                            # A server table has no enable toggle in the WebUI.
                            $Row = [Ordered]@{
                                $LocalizedData.TableName   = $Table.Description
                                $LocalizedData.ServerCount = @($Table.Server).Count
                            }

                            if ($InfoLevel.SIP -ge 5) {
                                $Row[$LocalizedData.State] = $Table.State
                            }

                            [PSCustomObject]$Row
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.ServerSummary
                            List         = $false
                            ColumnWidths = if ($InfoLevel.SIP -ge 5) { 60, 20, 20 } else { 75, 25 }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $SummaryInfo | Table @TableParams

                        if ($InfoLevel.SIP -ge 2) {
                            foreach ($Table in $Sip.ServerTable) {
                                if (-not $Table.Server) {
                                    continue
                                }

                                Section -Style Heading4 $Table.Description {

                                    $ServerInfo = foreach ($Server in $Table.Server) {
                                        # Priority is the field administrators recognise, and
                                        # it already conveys the attempt order.
                                        $Row = [Ordered]@{
                                            $LocalizedData.ServerHost = $Server.Host
                                            $LocalizedData.Port       = $Server.Port
                                            $LocalizedData.Protocol   = $Server.Protocol
                                            $LocalizedData.Priority   = $Server.Priority
                                        }

                                        if ($InfoLevel.SIP -ge 3) {
                                            $Row[$LocalizedData.TlsProfile] = $Server.TlsProfile
                                            $Row[$LocalizedData.Monitor] = $Server.Monitor
                                            $Row[$LocalizedData.KeepAlive] = $Server.KeepAlive
                                            $Row[$LocalizedData.RemoteAuth] = $Server.RemoteAuth
                                        }

                                        if ($InfoLevel.SIP -ge 5) {
                                            $Row[$LocalizedData.Order] = $Server.ExecutionOrder
                                            $Row[$LocalizedData.State] = $Server.State
                                        }

                                        [PSCustomObject]$Row
                                    }

                                    $TableParams = @{
                                        Name         = '{0} - {1}' -f $LocalizedData.ServerTable, $Table.Description
                                        List         = $false
                                        ColumnWidths = switch ($InfoLevel.SIP) {
                                            { $_ -ge 5 } { 20, 6, 8, 7, 14, 8, 8, 12, 9, 8 }
                                            { $_ -ge 3 } { 24, 8, 9, 9, 18, 10, 10, 12 }
                                            default { 55, 15, 15, 15 }
                                        }
                                    }
                                    if ($Report.ShowTableCaptions) {
                                        $TableParams['Caption'] = "- $($TableParams.Name)"
                                    }

                                    # Highlight the odd one out rather than the whole table,
                                    # so the specific server stands out.
                                    if ($ReportConfig.HealthCheck.SIP.ConsistentTlsProfile -and
                                        -not $Table.TlsProfileConsistent -and
                                        $InfoLevel.SIP -ge 3) {

                                        $Common = @($Table.Server |
                                                Where-Object { $_.Protocol -eq 'TLS' } |
                                                Group-Object TlsProfile |
                                                Sort-Object Count -Descending |
                                                Select-Object -First 1).Name

                                        foreach ($Row in $ServerInfo) {
                                            if ($Row.$($LocalizedData.Protocol) -eq 'TLS' -and
                                                $Row.$($LocalizedData.TlsProfile) -ne $Common) {
                                                $Row | Set-Style -Style Warning -Property $LocalizedData.TlsProfile
                                            }
                                        }
                                    }

                                    $ServerInfo | Table @TableParams
                                }
                            }
                        }
                    }
                }
                #endregion Server tables

                #region SIP profiles
                if ($InfoLevel.SIP -ge 2 -and $Sip.SipProfile) {
                    Section -Style Heading3 $LocalizedData.ProfileHeading {

                        $ProfileInfo = foreach ($SipProfile in $Sip.SipProfile) {
                            $Row = [Ordered]@{
                                $LocalizedData.ProfileName  = $SipProfile.Description
                                $LocalizedData.UserAgent    = $SipProfile.UserAgent
                                $LocalizedData.SessionTimer = $SipProfile.SessionTimer
                            }

                            if ($InfoLevel.SIP -ge 3) {
                                $Row[$LocalizedData.StaticHost] = if ([String]::IsNullOrWhiteSpace($SipProfile.StaticHost)) { $LocalizedData.NotSet } else { $SipProfile.StaticHost }
                                $Row[$LocalizedData.SessionExpires] = $SipProfile.SessionExpires
                                $Row[$LocalizedData.SessionMinSe] = $SipProfile.SessionMinSe
                            }

                            [PSCustomObject]$Row
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.ProfileTable
                            List         = $false
                            ColumnWidths = if ($InfoLevel.SIP -ge 3) { 26, 14, 12, 24, 12, 12 } else { 50, 25, 25 }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $ProfileInfo | Table @TableParams
                    }
                }
                #endregion SIP profiles
            }
        } catch {
            Write-PScriboMessage -IsWarning "SIP: $($_.Exception.Message)"
        }
    }

    end {}
}
