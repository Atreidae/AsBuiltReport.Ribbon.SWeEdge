function Resolve-AbrRibbonFirewallRule {
    <#
    .SYNOPSIS
        Derives the network flows a Ribbon SBC requires from its own configuration.
    .DESCRIPTION
        Network teams routinely ask which flows have to be permitted for an SBC to work.
        Answering that from a vendor requirements document produces a generic list, most of
        which does not apply. This function instead reads the appliance's own configuration
        and emits only the flows that the configured services actually need: the DNS and NTP
        servers it was given, the syslog and SNMP destinations it was told about, the SIP
        ports its signalling groups listen on, the hosts in its SIP server tables, and the
        media port range it was assigned.

        Two things genuinely cannot be derived from a configuration export:

        - The source port of an outbound TCP or TLS connection is chosen by the operating
          system at connect time, so it is reported as ephemeral rather than guessed. This
          does not apply to UDP: SIP over UDP is symmetric, so the appliance sends from the
          same port it listens on and that port is reported instead.
        - The media port range of the far end belongs to the far end. It is left as an
          explicit placeholder unless the peer is one of the well known providers below.

        Where a SIP server or federated host matches a published provider endpoint, that
        provider's documented media ranges are injected. Matching is by exact host name or
        exact domain suffix, never by partial or fuzzy comparison, so a host that merely
        resembles a provider endpoint is not claimed to be one.

        The appliance's own access control list is also returned. That is a separate concern
        from the upstream firewall, but it is the on-box equivalent and is frequently the
        reason a flow that was permitted upstream still does not work.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject with Flow, AccessControl, KnownPeer,
        MediaPortRange and SbcAddress.
    .NOTES
        Version:    0.1.0
        Author:     James Arber

        Provider ranges are published by the provider and do change. They are reported with a
        note telling the reader to confirm against current provider documentation, because a
        stale range in an as built document is worse than no range at all.
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonFirewallRule -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml

    # Values that cannot be derived from the configuration. Held as constants so the wording
    # is consistent everywhere it appears and can be changed in one place.
    $Ephemeral = 'Ephemeral'
    $AnyHost = 'Any'
    $AdminNetwork = 'Administrative networks'
    $RemoteMedia = 'Peer media port range (confirm with provider)'
    # SIP over UDP is symmetric, so the far end sends from the port it listens on. That port
    # belongs to the far end and is not in this appliance's configuration, but it is still
    # wrong to call it ephemeral.
    $PeerSipPort = 'Peer signalling port'

    # Published provider endpoints are shared with the topology diagram through
    # Find-AbrRibbonProvider. The list is read once so a provider is the same object each
    # time it is matched, which the detected provider list relies on.
    $KnownProvider = @(Get-AbrRibbonKnownProvider)

    $MatchProvider = {
        param([String] $Address)

        Find-AbrRibbonProvider -Address $Address -Provider $KnownProvider
    }

    $Flow = [System.Collections.Generic.List[PSObject]]::new()
    $SeenFlow = [System.Collections.Generic.HashSet[String]]::new([StringComparer]::OrdinalIgnoreCase)

    # Loopback and wildcard destinations are handled inside the appliance. A firewall rule
    # for them is meaningless, and including one invites an argument with the network team.
    $IsRoutable = {
        param([String] $Address)

        if ([String]::IsNullOrWhiteSpace($Address)) { return $false }

        $Trimmed = $Address.Trim()
        if ($Trimmed -in @('0.0.0.0', '::', '::1')) { return $false }

        -not $Trimmed.StartsWith('127.')
    }

    $AddFlow = {
        param(
            [String] $Purpose,
            [String] $Direction,
            [String] $Source,
            [String] $SourcePort,
            [String] $Destination,
            [String] $DestinationPort,
            [String] $Protocol,
            [String] $Note
        )

        # A flow with no destination is a service that was never configured. Emitting a row
        # with an empty address would imply the firewall needs a rule that it does not.
        if ([String]::IsNullOrWhiteSpace($Destination) -or [String]::IsNullOrWhiteSpace($Source)) {
            return
        }

        # Deduplicated on insertion rather than by sorting afterwards, because the table is
        # ordered by the sequence the rules are built in, which reads as management first,
        # then infrastructure, then signalling, then media.
        $Key = ($Purpose, $Direction, $Source, $SourcePort, $Destination, $DestinationPort, $Protocol) -join '|'
        if (-not $SeenFlow.Add($Key)) {
            return
        }

        $Flow.Add([PSCustomObject]@{
                Purpose         = $Purpose
                Direction       = $Direction
                Source          = $Source
                SourcePort      = $SourcePort
                Destination     = $Destination
                DestinationPort = $DestinationPort
                Protocol        = $Protocol
                Note            = $Note
            })
    }

    #region SBC addresses
    $Interface = @(Resolve-AbrRibbonNetworkInterface -Config $Config)

    $InterfaceAddress = @(
        $Interface |
            Where-Object { -not [String]::IsNullOrWhiteSpace($_.IPv4Primary) -and $_.IPv4Primary -ne '0.0.0.0' } |
            ForEach-Object { $_.IPv4Primary }
    ) | Select-Object -Unique

    $SbcAddress = if ($InterfaceAddress) { $InterfaceAddress -join ', ' } else { 'SBC' }
    #endregion SBC addresses

    #region Management interface
    # Web management, syslog and SNMP are served only on the management interface, not on
    # every configured interface. Which port that is depends on the platform: the SWe Lite
    # has a dedicated mgt0 admin port, while the 1000 and 2000 appliances use the first
    # Ethernet port.
    #
    # The two platforms have to be matched on different properties. On the 1000 and 2000 the
    # Ethernet port name is derived from the VLAN description and an interface alias cannot
    # override it, so the display name is a safe match. On the SWe Lite an alias does become
    # the display name, so the raw system name is the only stable identifier.
    $ManagementInterface = switch ($Config.PlatformType) {
        'SWeLite' { @($Interface | Where-Object { $_.Name -eq 'mgt0' }) }
        default { @($Interface | Where-Object { $_.DisplayName -eq 'Ethernet 1' }) }
    }

    $ManagementAddress = @(
        $ManagementInterface |
            Where-Object { & $IsRoutable $_.IPv4Primary } |
            ForEach-Object { $_.IPv4Primary }
    ) | Select-Object -Unique

    # If the expected port is missing or has no address, every interface address is reported
    # rather than dropping the flow. Over-reporting is recoverable, silently omitting a rule
    # the appliance needs is not.
    $ManagementNarrowed = [Bool]$ManagementAddress
    $ManagementText = if ($ManagementNarrowed) { $ManagementAddress -join ', ' } else { $SbcAddress }
    $ManagementNote = if ($ManagementNarrowed) { '' } else { ' The management port could not be identified in this configuration, so every interface address is listed.' }
    #endregion Management interface

    #region Management
    # The web interface and REST API are how the appliance is administered, so this flow
    # always exists. The source cannot be derived, because the configuration does not record
    # which networks the administrators sit on.
    & $AddFlow 'Management (WebUI and REST API)' 'Inbound' $AdminNetwork $Ephemeral $ManagementText '443' 'TCP' ('Restrict to administrative networks.' + $ManagementNote)
    #endregion Management

    #region Name resolution and time
    # DNS, NTP and directory lookups are appliance services rather than call traffic, so they
    # leave from the management interface: the admin port on a SWe Lite, the first Ethernet
    # port on a 1000 or 2000. They do not source from the signalling or media interfaces.
    $SystemNet = $Xml.Configuration.SelectNodes("Token[@name='System']/Token[@name='SystemNet']") | ConvertFrom-AbrRibbonIeNode

    $DnsServer = @(
        $SystemNet.PrimaryDNSServer
        $SystemNet.SecondaryDNSServer
    ) | Where-Object { & $IsRoutable $_ } | Select-Object -Unique

    if ($DnsServer) {
        & $AddFlow 'DNS' 'Outbound' $ManagementText $Ephemeral ($DnsServer -join ', ') '53' 'UDP and TCP' ('TCP is required for responses that exceed the UDP payload limit, which SRV and large A record sets often do.' + $ManagementNote)
    }

    # Each NTP server has its own enable flag, so a configured but disabled server is not a
    # flow the firewall needs to carry.
    $NtpServer = @(
        if ($SystemNet.IsNtp1Enabled -eq '1') { $SystemNet.Ntp1ServerName }
        if ($SystemNet.IsNtp2Enabled -eq '1') { $SystemNet.Ntp2ServerName }
    ) | Where-Object { & $IsRoutable $_ } | Select-Object -Unique

    if ($NtpServer) {
        & $AddFlow 'NTP' 'Outbound' $ManagementText $Ephemeral ($NtpServer -join ', ') '123' 'UDP' ('Some clients source from port 123 rather than an ephemeral port. Permit both if the flow fails.' + $ManagementNote)
    }
    #endregion Name resolution and time

    #region Logging and monitoring
    $Logging = Resolve-AbrRibbonLogging -Config $Config

    # Syslog and SNMP are sourced from and served on the management interface, not on the
    # signalling interfaces.
    foreach ($Syslog in @($Logging.SyslogServer | Where-Object { $_.State -eq 'Enabled' -and (& $IsRoutable $_.Address) })) {
        & $AddFlow 'Syslog' 'Outbound' $ManagementText $Ephemeral $Syslog.Address $Syslog.Port $Syslog.Transport $ManagementNote.Trim()
    }

    $SnmpManager = @($Logging.SnmpManager | Where-Object { $_.State -eq 'Enabled' -and (& $IsRoutable $_.Address) })

    if ($SnmpManager) {
        $ManagerAddress = @($SnmpManager | ForEach-Object { $_.Address }) | Select-Object -Unique
        & $AddFlow 'SNMP polling' 'Inbound' ($ManagerAddress -join ', ') $Ephemeral $ManagementText '161' 'UDP' $ManagementNote.Trim()

        $TrapManager = @($SnmpManager | Where-Object { $_.TrapEnabled -eq 'Enabled' } | ForEach-Object { $_.Address }) | Select-Object -Unique
        if ($TrapManager) {
            & $AddFlow 'SNMP traps' 'Outbound' $ManagementText $Ephemeral ($TrapManager -join ', ') '162' 'UDP' $ManagementNote.Trim()
        }
    }
    #endregion Logging and monitoring

    #region Directory services
    $DirectoryConfig = $Xml.Configuration.SelectNodes("Token[@name='AD']/IE[@classname='ADS_AD_CONFIG']") | ConvertFrom-AbrRibbonIeNode

    if ($DirectoryConfig -and $DirectoryConfig.Enabled -eq '1') {

        # The whole feature carries one TLS flag, so the port is the same for every
        # controller rather than being decided per controller.
        $UseTls = $DirectoryConfig.UseTLS -eq '1'
        $LdapPort = if ($UseTls) { '636' } else { '389' }
        $LdapNote = if ($UseTls) { 'LDAP over TLS.' } else { 'Plain LDAP. Credentials cross the network unprotected.' }

        $Controller = @(
            $Xml.Configuration.SelectNodes("Token[@name='AD']//IE[@classname='ADS_AD_DOMAINCONTROLLERS']") |
                ConvertFrom-AbrRibbonIeNode |
                Where-Object { $_.Enabled -eq '1' -and (& $IsRoutable $_.DomainController) } |
                ForEach-Object { $_.DomainController }
        ) | Select-Object -Unique

        if ($Controller) {
            & $AddFlow 'Active Directory (LDAP)' 'Outbound' $ManagementText $Ephemeral ($Controller -join ', ') $LdapPort 'TCP' ($LdapNote + $ManagementNote)
        }
    }
    #endregion Directory services

    #region SIP signalling
    $SignalingGroup = @(Resolve-AbrRibbonSignalingGroup -Config $Config | Where-Object { $_.Type -eq 'SIP' })
    $Sip = Resolve-AbrRibbonSipConfiguration -Config $Config

    $DetectedProvider = [System.Collections.Generic.List[PSObject]]::new()

    # Traffic to a provider leaves from the interfaces of the signalling groups that actually
    # reach it, not from every interface on the appliance. Listing a private interface as the
    # source of a flow to Microsoft is wrong, and a network team asked to permit it will
    # either refuse or open something that was never needed.
    $ProviderInterface = @{}

    $TrackProvider = {
        param([PSObject] $Provider, [PSObject] $Group)

        if (-not $DetectedProvider.Contains($Provider)) {
            $DetectedProvider.Add($Provider)
        }

        if (-not $ProviderInterface.ContainsKey($Provider.Name)) {
            $ProviderInterface[$Provider.Name] = [PSCustomObject]@{
                Signaling = [System.Collections.Generic.List[String]]::new()
                Media     = [System.Collections.Generic.List[String]]::new()
            }
        }

        if (-not $Group) {
            return
        }

        $Entry = $ProviderInterface[$Provider.Name]

        if (-not [String]::IsNullOrWhiteSpace($Group.SignalingInterface) -and -not $Entry.Signaling.Contains($Group.SignalingInterface)) {
            $Entry.Signaling.Add($Group.SignalingInterface)
        }

        if (-not [String]::IsNullOrWhiteSpace($Group.MediaInterface) -and -not $Entry.Media.Contains($Group.MediaInterface)) {
            $Entry.Media.Add($Group.MediaInterface)
        }
    }

    # Many signalling groups usually share a small number of listening sockets. Grouping by
    # socket keeps the table to the handful of rules a firewall actually needs, instead of
    # one near identical row per signalling group.
    $Listener = @{}

    foreach ($Group in $SignalingGroup) {
        foreach ($Listen in @($Group.ListenPort)) {
            if ([String]::IsNullOrWhiteSpace($Listen.Port)) {
                continue
            }

            $Key = '{0}|{1}|{2}' -f $Group.SignalingInterface, $Listen.Port, $Listen.Protocol
            if (-not $Listener.ContainsKey($Key)) {
                $Listener[$Key] = [PSCustomObject]@{
                    Interface = $Group.SignalingInterface
                    Port      = $Listen.Port
                    Protocol  = $Listen.Protocol
                    Peer      = [System.Collections.Generic.List[String]]::new()
                    Unlimited = $false
                }
            }

            $Entry = $Listener[$Key]
            $Federated = @($Group.FederatedHost | Where-Object { -not [String]::IsNullOrWhiteSpace($_) })

            if ($Federated) {
                foreach ($Peer in $Federated) {
                    if (-not $Entry.Peer.Contains($Peer)) {
                        $Entry.Peer.Add($Peer)
                    }
                    foreach ($Provider in (& $MatchProvider $Peer)) {
                        & $TrackProvider $Provider $Group
                    }
                }
            } else {
                # No federated host list means the group accepts signalling from anywhere.
                # That is worth stating plainly rather than leaving the source blank.
                $Entry.Unlimited = $true
            }
        }
    }

    foreach ($Entry in ($Listener.Values | Sort-Object -Property Interface, @{ Expression = { [Int]$_.Port } })) {
        $Source = if ($Entry.Unlimited -or -not $Entry.Peer.Count) { $AnyHost } else { ($Entry.Peer -join ', ') }
        $Note = if ($Entry.Unlimited) { 'At least one signalling group on this socket has no federated address restriction.' } else { '' }

        # A peer opening a TCP or TLS connection uses an ephemeral source port. A peer
        # sending SIP over UDP sends from its own signalling port, which is not ephemeral
        # and is not something this appliance's configuration records.
        $SourcePort = if ($Entry.Protocol -eq 'UDP') { $PeerSipPort } else { $Ephemeral }

        & $AddFlow 'SIP signalling' 'Inbound' $Source $SourcePort $Entry.Interface $Entry.Port $Entry.Protocol $Note
    }

    # Outbound signalling is defined by the SIP server tables. The same server can appear in
    # several tables, so these are grouped by socket too.
    #
    # A server table is reached from the signalling group, not the other way round, so the
    # reverse map is built first. It is what lets an outbound flow be attributed to the
    # interface and listen port of the group that actually carries it, instead of to every
    # address on the appliance.
    $TableUse = @{}

    foreach ($Group in $SignalingGroup) {
        if ([String]::IsNullOrWhiteSpace($Group.SipServerName)) {
            continue
        }

        if (-not $TableUse.ContainsKey($Group.SipServerName)) {
            $TableUse[$Group.SipServerName] = [System.Collections.Generic.List[PSObject]]::new()
        }
        $TableUse[$Group.SipServerName].Add($Group)
    }

    $Destination = @{}

    foreach ($Table in @($Sip.ServerTable)) {
        $Using = @(
            if ($Table.Description -and $TableUse.ContainsKey($Table.Description)) {
                $TableUse[$Table.Description]
            }
        )

        # A table no signalling group references carries no traffic, so there is no interface
        # to name. Falling back to every address over-reports, which is recoverable, rather
        # than dropping a flow that might be needed.
        $SourceInterface = @(
            $Using |
                Where-Object { -not [String]::IsNullOrWhiteSpace($_.SignalingInterface) } |
                ForEach-Object { $_.SignalingInterface }
        ) | Select-Object -Unique

        $SourceText = if ($SourceInterface) { $SourceInterface -join ', ' } else { $SbcAddress }

        $TableUdpPort = @(
            $Using |
                ForEach-Object { $_.ListenPort } |
                Where-Object { $_.Protocol -eq 'UDP' -and -not [String]::IsNullOrWhiteSpace($_.Port) } |
                ForEach-Object { [String]$_.Port }
        ) | Select-Object -Unique

        $TableUdpSource = if ($TableUdpPort) { ($TableUdpPort | Sort-Object { [Int]$_ }) -join ', ' } else { '' }

        foreach ($Server in @($Table.Server)) {
            if ([String]::IsNullOrWhiteSpace($Server.Host)) {
                continue
            }

            $SourcePort = if ($Server.Protocol -eq 'UDP' -and $TableUdpSource) { $TableUdpSource } else { $Ephemeral }

            $Key = '{0}|{1}|{2}|{3}|{4}' -f $Server.Host, $Server.Port, $Server.Protocol, $SourcePort, $SourceText
            if (-not $Destination.ContainsKey($Key)) {
                $Destination[$Key] = [PSCustomObject]@{
                    Host       = $Server.Host
                    Port       = $Server.Port
                    Protocol   = $Server.Protocol
                    Source     = $SourceText
                    SourcePort = $SourcePort
                }
            }

            foreach ($Provider in (& $MatchProvider $Server.Host)) {
                if ($Using) {
                    foreach ($Group in $Using) {
                        & $TrackProvider $Provider $Group
                    }
                } else {
                    & $TrackProvider $Provider $null
                }
            }
        }
    }

    foreach ($Entry in ($Destination.Values | Sort-Object -Property Host, @{ Expression = { [Int]$_.Port } })) {
        & $AddFlow 'SIP signalling' 'Outbound' $Entry.Source $Entry.SourcePort $Entry.Host $Entry.Port $Entry.Protocol ''
    }
    #endregion SIP signalling

    #region Media
    $MediaSystem = $Xml.Configuration.SelectNodes("Token[@name='System']/Token[@name='Media']") | ConvertFrom-AbrRibbonIeNode

    $MediaPortRange = ''
    if ($MediaSystem -and $MediaSystem.RTPRTCP_PortStart -and $MediaSystem.RTPRTCP_PortCount) {
        $Start = [Int]$MediaSystem.RTPRTCP_PortStart
        $Count = [Int]$MediaSystem.RTPRTCP_PortCount
        if ($Count -gt 0) {
            $MediaPortRange = '{0}-{1}' -f $Start, ($Start + $Count - 1)
        }
    }

    $MediaInterface = @(
        $SignalingGroup |
            Where-Object { -not [String]::IsNullOrWhiteSpace($_.MediaInterface) } |
            ForEach-Object { $_.MediaInterface }
    ) | Select-Object -Unique

    $MediaSource = if ($MediaInterface) { $MediaInterface -join ', ' } else { $SbcAddress }

    if ($MediaPortRange) {
        & $AddFlow 'RTP and RTCP media' 'Inbound' $RemoteMedia $RemoteMedia $MediaSource $MediaPortRange 'UDP' 'The far end chooses its own media ports, so its range has to come from the provider.'
        & $AddFlow 'RTP and RTCP media' 'Outbound' $MediaSource $MediaPortRange $RemoteMedia $RemoteMedia 'UDP' 'Media is negotiated per call, so the full range must be open in both directions.'
    }

    # Provider ranges replace the placeholder for peers that publish them.
    $LocalMedia = if ($MediaPortRange) { $MediaPortRange } else { $Ephemeral }

    foreach ($Provider in $DetectedProvider) {
        $Note = 'Detected from a configured SIP peer. {0}. Confirm against current provider documentation before applying.' -f $Provider.Reference

        # Media to a provider leaves from the media interface of the signalling groups that
        # reach it. Only where none could be identified does this fall back to every media
        # interface on the appliance.
        $Entry = $ProviderInterface[$Provider.Name]
        $ProviderMedia = if ($Entry -and $Entry.Media.Count) { $Entry.Media -join ', ' } else { $MediaSource }

        if ($Provider.MediaPort) {
            & $AddFlow ('Media to {0}' -f $Provider.Name) 'Outbound' $ProviderMedia $LocalMedia $Provider.MediaNetwork $Provider.MediaPort $Provider.MediaProtocol $Note
            & $AddFlow ('Media from {0}' -f $Provider.Name) 'Inbound' $Provider.MediaNetwork $Provider.MediaPort $ProviderMedia $LocalMedia $Provider.MediaProtocol $Note
        }

        if ($Provider.RelayPort) {
            # Transport relay is UDP, so the appliance sources from its media port range.
            & $AddFlow ('Transport relay for {0}' -f $Provider.Name) 'Outbound' $ProviderMedia $LocalMedia $Provider.MediaNetwork $Provider.RelayPort $Provider.MediaProtocol $Note
        }
    }
    #endregion Media

    #region Address translation
    # A public address on a signalling group means the appliance sits behind a one to one
    # translation and advertises the public address in its SIP and SDP.
    $Nat = @(
        $SignalingGroup |
            Where-Object { -not [String]::IsNullOrWhiteSpace($_.NatPublicAddress) -and $_.NatPublicAddress -ne '0.0.0.0' } |
            ForEach-Object {
                [PSCustomObject]@{
                    Group         = $_.Description
                    PublicAddress = $_.NatPublicAddress
                    Interface     = $_.SignalingInterface
                }
            }
    )
    #endregion Address translation

    #region On box access control list
    $Protocol = @{ '1' = 'ICMP'; '6' = 'TCP'; '17' = 'UDP'; '58' = 'ICMPv6'; '132' = 'SCTP'; '256' = 'Any' }

    # Formats an address and mask pair the way the WebUI presents it. An all zero pair is the
    # wildcard, which reads far better as Any than as 0.0.0.0/0.0.0.0.
    $AddressText = {
        param([String] $Address, [String] $Mask)

        if ([String]::IsNullOrWhiteSpace($Address) -or $Address -eq '0.0.0.0' -or $Address -eq '::') {
            return $AnyHost
        }
        if ([String]::IsNullOrWhiteSpace($Mask) -or $Mask -eq '0.0.0.0' -or $Mask -eq '0') {
            return $Address
        }
        '{0}/{1}' -f $Address, $Mask
    }

    $PortText = {
        param([String] $Single, [String] $Minimum, [String] $Maximum)

        if ($Single -and $Single -ne '0') { return $Single }
        if ($Minimum -and $Minimum -ne '0' -and $Maximum -and $Maximum -ne '0') { return '{0}-{1}' -f $Minimum, $Maximum }
        $AnyHost
    }

    $AccessControl = foreach ($ListName in @('AccessCntrlList', 'IPv6AccessCntrlList')) {
        foreach ($Node in @($Xml.Configuration.SelectNodes("Token[@name='IPRouting']/Token[@name='$ListName']/ID"))) {

            $List = $Node | ConvertFrom-AbrRibbonIeNode
            $Order = @(ConvertFrom-AbrRibbonSequence -EncodedSequence $List.Sequence)
            $Rule = Get-AbrRibbonOrderedRow -Row @($Node.SelectNodes('ID') | ConvertFrom-AbrRibbonIeNode) -Order $Order

            [PSCustomObject]@{
                ID          = $List.ID
                Family      = if ($ListName -eq 'IPv6AccessCntrlList') { 'IPv6' } else { 'IPv4' }
                Description = $List.Description
                State       = if ($List.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                Rule        = @(
                    foreach ($Row in $Rule) {
                        [PSCustomObject]@{
                            ID          = $Row.ID
                            Description = $Row.Description
                            State       = if ($Row.Enabled -eq '1') { 'Enabled' } else { 'Disabled' }
                            Action      = switch ($Row.aclAction) { '0' { 'Allow' } '1' { 'Deny' } default { $Row.aclAction } }
                            Protocol    = if ($Protocol.ContainsKey([String]$Row.aclProtocol)) { $Protocol[[String]$Row.aclProtocol] } else { $Row.aclProtocol }
                            Source      = & $AddressText $Row.srcIPAddr $Row.srcIPAddrMask
                            SourcePort  = & $PortText $Row.aclSrcPort $Row.aclMinSrcPort $Row.aclMaxSrcPort
                            Destination = & $AddressText $Row.destIPAddr $Row.destIPAddrMask
                            DestPort    = & $PortText $Row.aclDstPort $Row.aclMinDstPort $Row.aclMaxDstPort
                            Interface   = if ([String]::IsNullOrWhiteSpace($Row.ifName)) { 'All' } else { $Row.ifName }
                            Precedence  = $Row.aclPrecedence
                        }
                    }
                )
            }
        }
    }
    #endregion On box access control list

    [PSCustomObject]@{
        Flow           = @($Flow)
        AccessControl  = @($AccessControl)
        KnownPeer      = @($DetectedProvider)
        Nat            = @($Nat)
        MediaPortRange = $MediaPortRange
        SbcAddress     = $SbcAddress
        ManagementAddress = $ManagementText
    }
}
