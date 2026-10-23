function Get-AbrRibbonSWeEdgeLogging {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge logging and monitoring information.
    .DESCRIPTION
        Documents the syslog, SNMP and subsystem logging configuration of a Ribbon SBC in
        Word/HTML/Text formats using PScribo.
    .NOTES
        Version:    0.2.0
        Author:     James Arber

        SNMP community strings are never rendered.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeLogging
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.Logging)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Logging = Resolve-AbrRibbonLogging -Config $script:RibbonConfig

            if (-not $Logging.SyslogServer -and -not $Logging.SnmpManager -and -not $Logging.SubsystemLogLevel) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            # Trace and Debug left enabled is an operational problem rather than a
            # configuration choice, so it is highlighted. Only explain the highlighting to
            # the reader when the health check is on AND something is actually flagged.
            $VerboseSyslog = @($Logging.SyslogServer | Where-Object { $_.IsVerbose }).Address
            $VerboseSubsystem = @($Logging.SubsystemLogLevel | Where-Object { $_.IsVerbose }).Subsystem
            # The subsystem table only renders at InfoLevel 3, so a verbose subsystem cannot
            # justify the paragraph below that level.
            $HighlightVerbose = [bool]$ReportConfig.HealthCheck.Logging.VerboseLogging -and
                ($VerboseSyslog -or ($InfoLevel.Logging -ge 3 -and $VerboseSubsystem))

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                if ($HighlightVerbose) {
                    Paragraph $LocalizedData.VerboseInfo
                }
                BlankLine

                #region Syslog
                if ($Logging.SyslogServer) {
                    Section -Style Heading3 $LocalizedData.SyslogHeading {

                        $SyslogInfo = foreach ($Server in $Logging.SyslogServer) {
                            $Row = [Ordered]@{
                                $LocalizedData.Address   = $Server.Address
                                $LocalizedData.Port      = $Server.Port
                                $LocalizedData.Transport = $Server.Transport
                                $LocalizedData.Level     = $Server.Level
                                $LocalizedData.State     = $Server.State
                            }

                            if ($InfoLevel.Logging -ge 3) {
                                $Row[$LocalizedData.Facility] = $Server.Facility
                            }

                            [PSCustomObject]$Row
                        }

                        if ($HighlightVerbose) {
                            foreach ($Row in $SyslogInfo) {
                                if ($Row.$($LocalizedData.Address) -in $VerboseSyslog) {
                                    $Row | Set-Style -Style Warning -Property $LocalizedData.Level
                                }
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.SyslogTable
                            List         = $false
                            ColumnWidths = if ($InfoLevel.Logging -ge 3) { 32, 10, 12, 16, 14, 16 } else { 40, 12, 14, 18, 16 }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $SyslogInfo | Table @TableParams
                    }
                }
                #endregion Syslog

                #region SNMP
                if ($Logging.SnmpManager) {
                    Section -Style Heading3 $LocalizedData.SnmpHeading {

                        # Community strings are credentials and are not available here.
                        $SnmpInfo = foreach ($Manager in $Logging.SnmpManager) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.Address     = $Manager.Address
                                $LocalizedData.Version     = $Manager.Version
                                $LocalizedData.TrapEnabled = $Manager.TrapEnabled
                                $LocalizedData.State       = $Manager.State
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.SnmpTable
                            List         = $false
                            ColumnWidths = 40, 20, 20, 20
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $SnmpInfo | Table @TableParams
                    }
                }
                #endregion SNMP

                #region Subsystem log levels
                if ($InfoLevel.Logging -ge 3 -and $Logging.SubsystemLogLevel) {
                    Section -Style Heading3 $LocalizedData.DebugHeading {

                        $LevelInfo = foreach ($Subsystem in $Logging.SubsystemLogLevel) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.Subsystem = $Subsystem.Subsystem
                                $LocalizedData.Level     = $Subsystem.Level
                            }
                        }

                        if ($HighlightVerbose) {
                            foreach ($Row in $LevelInfo) {
                                if ($Row.$($LocalizedData.Subsystem) -in $VerboseSubsystem) {
                                    $Row | Set-Style -Style Warning -Property $LocalizedData.Level
                                }
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.DebugTable
                            List         = $false
                            ColumnWidths = 65, 35
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $LevelInfo | Sort-Object $LocalizedData.Subsystem | Table @TableParams
                    }
                }
                #endregion Subsystem log levels
            }
        } catch {
            Write-PScriboMessage -IsWarning "Logging: $($_.Exception.Message)"
        }
    }

    end {}
}
