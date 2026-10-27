# culture = 'en-US'
@{
    # Main module translations (Invoke-AsBuiltReport.Ribbon.SWeEdge)
    InvokeAsBuiltReportRibbonSWeEdge = ConvertFrom-StringData @'
        PwshRequired      = The ShowTopologyDiagram option needs PowerShell 7 or later, and this session is Windows PowerShell. Try using: pwsh -Command "{0}"
        TargetFileWithInputFile = '{0}' was passed as a Target alongside -InputFile. With -InputFile, Target is only a display name, so the file path was ignored and the node name from the export will be used instead.
        TargetFileDeprecated = '{0}' was passed as a Target. Passing an export file through Target is deprecated, use -InputFile instead (AsBuiltReport.Core 1.7.0 or later).
        Importing         = Importing Ribbon SBC configuration from {0}.
        Collecting        = Collecting configuration from Ribbon SBC {0} over REST.
        ImportError       = Unable to import configuration from {0}. {1}
        TargetNotFound    = Target {0} was not found. Supply a path to a Ribbon SBC configuration export, or the host name of an appliance with a REST enabled account.
        SectionError      = Error processing section {0}. {1}
        InfoLevelNotFound = InfoLevel for {0} was not found in the report configuration.
'@

    # System section translations (Get-AbrRibbonSWeEdgeSystem)
    GetAbrRibbonSWeEdgeSystem = ConvertFrom-StringData @'
        InfoLevel        = System InfoLevel set at {0}.
        Collecting       = Collecting System information.
        NotFound         = No system information was found in the configuration.

        Heading          = System
        SectionInfo      = The following section details the system level configuration of the SBC, covering how it identifies itself on the network, where it obtains time and name resolution, and the port range reserved for media traffic.

        NodeHeading      = Node Information
        NodeTable        = Node Information
        NodeName         = Node Name
        DomainName       = Domain Name
        PlatformType     = Platform Type
        SystemRelease    = System Release
        SourceFile       = Configuration Source
        Contact          = System Contact
        Location         = System Location
        Description      = System Description
        CountryCode      = Country Code

        TimeHeading      = Time and NTP
        TimeTable        = Time and NTP Configuration
        TimeZone         = Time Zone
        NtpServer        = NTP Server
        NtpPrimary       = Primary
        NtpSecondary     = Secondary
        NtpEnabled       = Enabled
        NtpAuthenticated = Authentication
        NtpInfo          = No NTP server is enabled on this appliance, so its clock is not synchronised and will drift. That affects more than timestamps: certificate validity is judged against the appliance clock, so drift presents as TLS handshake failures that look like certificate faults, and call detail records and logs cannot be correlated with any other system. Configure at least one NTP server.

        DnsHeading       = DNS
        DnsTable         = DNS Configuration
        DnsPrimary       = Primary DNS Server
        DnsSecondary     = Secondary DNS Server
        SplitDnsHeading  = Split DNS
        SplitDnsTable    = Split DNS Entries
        SplitDnsDomain   = Domain
        SplitDnsServer   = DNS Server

        HostsHeading     = Static Hosts
        HostsTable       = Static Host Entries
        HostName         = Host Name
        IpAddress        = IP Address

        MediaHeading     = Media System Settings
        MediaTable       = Media System Settings
        RtpPortRange     = RTP/RTCP Port Range
        MediaDryupTime   = Media Dry Up Time
        DhcpServer       = DHCP Server

        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # Firewall section translations (Get-AbrRibbonSWeEdgeFirewall)
    GetAbrRibbonSWeEdgeFirewall = ConvertFrom-StringData @'
        InfoLevel        = Firewall InfoLevel set at {0}.
        Collecting       = Collecting firewall requirement information.
        NotFound         = No firewall information could be derived from the configuration.

        Heading          = Firewall Requirements
        SectionInfo      = The following section lists the network flows this appliance needs in order to work. Every row is derived from this appliance's own configuration rather than from a generic vendor requirements list, so it covers the services that are actually configured and nothing else.

        FlowHeading      = Required Network Flows
        FlowInfo         = Some values cannot be taken from a configuration export. The source port of an outbound TCP or TLS connection is chosen by the operating system when the connection is made, so it is shown as ephemeral. UDP is different: SIP over UDP is symmetric, so the appliance sends from the same port it listens on, and an inbound UDP flow arrives from the far end's own signalling port rather than an ephemeral one. The media port range of the far end belongs to the far end, so it is shown as a placeholder unless the peer is a provider that publishes its ranges.
        FlowTable        = Required Network Flows
        Purpose          = Purpose
        Direction        = Direction
        Source           = Source
        SourcePort       = Source Port
        Destination      = Destination
        DestPort         = Destination Port
        Protocol         = Protocol
        Note             = Notes

        PeerHeading      = Detected Service Providers
        PeerInfo         = A SIP peer in this configuration matches a provider that publishes its own address and port requirements, so those ranges have been included in the flow table above. Providers change these ranges from time to time. Confirm them against current provider documentation before applying any rule.
        PeerTable        = Detected Service Providers
        Provider         = Provider
        SignalingNetwork = Signalling Networks
        MediaNetwork     = Media Networks
        MediaPort        = Media Ports
        RelayPort        = Transport Relay Ports

        NatHeading       = Address Translation
        NatInfo          = These signalling groups advertise a public address that differs from the address on the interface, which means the appliance sits behind a one to one translation. The firewall must translate the public address to the private address shown and must not alter the SIP or SDP payload while doing so.
        NatTable         = Address Translation
        SignalingGroup   = Signalling Group
        PrivateAddress   = Private Address
        PublicAddress    = Public Address

        AclHeading       = Appliance Access Control List
        AclInfo          = These rules are applied by the appliance itself and are separate from any upstream firewall. A flow permitted upstream will still fail if it is denied here. Rules are listed in the order the appliance evaluates them.
        AclTable         = Access Control Rules
        Action           = Action
        Interface        = Interface
        Precedence       = Precedence

        State            = State
        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # Topology section translations (Get-AbrRibbonSWeEdgeTopology)
    GetAbrRibbonSWeEdgeTopology = ConvertFrom-StringData @'
        Collecting       = Collecting trunk topology information.
        NotFound         = No signalling groups were found, so no topology diagram was drawn.
        UnsupportedHost   = The topology diagram was skipped because it needs PowerShell 7 or later. The diagram engine in AsBuiltReport.Diagram cannot load in Windows PowerShell 5.1. Run the report from pwsh to use the ShowTopologyDiagram option.
        ModuleMissing     = The topology diagram was skipped because the optional AsBuiltReport.Diagram module is not installed. Install it with Install-Module AsBuiltReport.Diagram to enable the ShowTopologyDiagram option.
        RenderFailed     = The topology diagram for {0} could not be rendered and was skipped.
        Error            = The topology diagram could not be created: {0}

        Heading          = Trunk Topology
        SectionInfo      = The diagram shows this appliance, the network interface each signalling group uses, and the far ends each group talks to. Line style shows the transport: a solid line is TLS, a dashed line is TCP and a dotted line is UDP. A drained signalling group is shown in amber and a disabled one is greyed out. Peers belonging to a recognised service provider are drawn as that provider.
        SplitInfo        = This appliance has too many signalling group connections ({0}) to read in one diagram, so it is drawn one interface at a time.
        AltText          = Trunk topology diagram for {0}
'@

    # Networking section translations (Get-AbrRibbonSWeEdgeNetworking)
    GetAbrRibbonSWeEdgeNetworking = ConvertFrom-StringData @'
        InfoLevel        = Networking InfoLevel set at {0}.
        Collecting       = Collecting Networking information.
        NotFound         = No network interfaces were found in the configuration.

        Heading          = Networking
        SectionInfo      = The following section details the network configuration of the SBC. Logical interfaces carry signalling and media traffic and are referenced by name from each signalling group. On SBC 1000 and 2000 appliances the physical ports are presented as VLAN sub-interfaces, so the friendly port name shown here is derived from the VLAN description held in the configuration.

        InterfaceHeading = Logical Interfaces
        InterfaceTable   = Logical Interfaces
        InterfaceName    = Interface
        SystemName       = System Name
        IpAddress        = IP Address
        SubnetMask       = Subnet Mask
        SecondaryAddress = Secondary Address
        IPv6Address      = IPv6 Address
        VlanTag          = VLAN Tag
        InterfaceIndex   = Index

        VlanHeading      = VLANs
        VlanTable        = VLAN Configuration
        VlanId           = VLAN ID
        VlanDescription  = Description

        RouteHeading     = Static Routes
        RouteTable       = Static Routes
        Destination      = Destination
        Gateway          = Gateway
        Metric           = Metric
        DefaultRoute     = Default Route

        DhcpHeading      = DHCP
        DhcpPoolTable    = DHCP Pools
        DhcpClientTable  = DHCP Static Clients
        PoolName         = Pool Name
        MacAddress       = MAC Address

        ArpHeading       = Static ARP
        ArpTable         = Static ARP Entries

        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # Media section translations (Get-AbrRibbonSWeEdgeMedia)
    GetAbrRibbonSWeEdgeMediaConfiguration = ConvertFrom-StringData @'
        InfoLevel        = Media InfoLevel set at {0}.
        Collecting       = Collecting Media information.
        NotFound         = No media configuration was found.

        Heading          = Media
        SectionInfo      = The following section details how the SBC handles media such as audio or video. A media list defines which codecs are offered and in what order of preference, and is applied to a signalling group. The order matters, because the first codec that both ends support is the one used for the call. Note: There are some cases where the SBC will select a codec that is less desirable than the first codec to save compute resources should the SBC be using Dynamic-DSP mode instead of transcoding one wideband codec to another if a common narrowband codec is available.

        ListHeading      = Media Lists
        ListTable        = Media Lists
        ListName         = Media List
        Codecs           = Codecs (in preference order)
        CryptoProfile    = Crypto Profile
        DtlsProfile      = DTLS Profile
        Dscp             = DSCP
        DigitRelay       = Digit Relay

        VoiceHeading     = Voice Codec Profiles
        VoiceTable       = Voice Codec Profiles
        CodecName        = Codec
        PayloadType      = Payload Type
        PacketTime       = Packet Time (ms)
        BitRate          = Rate (bps)

        FaxHeading       = Fax Codec Profiles
        FaxTable         = Fax Codec Profiles

        CryptoHeading    = Media Crypto Profiles
        CryptoTable      = Media Crypto Profiles
        CryptoSuite      = Crypto Suite
        Operation        = Operation

        DetailTable      = Media List Detail
        DeadCall         = Dead Call Detection
        SilenceSupp      = Silence Suppression
        CodecPriority    = Enforce SG Codec Priority
        ChangeSsrc       = Change SSRC
        ModemPassthrough = Modem Passthrough
        FaxPassthrough   = Fax Passthrough
        FaxToneDetect    = Fax Tone Detection
        RtcpMode         = RTCP Mode
        DigitRelayType   = Digit (DTMF) Relay Type
        DigitPayload     = Digit Relay Payload Type

        Enable           = Enable
        Disable          = Disable
        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
        Unknown          = Unknown ({0})
'@

    # Signaling group section translations (Get-AbrRibbonSWeEdgeSignalingGroup)
    GetAbrRibbonSWeEdgeSignalingGroup = ConvertFrom-StringData @'
        InfoLevel        = SignalingGroup InfoLevel set at {0}.
        Collecting       = Collecting Signaling Group information.
        NotFound         = No signaling groups were found in the configuration.

        Heading          = Signaling Groups
        SectionInfo      = The following section details the signalling groups configured on the SBC. A signalling group represents a single trunk or endpoint relationship. It defines which far end the SBC will exchange SIP with, over which network interface, using which media list, and which call route table applies to calls arriving on it.
        Drain            = Drain
        DrainInfo        = A group left in the Drain state is highlighted below. It still answers OPTIONS and so appears healthy to monitoring, but it rejects any call offered to it. Draining is a maintenance step, so a drained group in a finished build usually means it was never put back into service.
        DisabledInfo     = A disabled group is highlighted below. It carries no calls and does not respond on its listen ports. This is usually deliberate, but it is also the common explanation for a trunk that appears fully configured and does not work.
        UnresolvedInfo   = A group highlighted as unresolved refers to an object that is not present in this configuration, such as a route table or media list that was deleted while the reference to it was left in place. The group will not behave the way the configuration reads. Note that the broken reference may be in a field that is not shown at the current detail level.
        RecorderInfo     = Signaling groups numbered 50000 and above are SIPREC recorders.

        SummaryTable     = Signaling Groups
        GroupId          = ID
        GroupType        = Type
        GroupName        = Description
        State            = State
        RouteTable       = Route Table
        MediaList        = Media List
        SipProfile       = SIP Profile
        SipServer        = SIP Server Table
        ToneTable        = Tone Table
        ActionSet        = Action Set
        Channels         = Channels
        PhysicalPort     = Port

        DetailTable      = Signaling Group Detail
        SignalingIf      = Signaling Interface
        MediaIf          = Media Interface
        ListenPorts      = Listen Ports
        FederatedHosts   = Federated IP/FQDN
        NatPublic        = Public NAT Address
        InboundNat       = Inbound NAT Detection
        PrivateMedia     = Private Media Source

        AudioMode        = Audio Stream Mode
        VideoMode        = Video Stream Mode
        ServerSelection  = Server Selection
        NatTraversal     = NAT Traversal
        OutboundProxy    = Outbound Proxy
        IngressRules     = Ingress Message Rules
        EgressRules      = Egress Message Rules
        SipToQ850        = SIP to Q.850 Table
        Q850ToSip        = Q.850 to SIP Table

        IsdnVariant      = ISDN Switch Variant
        IsdnOrientation  = ISDN Side Orientation
        IsdnHuntMethod   = ISDN Hunt Method
        IsdnChannel      = ISDN Indicated Channel

        OptionsTable     = Protocol Options
        Option           = Option
        Setting          = Setting
        ChallengeRequest = Challenge Request
        Early183         = Early 183
        IceSupport       = ICE Support
        RegisterKeepAlive = Register Keep Alive
        RtcpMultiplexing = RTCP Multiplexing
        QoeReporting     = QoE Reporting

        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # Call routing section translations (Get-AbrRibbonSWeEdgeCallRouting)
    GetAbrRibbonSWeEdgeCallRouting = ConvertFrom-StringData @'
        InfoLevel        = CallRouting InfoLevel set at {0}.
        Collecting       = Collecting Call Routing information.
        NotFound         = No call routing tables were found in the configuration.

        Heading          = Call Routing
        SectionInfo      = The following section details how the SBC routes calls. A call arriving on a signalling group is matched against that group's route table. Route entries are evaluated in the order shown until one matches, and each entry references a transformation table which both tests the call and rewrites its numbers.
        OrderInfo        = Routes and rules are listed in the order the SBC evaluates them, which is not the same as identifier order.
        DisabledRouteInfo = A disabled route is highlighted below. It is skipped during evaluation, so a call that appears to match it will fall through to the next route in the table, or fail if none follows.
        UnresolvedInfo   = A route highlighted as unresolved refers to an object that is not present in this configuration, such as a destination signalling group or transformation table that was deleted while the reference to it was left in place. The route cannot send a call where it appears to send it.

        RouteHeading     = Route Tables
        RouteSummary     = Route Tables
        RouteEntryTable  = Routes
        TableName        = Table
        RouteCount       = Routes
        Order            = Order
        RouteName        = Route
        RouteType        = Type
        Destination      = Destination
        Transformation   = Transformation Table
        MediaOverride    = Media Override
        TimeOfDay        = Time of Day
        Priority         = Priority

        TransformHeading = Transformation Tables
        TransformSummary = Transformation Tables
        RuleTable        = Rules
        RuleCount        = Rules
        UsedBy           = Used By
        Requirement      = Requirement
        InputField       = Input Field
        InputValue       = Input Value
        OutputField      = Output Field
        OutputValue      = Output Value
        MatchInfo        = A table succeeds only when every enabled Mandatory rule matches. If an Optional rule exists for a certain match type (IE Calling Number) then it must match at least one Optional Rule for that match type. Any additional Optional rules that do not match will not fail the table.

        State            = State
        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # Emergency services section translations (Get-AbrRibbonSWeEdgeEmergencyService)
    GetAbrRibbonSWeEdgeEmergencyService = ConvertFrom-StringData @'
        InfoLevel        = EmergencyService InfoLevel set at {0}.
        Collecting       = Collecting Emergency Services information.
        NotFound         = No emergency services configuration was found.

        Heading          = Emergency Services
        SectionInfo      = The following section details the emergency services configuration. A callback number pool provides the number an emergency operator will dial back on, and a notification manager alerts nominated recipients when an emergency call is placed.

        ConfigHeading    = Configuration
        ConfigTable      = Emergency Services Configuration
        ServiceState     = Emergency Services
        CallStatus       = Call Status Duration (hours)
        Preempt          = Preempt Non-Emergency Calls

        CallbackHeading  = Callback Number Pool
        CallbackTable    = Callback Number Pools
        PoolName         = Pool
        PsapNumber       = PSAP Number
        CallbackNumbers  = Callback Numbers

        NotifyHeading    = Notification Manager
        NotifyTable      = Notification Managers
        NotifyName       = Notification Manager
        Recipients       = Recipients
        NotifyMessage    = Message
        MonitorInterval  = Monitoring Interval
        ClientId         = Client ID

        State            = State
        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # Security section translations (Get-AbrRibbonSWeEdgeSecurity)
    GetAbrRibbonSWeEdgeSecurity = ConvertFrom-StringData @'
        InfoLevel        = Security InfoLevel set at {0}.
        Collecting       = Collecting Security information.
        NotFound         = No security configuration was found.

        Heading          = Security
        SectionInfo      = The following section details the certificates presented by the SBC and the TLS profiles that govern encrypted signalling. An expired certificate takes a secure trunk out of service, so the remaining validity of each appliance certificate is shown. Days remaining is counted from the date this report was generated and will be out of date if the report is read later. Certificate content and private keys are never included in this report. The account policy at the end of this section governs who may sign in to the appliance, which is the other half of the security question.
        ExpiryInfo       = A certificate that has already expired, or that expires within the warning period, has its entire row highlighted below. An expired appliance certificate takes every trunk that relies on it out of service, so these should be renewed before the dates shown.

        PolicyHeading     = Account Policy
        PasswordTable     = Password Policy
        SessionTable      = Session and Lockout Policy
        MinimumLength     = Minimum Length
        MinimumUpper      = Minimum Uppercase Characters
        MinimumLower      = Minimum Lowercase Characters
        MinimumDigits     = Minimum Digits
        MinimumSpecial    = Minimum Special Characters
        MinimumChanged    = Minimum Characters Changed
        MaximumConsecutive = Maximum Repeated Characters
        MaximumSameClass  = Maximum Consecutive Same Class
        ExpiryEnforced    = Password Expiry
        MinimumLife       = Minimum Password Life (days)
        MaximumLife       = Maximum Password Life (days)
        HistoryRemembered = Previous Passwords Remembered
        EnhancedSecurity  = Enhanced Password Security
        RecoveryAllowed   = Password Recovery
        DisplayAllowed    = Password Display
        BrowserSaveAllowed = Browser Password Save
        FailedLogins      = Failed Logins Before Lockout
        LockoutTime       = Lockout Duration (minutes)
        IdleTimeout       = Idle Session Timeout (minutes)
        MaximumSession    = Maximum Concurrent Sessions
        InactivityOff     = Disable Account After Inactivity (days)
        PreLoginAck       = Pre-Login Banner Acknowledgement

        DirectoryHeading  = Active Directory
        DirectoryTable    = Active Directory Configuration
        ControllerTable   = Domain Controllers
        OperatingMode     = Operating Mode
        UseTls            = LDAP over TLS
        UpdateFrequency   = Cache Update Frequency
        NestedGroups      = Nested Group Lookups
        CacheEncrypted    = Cache Encryption
        SearchScope       = Search Scope
        Timeout           = Timeout

        RadiusHeading     = RADIUS
        RadiusTable       = RADIUS Configuration
        RadiusServerTable = RADIUS Servers
        Authentication    = Authentication
        Accounting        = Accounting
        AccountingMode    = Accounting Mode
        AccountServer1    = Accounting Server 1
        AccountServer2    = Accounting Server 2
        PrimaryServer     = Primary Server
        SecondServer      = Secondary Server
        FailoverTime      = Failover Timeout
        Server            = Server
        Priority          = Priority
        Port              = Port
        PacketType        = Connectivity Packet Type

        CertHeading      = Certificates
        CertTable        = Certificates
        RootHeading      = Trusted Root Certificates
        RootTable        = Trusted Root Certificates
        CommonName       = Common Name
        CertType         = Type
        SubjectAltName   = Subject Alternative Name
        Issuer           = Issuer
        Expires          = Expires
        DaysRemaining    = Days Remaining
        SerialNumber     = Serial Number
        SignatureAlgo    = Signature Algorithm
        VerifyStatus     = Verification

        TlsHeading       = TLS Profiles
        TlsTable         = TLS Profiles
        ProfileName      = Profile
        TlsVersion       = TLS Version
        MutualAuth       = Mutual Authentication
        VerifyPeer       = Verify Peer Certificate
        ValidateServer   = Validate Server FQDN
        ValidateClient   = Validate Client FQDN
        OcspStapling     = OCSP Stapling
        CipherCount      = Ciphers

        Expired          = Expired

        State            = State
        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # SIP section translations (Get-AbrRibbonSWeEdgeSip)
    GetAbrRibbonSWeEdgeSip = ConvertFrom-StringData @'
        InfoLevel        = SIP InfoLevel set at {0}.
        Collecting       = Collecting SIP information.
        NotFound         = No SIP configuration was found.

        Heading          = SIP
        SectionInfo      = The following section details the SIP server tables and profiles. A server table lists the far end servers for a trunk, and the SBC attempts them in the order shown. A SIP profile controls how the SBC formats and times SIP messages toward that trunk.
        OrderInfo        = Servers are listed in the order the SBC attempts them when using round robin or first routing.

        ServerHeading    = SIP Server Tables
        ServerSummary    = SIP Server Tables
        ServerTable      = Servers
        TableName        = Server Table
        ServerCount      = Servers
        MixedTlsWarning  = One or more server tables use more than one TLS profile. This is usually unintended and is highlighted below.
        Order            = Order
        ServerHost       = Host
        Port             = Port
        Protocol         = Protocol
        Priority         = Priority
        Monitor          = Monitor
        KeepAlive        = Keep Alive (s)
        TlsProfile       = TLS Profile
        RemoteAuth       = Remote Authorization
        Registrant       = Contact Registrant

        ProfileHeading   = SIP Profiles
        ProfileTable     = SIP Profiles
        ProfileName      = Profile
        UserAgent        = User Agent Header
        StaticHost       = Static Host
        SessionTimer     = Session Timer
        SessionExpires   = Session Expires (s)
        SessionMinSe     = Minimum SE (s)

        State            = State
        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # Logging section translations (Get-AbrRibbonSWeEdgeLogging)
    GetAbrRibbonSWeEdgeLogging = ConvertFrom-StringData @'
        InfoLevel        = Logging InfoLevel set at {0}.
        Collecting       = Collecting Logging information.
        NotFound         = No logging configuration was found.

        Heading          = Logging and Monitoring
        SectionInfo      = The following section details where the SBC sends its logs and which management systems may poll it. SNMP community strings are not included in this report due to their sensitive nature.
        VerboseInfo      = A syslog destination or subsystem left at Trace or Debug generates significant load and disk usage, and is highlighted below. Verbose logging is a troubleshooting step, so finding it in a finished build usually means it was never turned back down.

        SyslogHeading    = Syslog Destinations
        SyslogTable      = Syslog Destinations
        Address          = Address
        Port             = Port
        Transport        = Transport
        Level            = Level
        Facility         = Facility

        SnmpHeading      = SNMP
        SnmpTable        = SNMP Managers
        Version          = Version
        TrapEnabled      = Traps
        UserName         = User Name

        DebugHeading     = Subsystem Log Levels
        DebugTable       = Subsystem Log Levels
        Subsystem        = Subsystem

        State            = State
        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # Physical telephony port translations (Get-AbrRibbonSWeEdgePhysicalTelephonyPort)
    GetAbrRibbonSWeEdgePhysicalTelephonyPort = ConvertFrom-StringData @'
        InfoLevel        = PhysicalTelephonyPort InfoLevel set at {0}.
        Collecting       = Collecting Physical Telephony Port information.
        NotFound         = No physical telephony ports are present on this platform.

        Heading          = Physical Telephony Ports
        SectionInfo      = The following section details the physical telephony ports fitted to the SBC. Digital ports carry ISDN or CAS signalling and are referenced by signalling groups, while analog ports provide FXS and FXO connections for handsets, paging equipment and legacy devices.

        DigitalHeading   = Digital Ports
        DigitalTable     = Digital Ports
        AnalogHeading    = Analog Ports
        AnalogTable      = Analog Ports

        PortName         = Port
        Alias            = Alias
        PortType         = Type
        PhysicalType     = Physical
        SignalingType    = Signaling
        RxGain           = Rx Gain
        TxGain           = Tx Gain

        State            = State
        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # Telephony mapping translations (Get-AbrRibbonSWeEdgeTelephonyMapping)
    GetAbrRibbonSWeEdgeTelephonyMapping = ConvertFrom-StringData @'
        InfoLevel        = TelephonyMapping InfoLevel set at {0}.
        Collecting       = Collecting Telephony Mapping information.
        NotFound         = No telephony mapping tables were found.

        Heading          = Telephony Mapping
        SectionInfo      = The following section details the tables that translate between signalling protocols and handle call failure. A cause code reroute table lets a call be retried on another route when the far end returns particular Q.850 causes, and the SIP to Q.850 tables map between SIP response codes and ISDN cause values.

        RerouteHeading   = Cause Code Reroute Tables
        RerouteTable     = Cause Code Reroute Tables
        TableName        = Table
        CauseCodes       = Trigger Cause Codes

        MessageHeading   = Message Translation Tables
        MessageTable     = Message Translation Tables
        MessageEntry     = Message Translation Rules
        SipQ850Heading   = SIP to Q.850
        SipQ850Table     = SIP to Q.850 Tables
        SipQ850Entry     = SIP to Q.850 Mappings
        Q850SipHeading   = Q.850 to SIP
        Q850SipTable     = Q.850 to SIP Tables
        Q850SipEntry     = Q.850 to SIP Mappings
        ToneHeading      = Tone Tables
        ToneTable        = Tone Tables
        ToneEntry        = Tone Profiles

        EntryCount       = Entries
        Rule             = Rule
        InMessage        = Inbound Message
        OutMessage       = Outbound Message
        InIeType         = Inbound IE
        OutIeType        = Outbound IE
        SendMessage      = Send Message
        MediaCutThrough  = Media Cut Through
        EarlyMedia       = Early Media
        PiPresent        = PI Present
        PiSelection      = PI Selection
        PiValue          = PI Value
        SipResponse      = SIP Response
        Q850Cause        = Q.850 Cause
        ToneType         = Tone
        Frequency        = Frequency (Hz)
        Amplitude        = Amplitude (dBm)
        CadenceOn        = Cadence On (ms)
        CadenceOff       = Cadence Off (ms)
        Cadence2On       = Second Cadence On (ms)
        Cadence2Off      = Second Cadence Off (ms)

        State            = State
        Enabled          = Enabled
        Disabled         = Disabled
        None             = None configured
        NotSet           = Not set
'@

    # Unreferenced object health check translations (Get-AbrRibbonSWeEdgeUnreferenced)
    GetAbrRibbonSWeEdgeUnreferenced = ConvertFrom-StringData @'
        Collecting       = Checking for unreferenced configuration objects.
        NotFound         = Every configuration object is referenced.

        Heading          = Unreferenced Objects
        SectionInfo      = The following objects are defined on the SBC but nothing refers to them. This is usually stale configuration left behind when a table was superseded rather than a fault, and the WebUI gives no way to spot it because nothing lists the referrers of a table. Factory default tables commonly appear here on an appliance that has been fully configured. An object shown as referenced only by disabled configuration is still wired in: re-enabling one route entry brings it back into use, so it is listed separately rather than as unreferenced.

        SummaryTable     = Unreferenced Objects
        ObjectType       = Type
        ObjectId         = ID
        ObjectName       = Name
        Status           = Status
        StatusUnreferenced = Unreferenced
        StatusDisabledReferrer = Referenced by disabled configuration only

        TypeTransformation = Transformation Table
        TypeTranslation  = Translation Table
        TypeRoutingTable = Route Table
        TypeMessageRule  = Message Rule Table
        TypeMediaList    = Media List
        TypeSipProfile   = SIP Profile
        TypeSipServer    = SIP Server Table
        TypeTlsProfile   = TLS Profile
        TypeToneTable    = Tone Table
        TypeActionSet    = Action Set
'@
}

