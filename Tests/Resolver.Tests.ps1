BeforeAll {
    $script:ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\AsBuiltReport.Ribbon.SWeEdge' -Resolve

    Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Src\Private') -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }

    # Builds a minimal configuration object around a fragment of Ribbon XML, so resolvers can
    # be tested without customer data.
    function New-TestConfig {
        param([String] $Body)

        [Xml] $Xml = "<Configuration SystemRelease='13.1.0v43' PlatformType='SWeLite'>$Body</Configuration>"

        [PSCustomObject]@{
            SourceFile           = 'TestDrive:\test.xml'
            SystemRelease        = '13.1.0v43'
            PlatformType         = 'SWeLite'
            RawXml               = $Xml
            SignalingGroups      = [Ordered]@{ ISDN = @(); SIP = @(); CAS = @() }
            RoutingTables        = @()
            TransformationTables = @()
        }
    }
}

Describe 'ConvertTo-AbrRibbonAddressText' {

    It 'treats <_> as not configured' -ForEach @('', ' ', '0.0.0.0', '::') {
        ConvertTo-AbrRibbonAddressText -Value $_ -Placeholder 'Not set' | Should -Be 'Not set'
    }

    It 'returns a real address unchanged' {
        ConvertTo-AbrRibbonAddressText -Value '10.42.135.21' -Placeholder 'Not set' | Should -Be '10.42.135.21'
    }
}

Describe 'ConvertTo-AbrRibbonTransformField' {

    It 'names field <Value> as <Expected>' -ForEach @(
        @{ Value = '0'; Expected = 'Called Address/Number' }
        @{ Value = '3'; Expected = 'Calling Address/Number' }
        @{ Value = '10'; Expected = 'Redirecting Number' }
        @{ Value = '14'; Expected = 'User Value 1' }
        @{ Value = '27'; Expected = 'SG User Value 1' }
    ) {
        ConvertTo-AbrRibbonTransformField -Value $Value | Should -Be $Expected
    }

    It 'marks an unrecognised field rather than blanking it' {
        ConvertTo-AbrRibbonTransformField -Value '999' | Should -Be 'Unknown (999)'
    }
}

