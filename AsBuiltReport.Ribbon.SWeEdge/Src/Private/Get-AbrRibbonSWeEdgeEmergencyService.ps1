function Get-AbrRibbonSWeEdgeEmergencyService {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge emergency services information.
    .DESCRIPTION
        Documents the emergency services configuration of a Ribbon SBC in Word/HTML/Text
        formats using PScribo.
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        Notification manager credentials are never rendered.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeEmergencyService
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.EmergencyService)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Emergency = Resolve-AbrRibbonEmergencyService -Config $script:RibbonConfig

            if (-not $Emergency.Configuration -and -not $Emergency.CallbackPool -and -not $Emergency.NotificationManager) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                BlankLine

                #region Configuration
                if ($Emergency.Configuration) {
                    Section -Style Heading3 $LocalizedData.ConfigHeading {

                        $ConfigInfo = [Ordered]@{
                            $LocalizedData.ServiceState = if ($Emergency.Configuration.Enabled -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                            $LocalizedData.CallStatus   = $Emergency.Configuration.CallStatusDuration
                            $LocalizedData.Preempt      = if ($Emergency.Configuration.PreemptNonEmergencyCalls -eq '1') { $LocalizedData.Enabled } else { $LocalizedData.Disabled }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.ConfigTable
                            List         = $true
                            ColumnWidths = 40, 60
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        [PSCustomObject]$ConfigInfo | Table @TableParams
                    }
                }
                #endregion Configuration

                #region Callback pools
                if ($Emergency.CallbackPool) {
                    Section -Style Heading3 $LocalizedData.CallbackHeading {

                        $PoolInfo = foreach ($Pool in $Emergency.CallbackPool) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.PoolName        = $Pool.Description
                                $LocalizedData.PsapNumber      = $Pool.PsapNumber
                                $LocalizedData.CallbackNumbers = if ($Pool.CallbackNumber) { ($Pool.CallbackNumber -join ', ') } else { $LocalizedData.None }
                                $LocalizedData.State           = $Pool.State
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.CallbackTable
                            List         = $false
                            ColumnWidths = 28, 17, 40, 15
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $PoolInfo | Table @TableParams
                    }
                }
                #endregion Callback pools

                #region Notification managers
                if ($Emergency.NotificationManager) {
                    Section -Style Heading3 $LocalizedData.NotifyHeading {

                        $NotifyInfo = foreach ($Manager in $Emergency.NotificationManager) {
                            $Row = [Ordered]@{
                                $LocalizedData.NotifyName = $Manager.Description
                                $LocalizedData.Recipients = if ($Manager.Recipient) { ($Manager.Recipient -join ', ') } else { $LocalizedData.None }
                                $LocalizedData.State      = $Manager.State
                            }

                            if ($InfoLevel.EmergencyService -ge 3) {
                                $Row[$LocalizedData.NotifyMessage] = $Manager.Message
                                $Row[$LocalizedData.MonitorInterval] = $Manager.MonitoringInterval
                                $Row[$LocalizedData.ClientId] = $Manager.ClientId
                            }

                            [PSCustomObject]$Row
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.NotifyTable
                            List         = $false
                            ColumnWidths = if ($InfoLevel.EmergencyService -ge 3) { 18, 26, 10, 18, 12, 16 } else { 30, 50, 20 }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $NotifyInfo | Table @TableParams
                    }
                }
                #endregion Notification managers
            }
        } catch {
            Write-PScriboMessage -IsWarning "EmergencyService: $($_.Exception.Message)"
        }
    }

    end {}
}
