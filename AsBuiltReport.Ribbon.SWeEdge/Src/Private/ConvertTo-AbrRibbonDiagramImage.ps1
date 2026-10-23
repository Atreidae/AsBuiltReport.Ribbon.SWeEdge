function Test-AbrRibbonDiagramModule {
    <#
    .SYNOPSIS
        Tests whether the optional AsBuiltReport.Diagram module can be used, and loads it.
    .DESCRIPTION
        The module is deliberately not in RequiredModules, so a report that does not draw a
        diagram never needs it. Returns false rather than throwing when it is absent or will
        not load.
    .OUTPUTS
        System.Boolean
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Test-AbrRibbonDiagramModule
    #>
    [CmdletBinding()]
    [OutputType([Boolean])]
    param ()

    if (Get-Command -Name New-AbrTopologyDiagram -ErrorAction SilentlyContinue) {
        return $true
    }

    if (-not (Get-Module -ListAvailable -Name AsBuiltReport.Diagram)) {
        return $false
    }

    try {
        Import-Module -Name AsBuiltReport.Diagram -ErrorAction Stop

        # Older releases of the module predate the topology commands.
        [Boolean](Get-Command -Name New-AbrTopologyDiagram -ErrorAction SilentlyContinue)
    } catch {
        $false
    }
}

function ConvertTo-AbrRibbonDiagramImage {
    <#
    .SYNOPSIS
        Renders a topology chart to a base64 PNG sized to fit a document page.
    .DESCRIPTION
        PScribo places an image at the size it is given, and a tall diagram would otherwise run
        off the bottom of a Word page. The pixel size is read from the PNG header, which is
        portable, where System.Drawing is not available on every platform PowerShell runs on.
    .PARAMETER Diagram
        The chart returned by New-AbrRibbonTopologyDiagram.
    .PARAMETER MaxWidth
        The widest the image may be, in pixels.
    .PARAMETER MaxHeight
        The tallest the image may be, in pixels.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with Base64, Width and Height, or nothing
        when the diagram could not be rendered.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> ConvertTo-AbrRibbonDiagramImage -Diagram $Chart
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Diagram,

        [Int] $MaxWidth = 620,

        [Int] $MaxHeight = 860
    )

    try {
        $Base64 = Export-AbrTopologyDiagram -Diagram $Diagram -OutputFolderPath ([System.IO.Path]::GetTempPath()) -Filename 'RibbonTopology' -Format base64

        if ([String]::IsNullOrWhiteSpace($Base64)) {
            return
        }

        $Header = [Convert]::FromBase64String(($Base64 -replace '^data:image/png;base64,', '').Substring(0, 44))

        # IHDR holds the width and height as big endian 32 bit integers at fixed offsets.
        # Parenthesised because -shl binds looser than +.
        $Width = (([Int]$Header[16] -shl 24) + (([Int]$Header[17]) -shl 16) + (([Int]$Header[18]) -shl 8) + [Int]$Header[19])
        $Height = (([Int]$Header[20] -shl 24) + (([Int]$Header[21]) -shl 16) + (([Int]$Header[22]) -shl 8) + [Int]$Header[23])

        if ($Width -le 0 -or $Height -le 0) {
            return
        }

        $Scale = [Math]::Min(1.0, [Math]::Min([Double]$MaxWidth / $Width, [Double]$MaxHeight / $Height))

        [PSCustomObject]@{
            Base64 = $Base64 -replace '^data:image/png;base64,', ''
            Width  = [Int][Math]::Floor($Width * $Scale)
            Height = [Int][Math]::Floor($Height * $Scale)
        }
    } catch {
        Write-PScriboMessage -IsWarning $_.Exception.Message
    }
}