Describe 'Resolve-AbrRibbonNetworkInterface' {

    BeforeAll {
        # An SBC 1000 style config, where physical ports appear as VLAN sub-interfaces and the
        # port name has to be derived from the VLAN description.
        $script:Config = New-TestConfig -Body @'
<Token name="NodeHardware">
  <Token name="NetworkAdapter">
    <Token name="Bridge">
      <ID value="1">
        <IE classname="BRIDGE_IE"><Description>Bridge</Description></IE>
        <ID value="4040"><IE classname="NETSERV_VLAN_CFG_IE"><vlan_id>4040</vlan_id><vlan_description>Ethernet 1 VLAN</vlan_description><Enabled>1</Enabled></IE></ID>
        <ID value="4041"><IE classname="NETSERV_VLAN_CFG_IE"><vlan_id>4041</vlan_id><vlan_description>Ethernet 2 VLAN</vlan_description><Enabled>1</Enabled></IE></ID>
      </ID>
    </Token>
  </Token>
  <Token name="LogicalInterfaces">
    <ID value="1"><IE classname="NETSERV_INTERFACE_CFG_IE"><ifName>vlan1.4040</ifName><ifIPv4AddressPrimary>10.1.1.1</ifIPv4AddressPrimary><ifIPv4AddressPrimaryMask>255.255.255.0</ifIPv4AddressPrimaryMask><ifInterfaceIndex>29</ifInterfaceIndex></IE></ID>
    <ID value="2"><IE classname="NETSERV_INTERFACE_CFG_IE"><ifName>vlan1.4041</ifName><ifIPv4AddressPrimary></ifIPv4AddressPrimary><ifInterfaceIndex>30</ifInterfaceIndex></IE></ID>
    <ID value="3"><IE classname="NETSERV_INTERFACE_CFG_IE"><ifName>local0</ifName><ifInterfaceIndex>16</ifInterfaceIndex></IE></ID>
    <ID value="4"><IE classname="NETSERV_INTERFACE_CFG_IE"><ifName>mgt0</ifName><ifIPv4AddressPrimary>192.168.0.1</ifIPv4AddressPrimary><ifInterfaceIndex>11</ifInterfaceIndex></IE></ID>
  </Token>
</Token>
'@
        $script:Interface = @(Resolve-AbrRibbonNetworkInterface -Config $script:Config)
    }

    It 'derives the port name from the VLAN description rather than a hardcoded table' {
        ($script:Interface | Where-Object { $_.Name -eq 'vlan1.4040' }).DisplayName | Should -Be 'Ethernet 1'
        ($script:Interface | Where-Object { $_.Name -eq 'vlan1.4041' }).DisplayName | Should -Be 'Ethernet 2'
    }

    It 'labels fixed system interfaces' {
        ($script:Interface | Where-Object { $_.Name -eq 'mgt0' }).DisplayName | Should -Be 'Admin'
        ($script:Interface | Where-Object { $_.Name -eq 'local0' }).DisplayName | Should -Be 'Loopback 1'
    }

    It 'exposes the VLAN tag' {
        ($script:Interface | Where-Object { $_.Name -eq 'vlan1.4040' }).VlanTag | Should -Be '4040'
    }

    It 'keys the lookup by the forms a signaling group uses' {
        $Lookup = Resolve-AbrRibbonNetworkInterface -Config $script:Config -AsLookup

        # A signaling group refers to an interface as "Ethernet 1-1", meaning primary IPv4.
        $Lookup.ContainsKey('Ethernet 1-1') | Should -BeTrue
        $Lookup['Ethernet 1-1'].IPv4Primary | Should -Be '10.1.1.1'
        $Lookup.ContainsKey('vlan1.4040') | Should -BeTrue
    }
}

Describe 'Resolve-AbrRibbonEmergencyService' {

    BeforeAll {
        $script:Config = New-TestConfig -Body @'
<Token name="EmergencyServices">
  <Token name="ESConfig">
    <IE classname="CC_CFG_EMERGENCY_SERVICES_IE"><Enabled>1</Enabled><CallStatusDuration>24</CallStatusDuration><PreemptNonEmergencyCalls>1</PreemptNonEmergencyCalls></IE>
  </Token>
  <Token name="ESCallback">
    <ID value="1"><IE classname="CR_CALLBACK_NUMBER_TABLE_LIST_CONFIG"><Enabled>1</Enabled><Description>Pool</Description><PSAPNumber>+000</PSAPNumber><CallbackNumbersList>+61370105555,+61970105555</CallbackNumbersList></IE></ID>
    <ID value="2"><IE classname="CR_CALLBACK_NUMBER_TABLE_LIST_CONFIG"><Enabled>1</Enabled><Description>Single</Description><PSAPNumber>+000</PSAPNumber><CallbackNumbersList>+61370105555</CallbackNumbersList></IE></ID>
  </Token>
</Token>
<Token name="NotificationService">
  <Token name="NotificationManager">
    <ID value="1"><IE classname="NOTIFICATION_MANAGER_IE"><Enabled>1</Enabled><Description>Notify</Description><ClientID>Client</ClientID><Secret>SuperSecretValue</Secret><E911RecipientsList>+61870105555,+61470105555</E911RecipientsList><E911Message>Alert</E911Message></IE></ID>
  </Token>
</Token>
'@
        $script:Emergency = Resolve-AbrRibbonEmergencyService -Config $script:Config
    }

    It 'reads the singleton configuration that has no ID wrapper' {
        $script:Emergency.Configuration.CallStatusDuration | Should -Be '24'
    }

    It 'splits a multi entry callback list' {
        @($script:Emergency.CallbackPool | Where-Object { $_.Description -eq 'Pool' }).CallbackNumber | Should -Be @('+61370105555', '+61970105555')
    }

    It 'splits a single entry callback list without returning characters' {
        # Member enumeration collapses a one element array to a string, which would make
        # indexing return individual characters. The property is read from a single object
        # rather than through @(...) because that flattens nested arrays and would hide the
        # very thing being asserted.
        $Pool = @($script:Emergency.CallbackPool | Where-Object { $_.Description -eq 'Single' })[0]

        $Pool.CallbackNumber | Should -BeOfType [String]
        @($Pool.CallbackNumber) | Should -HaveCount 1
        @($Pool.CallbackNumber)[0] | Should -Be '+61370105555'
    }

    It 'never carries the notification manager secret' {
        $Manager = @($script:Emergency.NotificationManager)[0]
        $Manager.PSObject.Properties.Name | Should -Not -Contain 'Secret'
        ($Manager | Out-String) | Should -Not -Match 'SuperSecretValue'
    }
}

