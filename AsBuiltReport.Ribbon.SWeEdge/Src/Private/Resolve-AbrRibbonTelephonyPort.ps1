function Resolve-AbrRibbonTelephonyPort {
    <#
    .SYNOPSIS
        Resolves the physical telephony ports of a Ribbon SBC.
    .DESCRIPTION
        Digital ports live under LineCards, analog ports under FXSCards and FXOLineCards, and
        ISDN BRI ports under BRILineCards. Each card holds child rows, one per port.

        Only appliances with physical telephony hardware carry these. SWe Lite and SWe Edge
        have none, so an empty result is normal rather than a parsing failure.

        Note that a signaling group references a port as ApplyToPortName, for example "1.1",
        while the port itself is named "DS1-1:1". The relationship between the two is not
        stated in the configuration, so no link is inferred here.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with DigitalPort and AnalogPort.
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonTelephonyPort -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml

    $DigitalPort = foreach ($CardType in 'LineCards', 'BRILineCards') {
        foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='NodeHardware']/Token[@name='$CardType']/ID/ID") | ConvertFrom-AbrRibbonIeNode)) {
            [PSCustomObject]@{
                Card          = $CardType
                PortName      = $Row.PortName
                Alias         = $Row.PortAlias
                Description   = $Row.PortDescription
                State         = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                PhysicalType  = switch ([String]$Row.PortPhysicalType) {
                    '0' { 'E1' }
                    '1' { 'T1' }
                    default { '' }
                }
                SignalingType = switch ([String]$Row.PortSignalingType) {
                    '0' { 'ISDN' }
                    '1' { 'CAS' }
                    default { '' }
                }
                FramingType   = $Row.PortFramingType
                CodingType    = $Row.PortCodingType
                CrcType       = $Row.PortCRCType
            }
        }
    }

    $AnalogPort = foreach ($CardType in 'FXSCards', 'FXOLineCards') {
        foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='NodeHardware']/Token[@name='$CardType']/ID/ID") | ConvertFrom-AbrRibbonIeNode)) {
            [PSCustomObject]@{
                Card        = $CardType
                PortName    = $Row.PortName
                Alias       = $Row.PortAlias
                Description = $Row.PortDescription
                State       = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                Type        = if ($CardType -eq 'FXSCards') { 'FXS' } else { 'FXO' }
                RxGain      = $Row.RxGain
                TxGain      = $Row.TxGain
            }
        }
    }

    [PSCustomObject]@{
        DigitalPort = @($DigitalPort)
        AnalogPort  = @($AnalogPort)
    }
}
