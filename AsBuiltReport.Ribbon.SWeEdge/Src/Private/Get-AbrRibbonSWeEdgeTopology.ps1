function Get-AbrRibbonSWeEdgeTopology {
    <#
    .SYNOPSIS
        Renders the trunk topology diagram section of a Ribbon SWeEdge As Built Report.
    .DESCRIPTION
        Draws the appliance, the interfaces its signalling groups use and the far ends those
        groups talk to. The diagram is built from data the other sections already resolve, so
        it adds no configuration parsing.

        The AsBuiltReport.Diagram module is optional. When it is not installed the section is
        skipped with a warning and the rest of the report is unaffected. A Text document needs
        no special handling: PScribo omits images from it.

        The section is controlled by the ShowTopologyDiagram report option rather than an
        InfoLevel, because a diagram is a presentation choice and not a level of detail.
    .OUTPUTS
        None. Emits PScribo document objects.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Get-AbrRibbonSWeEdgeTopology
    #>
    [CmdletBinding()]
    param (
        [String] $Name
    )

    begin {
        $LocalizedData = $reportTranslate.GetAbrRibbonSWeEdgeTopology
        Write-PScriboMessage $LocalizedData.Collecting
    }

    process {
        try {
            # The diagram engine only ships a .NET 8 build, so it cannot load in Windows PowerShell.
            if ($PSVersionTable.PSEdition -ne 'Core') {
                Write-PScriboMessage -IsWarning $LocalizedData.UnsupportedHost
                return
            }

            if (-not (Test-AbrRibbonDiagramModule)) {
                Write-PScriboMessage -IsWarning $LocalizedData.ModuleMissing
                return
            }

            $Topology = Resolve-AbrRibbonTopology -Config $script:RibbonConfig -Name $Name

            if (-not $Topology.Group) {
                Write-PScriboMessage -IsWarning $LocalizedData.NotFound
                return
            }

            # Past this many rows a single diagram is too dense to read once it is scaled to
            # a page, so the appliance is drawn one interface at a time instead.
            $MaxRow = 24
            $MaxFarEnd = 6

            $RowCount = ($Topology.Group | ForEach-Object { [Math]::Max(1, [Math]::Min(@($_.FarEnd).Count, $MaxFarEnd) + $(if (@($_.FarEnd).Count -gt $MaxFarEnd) { 1 } else { 0 })) } | Measure-Object -Sum).Sum
            $Split = $RowCount -gt $MaxRow -and @($Topology.Interface).Count -gt 1

            $Diagram = if ($Split) {
                foreach ($Interface in $Topology.Interface) {
                    [PSCustomObject]@{
                        Title = $Interface
                        Chart = New-AbrRibbonTopologyDiagram -Topology $Topology -Interface $Interface -MaxFarEnd $MaxFarEnd
                    }
                }
            } else {
                [PSCustomObject]@{
                    Title = $Topology.Name
                    Chart = New-AbrRibbonTopologyDiagram -Topology $Topology -MaxFarEnd $MaxFarEnd
                }
            }

            Section -Style Heading2 $LocalizedData.Heading {
                Paragraph $LocalizedData.SectionInfo
                BlankLine

                if ($Split) {
                    Paragraph ($LocalizedData.SplitInfo -f $RowCount)
                    BlankLine
                }

                foreach ($Item in $Diagram) {
                    $Image = ConvertTo-AbrRibbonDiagramImage -Diagram $Item.Chart

                    if (-not $Image) {
                        Write-PScriboMessage -IsWarning ($LocalizedData.RenderFailed -f $Item.Title)
                        continue
                    }

                    $Alt = $LocalizedData.AltText -f $Item.Title

                    if ($Split) {
                        Section -Style Heading3 $Item.Title {
                            Image -Base64 $Image.Base64 -Text $Alt -Width $Image.Width -Height $Image.Height -Align Center
                            BlankLine
                        }
                    } else {
                        Image -Base64 $Image.Base64 -Text $Alt -Width $Image.Width -Height $Image.Height -Align Center
                        BlankLine
                    }
                }
            }
        } catch {
            Write-PScriboMessage -IsWarning ($LocalizedData.Error -f $_.Exception.Message)
        }
    }

    end {}
}