Describe 'Resolve-AbrRibbonLogging' {

    BeforeAll {
        $script:Config = New-TestConfig -Body @'
<Token name="Logging">
  <Token name="SyslogServer">
    <ID value="1"><IE classname="LOGGER_SYSLOG_DEST"><Enabled>1</Enabled><ServerAddress>syslog.example.com</ServerAddress><ServerPort>514</ServerPort><ServerTransport>0</ServerTransport><DefaultLevel>4</DefaultLevel><SyslogFacility>9</SyslogFacility></IE></ID>
  </Token>
  <Token name="DebugLevels">
    <ID value="1"><IE classname="LOGGER_LEVEL_SET"><Enabled>1</Enabled><LogLevel>3</LogLevel><LoggerName>com.sonus.sbc.sip</LoggerName><LogDestination>0</LogDestination></IE></ID>
    <ID value="2"><IE classname="LOGGER_LEVEL_SET"><Enabled>1</Enabled><LogLevel>3</LogLevel><LoggerName>com.sonus.sbc.sip</LoggerName><LogDestination>3</LogDestination></IE></ID>
    <ID value="3"><IE classname="LOGGER_LEVEL_SET"><Enabled>1</Enabled><LogLevel>2</LogLevel><LoggerName>com.sonus.sbc.route</LoggerName><LogDestination>0</LogDestination></IE></ID>
  </Token>
</Token>
<Token name="SNMP">
  <Token name="SNMPMgrTable">
    <ID value="1"><IE classname="SNMP_MANAGER_ADDR_IE"><Enabled>1</Enabled><snmpMgrAddr>10.1.1.5</snmpMgrAddr><snmpCommunity>PlainTextCommunity</snmpCommunity><snmpTrapEnable>1</snmpTrapEnable><snmpVersion>0</snmpVersion></IE></ID>
  </Token>
</Token>
'@
        $script:Logging = Resolve-AbrRibbonLogging -Config $script:Config
    }

    It 'names the syslog level and facility' {
        $Server = @($script:Logging.SyslogServer)[0]
        $Server.Level | Should -Be 'Warning'
        $Server.Facility | Should -Be 'local0'
        $Server.Transport | Should -Be 'UDP'
    }

    It 'never carries the SNMP community string' {
        # Name based redaction does not catch this field, so it is dropped explicitly.
        $Manager = @($script:Logging.SnmpManager)[0]
        $Manager.PSObject.Properties.Name | Should -Not -Contain 'snmpCommunity'
        ($Manager | Out-String) | Should -Not -Match 'PlainTextCommunity'
    }

    It 'collapses a subsystem that has the same level on every destination' {
        @($script:Logging.SubsystemLogLevel | Where-Object { $_.Subsystem -eq 'SIP Stack Service' }) | Should -HaveCount 1
    }

    It 'flags a subsystem left at Debug' {
        $Route = @($script:Logging.SubsystemLogLevel | Where-Object { $_.Subsystem -eq 'Call Routing Service' })[0]
        $Route.Level | Should -Be 'Debug'
        $Route.IsVerbose | Should -BeTrue
    }
}

