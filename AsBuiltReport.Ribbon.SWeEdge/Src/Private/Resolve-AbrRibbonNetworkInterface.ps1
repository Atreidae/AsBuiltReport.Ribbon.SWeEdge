function Resolve-AbrRibbonNetworkInterface {
    <#
    .SYNOPSIS
        Resolves the logical network interfaces of a Ribbon SBC into reportable objects.
    .DESCRIPTION
        Ribbon names logical interfaces differently across platforms. SWe Lite uses friendly
        names such as "Ethernet 1" and "mgt0", while the SBC 1000 and 2000 present physical
        ports as VLAN sub-interfaces named "vlan1.<tag>".

        The mapping from VLAN tag to physical port is held in the configuration itself. Each
        VLAN row carries a description such as "Ethernet 1 VLAN", so the port name is derived
        rather than assumed. This matters because the tags differ by platform: an SBC 2000
        uses 4031 to 4034 while an SBC 1000 uses 4040 to 4042.

        Signaling groups reference an interface by name with an address suffix, for example
        "Ethernet 2-1". The suffixes are -1 for the primary IPv4 address, -2 for the secondary
        and -6 for IPv6. A bare name is also accepted, as used by SWe Lite.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .PARAMETER AsLookup
        Returns a hashtable keyed by the reference forms a signaling group uses, instead of
        the interface objects.
    .OUTPUTS
        System.Management.Automation.PSCustomObject or System.Collections.Hashtable
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        Loopback and management interface labels are presentation names for fixed system
        interfaces. They are not relationships inferred from the configuration.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonNetworkInterface -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject], [Hashtable])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config,

        [Parameter(Mandatory = $false)]
        [Switch] $AsLookup
    )

    $Xml = $Config.RawXml

    # Fixed system interfaces. These names are constant across releases and carry no port
    # relationship to derive, so a presentation label is all that is required.
    $SystemInterfaceLabel = @{
        'eth0'   = 'Admin'
        'mgt0'   = 'Admin'
        'local0' = 'Loopback 1'
        'local1' = 'Loopback 2'
        'local2' = 'Loopback 3'
        'local3' = 'Loopback 4'
        'local4' = 'Loopback 5'
    }

    # VLAN tag to physical port, taken from the configuration rather than hardcoded.
    $VlanPort = @{}
    foreach ($Vlan in @($Xml.Configuration.SelectNodes("Token[@name='NodeHardware']/Token[@name='NetworkAdapter']/Token[@name='Bridge']/ID/ID") | ConvertFrom-AbrRibbonIeNode)) {
        if ($Vlan.ClassName -ne 'NETSERV_VLAN_CFG_IE') {
            continue
        }

        $Tag = [String]$Vlan.vlan_id
        if ([String]::IsNullOrWhiteSpace($Tag)) {
            continue
        }

        # Descriptions read "Ethernet 1 VLAN". Trim the suffix to get the port name.
        $Port = ([String]$Vlan.vlan_description) -replace '\s*VLAN\s*$', ''
        $VlanPort[$Tag] = [PSCustomObject]@{
            Tag         = $Tag
            Port        = $Port
            Description = [String]$Vlan.vlan_description
        }
    }

    $Interfaces = foreach ($Row in @($Xml.Configuration.SelectNodes("Token[@name='NodeHardware']/Token[@name='LogicalInterfaces']/ID") | ConvertFrom-AbrRibbonIeNode)) {

        $Name = [String]$Row.ifName
        $VlanTag = $null
        $Port = $null

        if ($Name -match '^vlan\d+\.(?<Tag>\d+)$') {
            $VlanTag = $Matches['Tag']
            if ($VlanPort.ContainsKey($VlanTag)) {
                $Port = $VlanPort[$VlanTag].Port
            }
        }

        $DisplayName = if ($Port) {
            $Port
        } elseif ($SystemInterfaceLabel.ContainsKey($Name)) {
            $SystemInterfaceLabel[$Name]
        } elseif (-not [String]::IsNullOrWhiteSpace($Row.ifAlias)) {
            $Row.ifAlias
        } else {
            # Unresolvable names are shown verbatim rather than guessed at.
            $Name
        }

        [PSCustomObject]@{
            ID              = $Row.ID
            Name            = $Name
            DisplayName     = $DisplayName
            Alias           = [String]$Row.ifAlias
            VlanTag         = $VlanTag
            IPv4Primary     = [String]$Row.ifIPv4AddressPrimary
            IPv4PrimaryMask = [String]$Row.ifIPv4AddressPrimaryMask
            IPv4Secondary   = [String]$Row.ifIPv4AddressSecondary
            IPv6Primary     = [String]$Row.ifIPv6AddressPrimary
            InterfaceIndex  = [String]$Row.ifInterfaceIndex
            BridgeGroupId   = [String]$Row.ifBridgeGroupId
            AclIn           = [String]$Row.aclInInstanceID
            AclOut          = [String]$Row.aclOutInstanceID
            AclForward      = [String]$Row.aclForwardInstanceID
        }
    }

    if (-not $AsLookup) {
        return @($Interfaces)
    }

    # Signaling groups reference an interface plus an address slot, such as "Ethernet 2-1".
    $Lookup = @{}
    foreach ($Interface in $Interfaces) {
        $Lookup[$Interface.Name] = $Interface
        $Lookup['{0}-1' -f $Interface.Name] = $Interface
        $Lookup['{0}-2' -f $Interface.Name] = $Interface
        $Lookup['{0}-6' -f $Interface.Name] = $Interface

        # SWe Lite signaling groups reference the display name directly.
        $Lookup[$Interface.DisplayName] = $Interface
        $Lookup['{0}-1' -f $Interface.DisplayName] = $Interface
        $Lookup['{0}-2' -f $Interface.DisplayName] = $Interface
        $Lookup['{0}-6' -f $Interface.DisplayName] = $Interface
    }

    return $Lookup
}
