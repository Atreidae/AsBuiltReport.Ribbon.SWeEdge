function New-AbrRibbonTopologyDiagram {
    <#
    .SYNOPSIS
        Builds the trunk topology diagram for one appliance.
    .DESCRIPTION
        Turns the output of Resolve-AbrRibbonTopology into an AsBuiltReport.Diagram topology
        chart. The appliance sits at the left, each interface is a container holding the
        signalling groups that use it, and each group is linked to its far ends on the right.

        State and transport are carried by the drawing rather than by labels alone. A drained
        group is a warning and a disabled group is greyed out. TLS is a solid line, TCP is
        dashed and UDP is dotted, so a plain text trunk stands out from a secure one without
        reading anything.

        Positions are calculated here rather than left to the automatic layout. The automatic
        layouts do not keep an interface container around its own groups, which is the one
        thing this diagram exists to show.

        Requires the AsBuiltReport.Diagram module to be loaded. The caller is responsible for
        checking that, because the module is optional.
    .PARAMETER Topology
        The object returned by Resolve-AbrRibbonTopology.
    .PARAMETER Interface
        Restricts the diagram to the signalling groups on one interface. Used to split an
        appliance with many groups into several readable diagrams.
    .PARAMETER MaxFarEnd
        The most far ends drawn for one group. The rest are summarised in a single node so one
        group with a large peer list cannot swamp the page.
    .OUTPUTS
        ChartForgeX.Topology.TopologyChart
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> New-AbrRibbonTopologyDiagram -Topology $Topology
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Builds an in memory object and changes no system state.'
    )]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Topology,

        [String] $Interface,

        [ValidateRange(1, 50)]
        [Int] $MaxFarEnd = 6
    )

    $Status = @{
        'Enabled'  = 'Healthy'
        'Drain'    = 'Warning'
        'Disabled' = 'Disabled'
    }

    $Style = @{
        'TLS' = @{ Line = 'Solid'; Color = '#2E7D32' }
        'TCP' = @{ Line = 'Dashed'; Color = '#1565C0' }
        'UDP' = @{ Line = 'Dotted'; Color = '#EF6C00' }
    }

    # Geometry in diagram units. Every node is the same size so rows line up.
    $NodeWidth = 250
    $NodeHeight = 70
    $RowHeight = 96
    $ContainerPad = 36
    $ContainerGap = 40
    $ApplianceX = 40
    $ContainerX = 340
    $GroupX = $ContainerX + 30
    $ContainerWidth = $NodeWidth + 60
    $FarEndX = $ContainerX + $ContainerWidth + 150

    $Subtitle = (@($Topology.PlatformType, $Topology.Release) | Where-Object { $_ }) -join ' '
    $Title = if ($Interface) { '{0} - {1}' -f $Topology.Name, $Interface } else { $Topology.Name }

    # Ordered by interface so each container is one contiguous band.
    $Selected = @(
        $Topology.Group |
            Where-Object { -not $Interface -or $_.Interface -eq $Interface } |
            Sort-Object -Property Interface
    )

    $Diagram = New-AbrTopologyDiagram -Id 'RibbonTopology' -Title $Title -Subtitle $Subtitle -LayoutMode Manual -LayoutDirection LeftToRight

    $InterfaceBand = [Ordered]@{}
    $FarEndId = @{}
    $EdgeIndex = 0
    $Cursor = 100

    foreach ($Group in $Selected) {

        if (-not $InterfaceBand.Contains($Group.Interface)) {
            # The gap goes between containers, not before the first one.
            if ($InterfaceBand.Count) { $Cursor += $ContainerGap }
            $InterfaceBand[$Group.Interface] = [PSCustomObject]@{ Id = 'interface{0}' -f $InterfaceBand.Count; Top = $Cursor; Bottom = $Cursor; First = ('group{0}_{1}' -f $Group.Type, $Group.ID) }
            $Cursor += $ContainerPad
        }

        $Band = $InterfaceBand[$Group.Interface]

        $Drawn = @($Group.FarEnd | Select-Object -First $MaxFarEnd)
        $Hidden = @($Group.FarEnd).Count - $Drawn.Count
        $Rows = [Math]::Max(1, $Drawn.Count + $(if ($Hidden -gt 0) { 1 } else { 0 }))

        $GroupNodeId = 'group{0}_{1}' -f $Group.Type, $Group.ID
        $GroupY = $Cursor + (($Rows - 1) * $RowHeight / 2)

        $Detail = @(
            if (@($Group.Listen).Count) { @($Group.Listen) -join ', ' } else { $Group.Type }
            $Group.State
        ) -join ' - '

        $null = Add-AbrTopologyNode -Diagram $Diagram -Id $GroupNodeId -Label $Group.Name -Subtitle $Detail -Kind Service `
            -Status $(if ($Status.ContainsKey([String]$Group.State)) { $Status[[String]$Group.State] } else { 'Unknown' }) `
            -GroupId $Band.Id -X $GroupX -Y $GroupY -Width $NodeWidth -Height $NodeHeight

        $Row = 0
        foreach ($FarEnd in $Drawn) {
            # Drawn once per group. A shared node would pull lines across other groups' rows
            # and make the picture unreadable.
            $FarKey = '{0}|{1}' -f $GroupNodeId, $FarEnd.Key
            if (-not $FarEndId.ContainsKey($FarKey)) {
                $FarEndId[$FarKey] = 'farend{0}' -f $FarEndId.Count

                $Kind = if ($FarEnd.Provider) { 'Cloud' } elseif ($FarEnd.Source -eq 'Port') { 'Endpoint' } else { 'Server' }

                $null = Add-AbrTopologyNode -Diagram $Diagram -Id $FarEndId[$FarKey] -Label $FarEnd.Label -Kind $Kind `
                    -Status $(if ($FarEnd.State -eq 'Disabled') { 'Disabled' } else { 'Healthy' }) `
                    -X $FarEndX -Y ($Cursor + ($Row * $RowHeight)) -Width $NodeWidth -Height $NodeHeight
            }

            $Line = if ($Style.ContainsKey([String]$FarEnd.Protocol)) { $Style[[String]$FarEnd.Protocol] } else { @{ Line = 'Solid'; Color = '#607D8B' } }

            $EdgeIndex++
            $null = Add-AbrTopologyEdge -Diagram $Diagram -Id ('edge{0}' -f $EdgeIndex) -SourceId $GroupNodeId -TargetId $FarEndId[$FarKey] -Kind Connectivity `
                -Label $FarEnd.Protocol -LineStyle $Line.Line -Color $Line.Color
            $Row++
        }

        if ($Hidden -gt 0) {
            $MoreId = 'more{0}_{1}' -f $Group.Type, $Group.ID
            $null = Add-AbrTopologyNode -Diagram $Diagram -Id $MoreId -Label ('+{0} more' -f $Hidden) -Kind Generic -Status Unknown `
                -X $FarEndX -Y ($Cursor + ($Row * $RowHeight)) -Width $NodeWidth -Height $NodeHeight

            $EdgeIndex++
            $null = Add-AbrTopologyEdge -Diagram $Diagram -Id ('edge{0}' -f $EdgeIndex) -SourceId $GroupNodeId -TargetId $MoreId -Kind Connectivity -LineStyle Dotted
        }

        $Cursor += $Rows * $RowHeight
        $Band.Bottom = $Cursor
    }

    # Containers are added after their contents are measured, then the appliance is centred
    # on the whole diagram.
    foreach ($Name in $InterfaceBand.Keys) {
        $Band = $InterfaceBand[$Name]
        $Height = ($Band.Bottom - $Band.Top) + $ContainerPad - ($RowHeight - $NodeHeight)

        $null = Add-AbrTopologyGroup -Diagram $Diagram -Id $Band.Id -Label $Name -X $ContainerX -Y ($Band.Top - 20) -Width $ContainerWidth -Height $Height
    }

    $ApplianceY = 100 + (([Math]::Max($Cursor, 200) - 100 - $NodeHeight) / 2)
    $null = Add-AbrTopologyNode -Diagram $Diagram -Id 'appliance' -Label $Topology.Name -Subtitle $Subtitle -Kind Gateway -Status Healthy `
        -X $ApplianceX -Y $ApplianceY -Width $NodeWidth -Height $NodeHeight

    foreach ($Name in $InterfaceBand.Keys) {
        $EdgeIndex++
        $null = Add-AbrTopologyEdge -Diagram $Diagram -Id ('edge{0}' -f $EdgeIndex) -SourceId 'appliance' -TargetId $InterfaceBand[$Name].First -Kind Connectivity -Routing Straight -Color '#90A4AE' -Opacity 0.7
    }

    $Diagram
}