Describe 'Test-AbrRibbonUnresolvedReference' {

    It 'reports an identifier that did not resolve' {
        Test-AbrRibbonUnresolvedReference -Value 'Unresolved (ID 42)' | Should -BeTrue
    }

    It 'reports an interface key that did not resolve' {
        # The interface resolver formats the remainder differently, so the marker is matched
        # by prefix rather than by the whole string.
        Test-AbrRibbonUnresolvedReference -Value 'Unresolved (vlan1.4040)' | Should -BeTrue
    }

    It 'does not report values that resolved, or the not-set placeholders' {
        Test-AbrRibbonUnresolvedReference -Value 'Teams', '--None--', 'Auto', '' | Should -BeFalse
    }

    It 'reports a set where only one value is unresolved' {
        Test-AbrRibbonUnresolvedReference -Value 'Teams', 'Unresolved (ID 7)' | Should -BeTrue
    }

    It 'does not report an empty set' {
        Test-AbrRibbonUnresolvedReference -Value @() | Should -BeFalse
    }
}

Describe 'Resolve-AbrRibbonSignalingGroup health check data' {

    BeforeAll {
        # Only the tokens the resolver looks up are needed. Group rows are supplied directly,
        # because the importer is what normally populates them.
        $script:Config = New-TestConfig -Body @'
<Token name="SIP">
  <Token name="SIPServers">
    <ID value="1"><IE classname="SIP_CFG_SERVER_TABLE_IE"><Description>Teams</Description></IE></ID>
  </Token>
</Token>
'@
        $script:Config.RoutingTables = @(
            [PSCustomObject]@{ ID = '1'; Description = 'From Teams'; Enabled = '1'; Routes = @() }
        )

        $script:Config.SignalingGroups.SIP = @(
            [PSCustomObject]@{ ID = '1'; Description = 'Healthy'; customAdminState = '1'; RouteTable = '1'; ServerClusterId = '1' }
            [PSCustomObject]@{ ID = '2'; Description = 'Dangling route table'; customAdminState = '1'; RouteTable = '99'; ServerClusterId = '1' }
            [PSCustomObject]@{ ID = '3'; Description = 'Turned off'; customAdminState = '0'; RouteTable = '1'; ServerClusterId = '1' }
            [PSCustomObject]@{ ID = '4'; Description = 'In maintenance'; customAdminState = '2'; RouteTable = '1'; ServerClusterId = '1' }
        )

        $script:Group = @(Resolve-AbrRibbonSignalingGroup -Config $script:Config)
    }

    It 'does not flag a group whose references all resolve' {
        ($script:Group | Where-Object { $_.ID -eq '1' }).HasUnresolvedReference | Should -BeFalse
    }

    It 'flags a group pointing at a route table that no longer exists' {
        $Broken = $script:Group | Where-Object { $_.ID -eq '2' }
        $Broken.HasUnresolvedReference | Should -BeTrue
        # The marker must survive to the rendered value, never be name matched away.
        $Broken.RouteTableName | Should -Be 'Unresolved (ID 99)'
    }

    It 'reports admin state from customAdminState, including Drain' {
        ($script:Group | Where-Object { $_.ID -eq '1' }).State | Should -Be 'Enabled'
        ($script:Group | Where-Object { $_.ID -eq '3' }).State | Should -Be 'Disabled'
        ($script:Group | Where-Object { $_.ID -eq '4' }).State | Should -Be 'Drain'
    }

    It 'does not flag a disabled group as having a broken reference' {
        # The two health checks are independent. A group being off says nothing about
        # whether what it points at still exists.
        ($script:Group | Where-Object { $_.ID -eq '3' }).HasUnresolvedReference | Should -BeFalse
    }
}

