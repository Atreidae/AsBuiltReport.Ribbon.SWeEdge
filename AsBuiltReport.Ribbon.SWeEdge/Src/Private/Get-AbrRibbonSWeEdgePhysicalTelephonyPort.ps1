function Get-AbrRibbonSWeEdgePhysicalTelephonyPort {
    <#
    .SYNOPSIS
        Used by As Built Report to retrieve Ribbon SWeEdge physical telephony port information.
    .DESCRIPTION
        Documents the digital and analog telephony ports fitted to a Ribbon SBC in
        Word/HTML/Text formats using PScribo.

        The section renders nothing on platforms without telephony hardware, such as SWe Lite
        and SWe Edge, rather than emitting an empty heading.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    #>
    [CmdletBinding()]
    param ()

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgePhysicalTelephonyPort
        Write-PScriboMessage ($LocalizedData.InfoLevel -f $InfoLevel.PhysicalTelephonyPort)
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            $Port = Resolve-AbrRibbonTelephonyPort -Config $script:RibbonConfig

            # A virtual appliance has no telephony hardware. That is expected, so the section
            # is skipped quietly rather than warned about.
            if (-not $Port.DigitalPort -and -not $Port.AnalogPort) {
                Write-PScriboMessage $LocalizedData.NotFound
                return
            }

            Section -Style Heading2 $LocalizedData.Heading {

                Paragraph $LocalizedData.SectionInfo
                BlankLine

                #region Digital ports
                if ($Port.DigitalPort) {
                    Section -Style Heading3 $LocalizedData.DigitalHeading {

                        $DigitalInfo = foreach ($Entry in $Port.DigitalPort) {
                            [PSCustomObject][Ordered]@{
                                $LocalizedData.PortName      = $Entry.PortName
                                $LocalizedData.Alias         = $Entry.Alias
                                $LocalizedData.PhysicalType  = $Entry.PhysicalType
                                $LocalizedData.SignalingType = $Entry.SignalingType
                                $LocalizedData.State         = $Entry.State
                            }
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.DigitalTable
                            List         = $false
                            ColumnWidths = 22, 30, 14, 16, 18
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $DigitalInfo | Table @TableParams
                    }
                }
                #endregion Digital ports

                #region Analog ports
                if ($Port.AnalogPort) {
                    Section -Style Heading3 $LocalizedData.AnalogHeading {

                        $AnalogInfo = foreach ($Entry in $Port.AnalogPort) {
                            $Row = [Ordered]@{
                                $LocalizedData.PortName = $Entry.PortName
                                $LocalizedData.Alias    = $Entry.Alias
                                $LocalizedData.PortType = $Entry.Type
                                $LocalizedData.State    = $Entry.State
                            }

                            if ($InfoLevel.PhysicalTelephonyPort -ge 3) {
                                $Row[$LocalizedData.RxGain] = $Entry.RxGain
                                $Row[$LocalizedData.TxGain] = $Entry.TxGain
                            }

                            [PSCustomObject]$Row
                        }

                        $TableParams = @{
                            Name         = $LocalizedData.AnalogTable
                            List         = $false
                            ColumnWidths = if ($InfoLevel.PhysicalTelephonyPort -ge 3) { 20, 28, 12, 16, 12, 12 } else { 25, 35, 20, 20 }
                        }
                        if ($Report.ShowTableCaptions) {
                            $TableParams['Caption'] = "- $($TableParams.Name)"
                        }
                        $AnalogInfo | Table @TableParams
                    }
                }
                #endregion Analog ports
            }
        } catch {
            Write-PScriboMessage -IsWarning "PhysicalTelephonyPort: $($_.Exception.Message)"
        }
    }

    end {}
}
