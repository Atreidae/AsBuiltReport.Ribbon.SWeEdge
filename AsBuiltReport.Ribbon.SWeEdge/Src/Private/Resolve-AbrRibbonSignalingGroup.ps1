function Resolve-AbrRibbonSignalingGroup {
    <#
    .SYNOPSIS
        Resolves Ribbon signaling groups and the objects they reference.
    .DESCRIPTION
        Signaling groups sit at the top of the Ribbon object graph. They reference route
        tables, media lists, SIP profiles, SIP server tables and network interfaces, all by
        numeric identifier.

        Every reference is resolved by exact identifier. Where a reference is absent the
        result is reported as not configured, never inferred from names. ISDN and CAS groups
        legitimately have no media list, and SIP groups set to automatic interface selection
        legitimately have no interface.
    .PARAMETER Config
        The normalised configuration object from Import-AbrRibbonSWeEdgeConfig.
    .OUTPUTS
        System.Management.Automation.PSCustomObject
    .NOTES
        Version:    0.1.0
        Author:     James Arber
    .LINK
        https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge
    .EXAMPLE
        PS C:\> Resolve-AbrRibbonSignalingGroup -Config $Config
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [PSObject] $Config
    )

    $Xml = $Config.RawXml

    #region Lookups, built bottom up
    $MediaLookup = @{}
    foreach ($List in (Resolve-AbrRibbonMediaProfile -Config $Config).MediaList) {
        $MediaLookup[[String]$List.ID] = [String]$List.Description
    }

    $RouteLookup = @{}
    foreach ($Table in $Config.RoutingTables) {
        $RouteLookup[[String]$Table.ID] = [String]$Table.Description
    }

    $InterfaceLookup = Resolve-AbrRibbonNetworkInterface -Config $Config -AsLookup

    $ProfileLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='SIP']/Token[@name='Profile']/ID") | ConvertFrom-AbrRibbonIeNode)
    $ServerLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='SIP']/Token[@name='SIPServers']/ID") | ConvertFrom-AbrRibbonIeNode)
    $ToneLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='ToneTables']/ID") | ConvertFrom-AbrRibbonIeNode)
    $ActionLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='ActionSets']/ID") | ConvertFrom-AbrRibbonIeNode)

    # SIP message manipulation rules, applied per signaling group on ingress and egress. The
    # report already lists these tables; resolving the reference is what says which group uses
    # one, which is the part a reader actually needs.
    $SprLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='SIP']/Token[@name='SIPSPRMessageRules']/ID") | ConvertFrom-AbrRibbonIeNode)
    $SipToQ850Lookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='TelephonyMappingTables']/Token[@name='SipToQ850']/ID") | ConvertFrom-AbrRibbonIeNode)
    $Q850ToSipLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='TelephonyMappingTables']/Token[@name='Q850ToSip']/ID") | ConvertFrom-AbrRibbonIeNode)
    $TlsLookup = Get-AbrRibbonIdLookup -Row @($Xml.Configuration.SelectNodes("Token[@name='Security']/Token[@name='TLSProfile']/ID") | ConvertFrom-AbrRibbonIeNode)

    # Confirmed from the WebUI page markup rather than inferred. The values are not contiguous:
    # there is no 3, so a sequential guess would have mislabelled the last two.
    $ServerSelectionName = @{
        '0' = 'Round Robin'
        '1' = 'Priority: Register All'
        '2' = 'First'
        '4' = 'Priority: Register Active Only'
    }

    $NatTraversalName = @{ '0' = 'None'; '1' = 'Static NAT' }

    # ISDN settings, confirmed from the Create ISDN Signaling Group page markup. These use an
    # IsdnSg prefix and are separate fields from their SIP equivalents: channel hunting is
    # IsdnSgHuntMethod here, while the HuntMethod on a SIP group has no WebUI control and is
    # therefore not reported.
    $IsdnHuntName = @{
        '0' = 'Standard'
        '1' = 'Reverse Standard'
        '2' = 'Round Robin'
        '3' = 'Least Idle'
        '4' = 'Most Idle'
    }

    $IsdnChannelName = @{ '0' = 'Preferred'; '1' = 'Exclusive' }
    $IsdnOrientationName = @{ '0' = 'User'; '1' = 'Network' }

    $IsdnVariantName = @{
        '0' = 'ATT 4ESS'
        '1' = 'ATT 5ESS'
        '2' = 'DMS 100'
        '3' = 'NI2'
        '4' = 'Euro ISDN'
        '5' = 'QSIG'
        '6' = 'Japanese ISDN'
    }

    $FromMap = {
        param([Hashtable] $Map, [String] $Value)

        if ([String]::IsNullOrWhiteSpace($Value)) { '' }
        elseif ($Map.ContainsKey($Value)) { $Map[$Value] }
        else { $Value }
    }

    $Flag = {
        param([String] $Value)
        if ($Value -eq '1') { 'Enabled' } else { 'Disabled' }
    }

    # A reference field can hold several identifiers separated by commas.
    $ResolveList = {
        param([String] $Value, [Hashtable] $Lookup)

        if ([String]::IsNullOrWhiteSpace($Value) -or $Value -eq '0') {
            return '--None--'
        }

        $Names = foreach ($Id in @(($Value -split ',') | ForEach-Object { $_.Trim() })) {
            if ($Id -and $Id -ne '0') {
                Resolve-AbrRibbonReference -Id $Id -Lookup $Lookup
            }
        }

        if ($Names) { ($Names -join ', ') } else { '--None--' }
    }
    #endregion Lookups

    $ProtocolName = @{ '1' = 'UDP'; '2' = 'TCP'; '4' = 'TLS' }

    foreach ($Type in 'SIP', 'ISDN', 'CAS') {
        foreach ($Group in @($Config.SignalingGroups.$Type)) {

            #region Listen ports
            # Ports are held in six fixed slots rather than a repeating element.
            $ListenPort = for ($Slot = 1; $Slot -le 6; $Slot++) {
                $Port = $Group."ListenPort_$Slot"
                if ([String]::IsNullOrWhiteSpace($Port) -or $Port -eq '0') {
                    continue
                }

                $Protocol = [String]$Group."Protocol_$Slot"

                # Each slot carries its own TLS profile, so a group can listen on plain and
                # secure transports at once with different profiles.
                $SlotTlsProfile = [String]$Group."TLSProfileID_$Slot"

                [PSCustomObject]@{
                    Port       = $Port
                    Protocol   = if ($ProtocolName.ContainsKey($Protocol)) { $ProtocolName[$Protocol] } else { "Unknown ($Protocol)" }
                    TlsProfile = if ($SlotTlsProfile -and $SlotTlsProfile -ne '0') {
                        Resolve-AbrRibbonReference -Id $SlotTlsProfile -Lookup $TlsLookup
                    } else {
                        ''
                    }
                }
            }
            #endregion Listen ports

            #region Federated hosts
            # Newer releases use the comma separated pair, older ones use six numbered slots.
            $FederatedHost = if (-not [String]::IsNullOrWhiteSpace($Group.RemoteHosts)) {
                # The @() wrappers matter. Calling .Trim() on a one element array collapses it
                # to a scalar string through member enumeration, and indexing that returns
                # single characters rather than values.
                $Hosts = @(($Group.RemoteHosts -split ',') | ForEach-Object { $_.Trim() })
                $Masks = @(($Group.RemoteMasks -split ',') | ForEach-Object { $_.Trim() })

                for ($Index = 0; $Index -lt $Hosts.Count; $Index++) {
                    if ([String]::IsNullOrWhiteSpace($Hosts[$Index])) {
                        continue
                    }

                    if ($Index -lt $Masks.Count -and -not [String]::IsNullOrWhiteSpace($Masks[$Index])) {
                        '{0} / {1}' -f $Hosts[$Index], $Masks[$Index]
                    } else {
                        $Hosts[$Index]
                    }
                }
            } else {
                for ($Slot = 1; $Slot -le 6; $Slot++) {
                    $RemoteHost = $Group."RemoteHost$Slot"
                    if ([String]::IsNullOrWhiteSpace($RemoteHost)) {
                        continue
                    }

                    $Mask = $Group."RemoteMask$Slot"
                    if ([String]::IsNullOrWhiteSpace($Mask)) {
                        $RemoteHost
                    } else {
                        '{0} / {1}' -f $RemoteHost, $Mask
                    }
                }
            }
            #endregion Federated hosts

            #region Interfaces
            # The WebUI interface dropdown carries an empty option labelled Auto, so an empty
            # interface name is a deliberate "let the SBC choose" rather than missing data.
            # Type 1 pins a named interface, but the name is authoritative: configurations
            # exist with type 1 and no name, and the WebUI shows those as Auto.
            $ResolveInterface = {
                param([String] $Type, [String] $Key)

                if ($Type -ne '1' -or [String]::IsNullOrWhiteSpace($Key)) {
                    'Auto'
                } elseif ($InterfaceLookup.ContainsKey($Key)) {
                    '{0} ({1})' -f $InterfaceLookup[$Key].DisplayName, $InterfaceLookup[$Key].IPv4Primary
                } else {
                    # Same marker prefix as Resolve-AbrRibbonReference, so the health check
                    # in Test-AbrRibbonUnresolvedReference catches this case too.
                    "Unresolved ($Key)"
                }
            }

            $SignalingInterface = & $ResolveInterface ([String]$Group.SignalingSourceIPType) ([String]$Group.NetInterfaceSignaling)
            $MediaInterface = & $ResolveInterface ([String]$Group.MediaSourceIPType) ([String]$Group.NetInterfaceMedia)
            #endregion Interfaces

            #region Field name variance
            # ISDN names these fields ...Number where SIP and CAS use ...ID, and spells
            # Actionset with a lower case s. Case insensitive property access does not help
            # when the name itself differs, so both spellings are read.
            $ToneTableId = $Group.ToneTableID
            if ([String]::IsNullOrWhiteSpace($ToneTableId)) {
                $ToneTableId = $Group.ToneTableNumber
            }

            $ActionSetId = $Group.ActionSetTableID
            if ([String]::IsNullOrWhiteSpace($ActionSetId)) {
                $ActionSetId = $Group.ActionsetTableNumber
            }
            #endregion Field name variance

            $Resolved = [PSCustomObject]@{
                ID                 = $Group.ID
                Type               = $Type
                Description        = $Group.Description

                # customAdminState is the field the WebUI writes, and it is the only one that
                # ever carries Drain. Enabled looks like it should hold the same value and does
                # not: in the sample set Enabled is 1 for a group whose customAdminState is 2,
                # so reading Enabled reports a drained group as healthy. Older releases that
                # predate the field fall back to Enabled.
                State              = switch ([String]$(if ($null -ne $Group.customAdminState -and $Group.customAdminState -ne '') { $Group.customAdminState } else { $Group.Enabled })) {
                    '0' { 'Disabled' }
                    '1' { 'Enabled' }
                    '2' { 'Drain' }
                    default { 'Unknown' }
                }
                IsRecorder         = $Group.IsRecorder
                Port               = $Group.ApplyToPortName
                RouteTableName     = Resolve-AbrRibbonReference -Id ([String]$Group.RouteTable) -Lookup $RouteLookup
                MediaListName      = Resolve-AbrRibbonReference -Id ([String]$Group.MediaConfigID) -Lookup $MediaLookup
                SipProfileName     = Resolve-AbrRibbonReference -Id ([String]$Group.ProfileID) -Lookup $ProfileLookup
                SipServerName      = Resolve-AbrRibbonReference -Id ([String]$Group.ServerClusterId) -Lookup $ServerLookup
                ToneTableName      = Resolve-AbrRibbonReference -Id ([String]$ToneTableId) -Lookup $ToneLookup
                ActionSetName      = Resolve-AbrRibbonReference -Id ([String]$ActionSetId) -Lookup $ActionLookup
                SignalingInterface = $SignalingInterface
                MediaInterface     = $MediaInterface
                ListenPort         = @($ListenPort)
                FederatedHost      = @($FederatedHost)
                Channels           = $Group.Channels
                # The SBC itself sits behind a NAT and advertises this address.
                NatPublicAddress   = $Group.NATPublicIPAddress
                # A separate feature covering remote peers that sit behind a NAT.
                InboundNatDetect   = $Group.InboundNATTraversalDetection
                # Only meaningful when media optimization is enabled, likely Teams local
                # media optimization. Inert otherwise, so it is reported conditionally.
                MediaOptimization  = $Group.MediaOptimization
                PrivateMediaSource = $Group.PrivateMediaSourceIp

                # The supported media modes are a set of independent switches in the WebUI, not
                # one setting, so they are reported as the list of modes that are actually on.
                # Reporting four separate Enabled/Disabled rows would be technically accurate
                # and much harder to read.
                AudioMode          = @(
                    if ($Group.RTPMode -eq '1') { 'DSP' }
                    if ($Group.RTPProxyMode -eq '1') { 'Proxy' }
                    if ($Group.RTPDirectMode -eq '1') { 'Direct' }
                    if ($Group.RTPProxySrtpMode -eq '1') { 'Proxy with local SRTP' }
                ) -join ', '

                VideoMode          = @(
                    if ($Group.VideoProxyMode -eq '1') { 'Proxy' }
                    if ($Group.VideoDirectMode -eq '1') { 'Direct' }
                ) -join ', '

                ServerSelection    = if ($ServerSelectionName.ContainsKey([String]$Group.ServerSelection)) {
                    $ServerSelectionName[[String]$Group.ServerSelection]
                } else {
                    $Group.ServerSelection
                }

                NatTraversal       = if ($NatTraversalName.ContainsKey([String]$Group.NATTraversalType)) {
                    $NatTraversalName[[String]$Group.NATTraversalType]
                } else {
                    $Group.NATTraversalType
                }

                OutboundProxy      = $Group.OutboundProxy
                OutboundProxyPort  = $Group.OutboundProxyPort

                IngressMessageRule = & $ResolveList ([String]$Group.IngressSPRMessageTableList) $SprLookup
                EgressMessageRule  = & $ResolveList ([String]$Group.EgressSPRMessageTableList) $SprLookup
                SipToQ850Table     = Resolve-AbrRibbonReference -Id ([String]$Group.SIPtoQ850_TableID) -Lookup $SipToQ850Lookup
                Q850ToSipTable     = Resolve-AbrRibbonReference -Id ([String]$Group.Q850toSIP_TableID) -Lookup $Q850ToSipLookup

                ChallengeRequest   = & $Flag $Group.ChallengeRequest
                Early183           = & $Flag $Group.Early183
                IceSupport         = & $Flag $Group.ICESupport
                RegisterKeepAlive  = & $Flag $Group.RegisterKeepAlive
                RtcpMultiplexing   = & $Flag $Group.RTCPMultiplexing
                QoeReporting       = & $Flag $Group.QoEReporting

                # Only populated on ISDN groups. Empty elsewhere, so the section can render
                # them without testing the group type.
                IsdnSwitchVariant  = & $FromMap $IsdnVariantName ([String]$Group.IsdnSgSwitchVariant)
                IsdnOrientation    = & $FromMap $IsdnOrientationName ([String]$Group.IsdnSgSideOrientation)
                IsdnHuntMethod     = & $FromMap $IsdnHuntName ([String]$Group.IsdnSgHuntMethod)
                IsdnIndicatedChan  = & $FromMap $IsdnChannelName ([String]$Group.IsdnSgIndicatedChannel)
            }

            # Evaluated here rather than in the section so that every reference is covered,
            # including the ones that are only rendered at higher detail levels. A group with
            # a broken reference the reader cannot see is exactly the case worth flagging.
            $Resolved | Add-Member -NotePropertyName 'HasUnresolvedReference' -NotePropertyValue (
                Test-AbrRibbonUnresolvedReference -Value @(
                    $Resolved.RouteTableName
                    $Resolved.MediaListName
                    $Resolved.SipProfileName
                    $Resolved.SipServerName
                    $Resolved.ToneTableName
                    $Resolved.ActionSetName
                    $Resolved.SignalingInterface
                    $Resolved.MediaInterface
                    $Resolved.IngressMessageRule
                    $Resolved.EgressMessageRule
                    $Resolved.SipToQ850Table
                    $Resolved.Q850ToSipTable
                    $Resolved.ListenPort.TlsProfile
                )
            ) -Force

            $Resolved
        }
    }
}