Describe 'Resolve-AbrRibbonCallRoute health check data' {

    BeforeAll {
        $script:Config = New-TestConfig -Body '<Token name="TimeOfDay" />'

        $script:Config.SignalingGroups.SIP = @(
            [PSCustomObject]@{ ID = '1'; Description = 'To Carrier' }
        )

        # Destination names are resolved by the importer, so they are supplied already
        # resolved here and the resolver is tested on what it does with them.
        $script:Config.RoutingTables = @(
            [PSCustomObject]@{
                ID          = '1'
                Description = 'From Teams'
                Enabled     = '1'
                Routes      = @(
                    [PSCustomObject]@{
                        ExecutionOrder = 0; ID = '1'; Description = 'Healthy'; Enabled = '1'
                        DestinationType = '0'; SignalingGroupNames = @('To Carrier')
                        TransformationTableName = 'Pass through'
                    }
                    [PSCustomObject]@{
                        ExecutionOrder = 1; ID = '2'; Description = 'Turned off'; Enabled = '0'
                        DestinationType = '0'; SignalingGroupNames = @('To Carrier')
                        TransformationTableName = 'Pass through'
                    }
                    [PSCustomObject]@{
                        ExecutionOrder = 2; ID = '3'; Description = 'Dangling destination'; Enabled = '1'
                        DestinationType = '0'; SignalingGroupNames = @('Unresolved (ID 99)')
                        TransformationTableName = 'Pass through'
                    }
                    [PSCustomObject]@{
                        ExecutionOrder = 3; ID = '4'; Description = 'Blocked'; Enabled = '1'
                        DestinationType = '2'; SignalingGroupNames = @()
                        TransformationTableName = '--Deny--'
                    }
                )
            }
        )

        $script:Route = @((Resolve-AbrRibbonCallRoute -Config $script:Config).RouteTable.Route)
    }

    It 'does not flag a route whose references all resolve' {
        ($script:Route | Where-Object { $_.ID -eq '1' }).HasUnresolvedReference | Should -BeFalse
    }

    It 'reports the enabled state of each route entry' {
        ($script:Route | Where-Object { $_.ID -eq '1' }).State | Should -Be 'Enabled'
        ($script:Route | Where-Object { $_.ID -eq '2' }).State | Should -Be 'Disabled'
    }

    It 'flags a route pointing at a signaling group that no longer exists' {
        ($script:Route | Where-Object { $_.ID -eq '3' }).HasUnresolvedReference | Should -BeTrue
    }

    It 'does not flag a Deny route, which has no destination by design' {
        # Deny and Trunk Group routes carry an empty destination list, so an empty list must
        # never be read as a broken reference.
        $Deny = $script:Route | Where-Object { $_.ID -eq '4' }
        $Deny.Destination | Should -BeNullOrEmpty
        $Deny.HasUnresolvedReference | Should -BeFalse
    }
}

Describe 'Find-AbrRibbonProvider' {

    It 'recognises <Address> as Teams Direct Routing' -ForEach @(
        @{ Address = 'sip.pstnhub.microsoft.com' }
        @{ Address = 'SIP3.PSTNHUB.MICROSOFT.COM.' }
        @{ Address = 'sip-du-a-au.pstnhub.microsoft.com' }
    ) {
        (Find-AbrRibbonProvider -Address $Address).Name | Should -Be 'Microsoft Teams Direct Routing'
    }

    It 'does not claim a host that only resembles a provider endpoint' -ForEach @(
        @{ Address = 'sip.notpstnhub.microsoft.com' }
        @{ Address = 'pstnhub.microsoft.com.example.net' }
        @{ Address = '' }
    ) {
        Find-AbrRibbonProvider -Address $Address | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-AbrRibbonTopology' {

    BeforeAll {
        $script:Config = New-TestConfig -Body '<Token name="SIP"></Token>'

        $script:Config.SignalingGroups.SIP = @(
            [PSCustomObject]@{
                ID = '1'; Description = 'Teams'; customAdminState = '2'
                ListenPort_1 = '5061'; Protocol_1 = '4'
                RemoteHosts = 'sip.pstnhub.microsoft.com, sip2.pstnhub.microsoft.com, 0.0.0.0'
                RemoteMasks = '255.255.255.255, 255.255.255.255, 0.0.0.0'
            }
            [PSCustomObject]@{
                ID = '2'; Description = 'PBX'; customAdminState = '1'
                ListenPort_1 = '5060'; Protocol_1 = '1'
                RemoteHosts = '10.0.0.5'; RemoteMasks = '255.255.255.255'
            }
        )

        $script:Config.SignalingGroups.ISDN = @(
            [PSCustomObject]@{ ID = '7'; Description = 'PSTN'; customAdminState = '1'; ApplyToPortName = 'Port 1' }
        )

        $script:Topology = Resolve-AbrRibbonTopology -Config $script:Config -Name 'sbc01'
    }

    It 'collapses every host of one provider into a single far end' {
        $Teams = $script:Topology.Group | Where-Object { $_.Name -eq 'Teams' }
        @($Teams.FarEnd).Count | Should -Be 1
        $Teams.FarEnd[0].Label | Should -Be 'Microsoft Teams Direct Routing'
        $Teams.FarEnd[0].Protocol | Should -Be 'TLS'
    }

    It 'does not draw the unspecified address as a peer' {
        ($script:Topology.Group.FarEnd | Where-Object { $_.Host -eq '0.0.0.0' }) | Should -BeNullOrEmpty
    }

    It 'carries group state through so a drained group can be told apart' {
        ($script:Topology.Group | Where-Object { $_.Name -eq 'Teams' }).State | Should -Be 'Drain'
        ($script:Topology.Group | Where-Object { $_.Name -eq 'PBX' }).State | Should -Be 'Enabled'
    }

    It 'reports a peer that is not a known provider by address and transport' {
        $Pbx = $script:Topology.Group | Where-Object { $_.Name -eq 'PBX' }
        $Pbx.FarEnd[0].Label | Should -Be '10.0.0.5'
        $Pbx.FarEnd[0].Protocol | Should -Be 'UDP'
        $Pbx.FarEnd[0].Provider | Should -BeNullOrEmpty
    }

    It 'attaches a telephony group to its physical port rather than a peer' {
        $Isdn = $script:Topology.Group | Where-Object { $_.Type -eq 'ISDN' }
        $Isdn.FarEnd[0].Label | Should -Be 'Port 1'
    }
}

Describe 'New-AbrRibbonTopologyDiagram' -Skip:(-not (Get-Module -ListAvailable -Name AsBuiltReport.Diagram)) {

    BeforeAll {
        Import-Module AsBuiltReport.Diagram -ErrorAction Stop

        $script:Topology = [PSCustomObject]@{
            Name = 'sbc01'; PlatformType = 'SWeLite'; Release = '13.1.0v43'
            Interface = @('Ethernet 1')
            Group = @(
                [PSCustomObject]@{
                    ID = '1'; Name = 'Teams'; Type = 'SIP'; State = 'Drain'; Interface = 'Ethernet 1'; Listen = @('TLS 5061')
                    FarEnd = @(1..9 | ForEach-Object {
                            [PSCustomObject]@{ Key = "host|$_"; Label = "peer$_"; Host = "peer$_"; Port = '5061'; Protocol = 'TLS'; Provider = ''; Source = 'ServerTable'; State = 'Enabled' }
                        })
                }
            )
        }
    }

    It 'draws the appliance, the group, its far ends and one summary node for the rest' {
        $Diagram = New-AbrRibbonTopologyDiagram -Topology $script:Topology -MaxFarEnd 6

        # appliance + group + six far ends + the summary node
        @($Diagram.Nodes).Count | Should -Be 9
    }
}