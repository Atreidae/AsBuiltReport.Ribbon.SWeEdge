# Ribbon SBC `symphonyconfig.xml` data model

Derived from Greig Sheridan's `Convert-RibbonSbcConfigToWord.ps1` and verified against the
sample exports in `Dev/Samples`. This is the reference for the bottom-up resolver.

## Document shape

Everything hangs off `/Configuration/Token[@name='<Group>']`. Groups nest further `Token`
elements, and the leaf rows are `ID` elements carrying an `IE` child:

```xml
<Configuration SystemRelease="13.0.0v37" PlatformType="SBC2000">
  <Token name="SignalingGroups">
    <Token name="SIP">
      <ID value="1">
        <IE classname="SIP_CFG_SG_COMMON_IE">
          <Description>Telstra Enterprise SIP Production</Description>
          <MediaConfigID>2</MediaConfigID>
          <RouteTableID>2</RouteTableID>
        </IE>
      </ID>
    </Token>
  </Token>
</Configuration>
```

Rule: the row key is `ID/@value`, the row data is every child element of `IE`, and the row
type is `IE/@classname`.

**A row with no `classname` is a deleted/empty slot and must be skipped.**

## Top-level Token groups

| Token | Key IE classnames | Contains |
| --- | --- | --- |
| `NodeHardware` | `NETSERV_INTERFACE_CFG_IE`, `NETSERV_VLAN_CFG_IE`, `NETSERV_MSTP_INSTANCE_CFG_IE` | Ports, interfaces, VLANs, bridge |
| `System` | `SYSTEM_SERV_NET_CFG_IE`, `CERTIFICATE_FILE_DATA_CFG_IE` | Host/network settings, certificates |
| `IPRouting` | `ACCESS_CONTROL_LIST_IE`, `CONFIG_DESCRIPTION_IE` | Static routes, ACLs |
| `Logging` | `LOGGER_SYSLOG_DEST` | Syslog destinations |
| `IPSec` | `NETSERV_IPSEC_CONNECTION_OBJ_CFG_IE` | IPSec tunnels |
| `SignalingGroups` | `SIP_CFG_SG_COMMON_IE`, `ISDN_SG_PROFILE_CONFIG_ENTRY_IE`, `CAS_SG_CFG_IE` | Signaling groups by type |
| `CallRouting` | `CR_ROUTE_TABLE_LIST_CONFIG`, `CR_ROUTE_TABLE_CONFIG` | Route tables and route entries |
| `Transformation` | `CR_TRANSFORMATION_TABLE_LIST_CONFIG` | Transformation tables and rules |
| `Translation` | `CR_TRANSLATION_TABLE_LIST_CONFIG` | Legacy translation tables (pre v6.0) |
| `ActionSets` | `CR_ACTION_SET_TABLE_LIST_CONFIG` | Action sets |
| `TimeOfDay` | `TIME_OF_DAY_TABLE` | Time of day tables |
| `ToneTables` | `CONFIG_DESCRIPTION_IE` | Tone tables |
| `Media` | `MEDIALIST_PROFILE_IE`, `VOICE_CODEC_PROFILE_IE`, `FAX_CODEC_PROFILE_IE`, `CRYPTO_PROFILE_IE`, `MSC_CFG_DTLS_PROFILE_IE` | Media lists, codecs, SDES/DTLS crypto |
| `SIP` | `SIP_CFG_PROFILE_IE`, `SIP_CFG_SERVER_TABLE_LIST_IE`, `SIP_CFG_REGISTRAR_IE`, `SIP_CFG_USER_CREDENTIALS_LIST_IE`, `SPR_MESSAGE_TABLE_IE` | SIP profiles, server tables, registrars, credentials, message rules |
| `TelephonyMappingTables` | `CC_REROUTE_CFG_IE`, `MESSAGE_PI_TRANSLATION_TABLE_IE`, `CONFIG_DESCRIPTION_IE` | Reroute, message translation, SIP<->Q.850 |
| `Security` | TLS profile IEs | TLS profiles, ciphers |
| `ListenProtocolPortList` | `LISTEN_PROTOCOL_PORT_LIST_IE` | SIP listen ports |
| `EmergencyServices` | `ESConfig`, `ESCallback` sub-tokens | Emergency config, callback pools, notification |
| `CAS` | `CAS_ENM_CFG_IE`, `CAS_RTWO_CFG_IE`, `CAS_LOOPSTART_FXS_CFG_IE`, `CAS_LOOPSTART_FXO_CFG_IE`, `CAS_SUPPLEMENTARY_CFG_IE` | CAS signaling profiles |
| `SBA` | `CAC_PROFILE_CONFIG` | CAC profiles |
| `RAD` | `RAD_RADIUS_SERVERS` | RADIUS servers |
| `DHCP` | `NETSERV_DHCP_OBJ_CFG_IE` | DHCP pools and static clients |
| `Users` | `UAS_USER_GROUP` | User groups |

## Reference graph

Every cross-reference is a plain numeric ID pointing at another row's `ID/@value`.
**There is no fuzzy or name-based matching anywhere in this format.**

### SIP signaling group (`SIP_CFG_SG_COMMON_IE`)

| Field | Points to |
| --- | --- |
| `MediaConfigID` | Media list profile |
| `RouteTableID` | Call route table |
| `ProfileID` | SIP profile |
| `ServerClusterID` | SIP server table |
| `RegistrarID` | SIP registrar |
| `ProxyAuthorizationTableID` | SIP authorization table |
| `ActionSetTableID` | Action set |
| `CryptoProfileID` | SDES crypto profile |
| `ToneTableID` | Tone table |
| `SIPtoQ850_TableID` | SIP to Q.850 table |
| `Q850toSIP_TableID` | Q.850 to SIP table |
| `InboundNATQualifiedPrefixesTableID` | SIP NAT prefix table |
| `SipRecorder` | Another signaling group |

### ISDN signaling group (`ISDN_SG_PROFILE_CONFIG_ENTRY_IE`)

| Field | Points to |
| --- | --- |
| `RouteTableNumber` | Call route table |
| `ActionsetTableNumber` | Action set |
| `ToneTableNumber` | Tone table |
| `ApplyToPortName` | Physical port, e.g. `1.1` |

ISDN field names differ from SIP: `...Number` rather than `...ID`, and `Actionset` has a
lower-case `s`. Other ISDN fields carry an `IsdnSg` prefix, for example
`IsdnSgSwitchVariant` and `IsdnSgSideOrientation`, not `SwitchVariant`/`SideOrientation`.

ISDN groups have no media list. They carry no `MediaConfigID` at all, so the correct
rendering is "none", never an inferred one.

### CAS signaling group (`CAS_SG_CFG_IE`)

| Field | Points to |
| --- | --- |
| `RouteTableId` | Call route table |
| `ActionSetTableId` | Action set |
| `ToneTableId` | Tone table |
| `CasLoopStartFxsProfileId` / `CasLoopStartFxoProfileId` / `CasEnMProfileId` / `CasR2ProfileId` | CAS signaling profile |
| `CasSupplementaryProfileId` | CAS supplementary profile |

Note the casing. CAS uses `RouteTableId` where SIP uses `RouteTableID`. PowerShell property
and hashtable lookups are case insensitive, so this is survivable, but any case sensitive
lookup (XPath, for instance) must use the exact spelling.

### Signaling group identifier ranges

Observed across the sample set:

| Range | Meaning |
| --- | --- |
| 1 upward | SIP |
| 10001 upward | ISDN, one per physical port |
| 20001 upward | CAS |
| 50000 upward | SIPREC recorder |

### Route entry (`CR_ROUTE_TABLE_CONFIG`)

| Field | Points to |
| --- | --- |
| `SignalingGroupList` | Signaling groups (base64 sequence) |
| `TransformationTable` | Transformation table |
| `TranslationTable` | Legacy translation table |
| `MessageTranslationTable` | Message translation table |
| `ReRouteTable` | Reroute table |
| `TimeOfDay` | Time of day table |
| `MediaSelection` | Media list profile — **overrides the signaling group's `MediaConfigID`** |

### Media list profile (`MEDIALIST_PROFILE_IE`)

| Field | Points to |
| --- | --- |
| `VoiceFaxProfileID` | Voice/fax codec profiles (base64 sequence, ordered by preference) |
| `CryptoProfileID` | SDES crypto profile |
| `DtlsProfileID` | DTLS crypto profile |

### SIP server entry

| Field | Points to |
| --- | --- |
| `TLSProfileID` | TLS profile |
| `RemoteAuthorizationTableID` | SIP credentials table |
| `ContactRegistrantTableID` | SIP registration table |

### Action set entry (`CR_ACTION_SET_TABLE_LIST_CONFIG`)

`ActionParameter1` is context sensitive, keyed off `Action`:

| `Action` | `ActionParameter1` means |
| --- | --- |
| 0 (Route Call) | Call route table ID |
| 3 (Release Call) | Q.850 cause code |
| 6 (Generic Timer) | Milliseconds |
| 7 (Invoke Action Set) | Action set ID |

## Base64 sequence fields

Decoded little-endian; `ByteCount` 2 reads Int16 pairs, `ByteCount` 1 reads raw bytes.
Zero values are padding and are skipped.

| Field | ByteCount | Meaning |
| --- | --- | --- |
| `<route table>.Sequence` | 2 | Route entry execution order |
| `<route entry>.SignalingGroupList` | 2 | Destination signaling groups, in order |
| `<transformation table>.Sequence` | 2 | Rule execution order |
| `<translation table>.Sequence` | 2 | Legacy rule execution order |
| `<media list>.VoiceFaxProfileID` | 2 | Codec profiles in preference order |
| `<action set>.Sequence` | 2 | Action execution order |
| `<sip server table>.Sequence` | 2 | Server failover order |
| `<access list>.Sequence` | 2 | ACL evaluation order |
| `<message translation table>.Sequence` | 1 | Entry order |
| `<reroute table>.CauseCodes` | 1 | Q.850 cause code list |

TLS cipher order is the exception: `ClientCipherSequence` / `ServerCipherSequence` are
comma-delimited strings, not base64.

## Ordering

Rows are stored in creation order, not display order. To render correctly:

1. Read the parent's `Sequence` field.
2. Decode it to an ordered array of child row IDs.
3. Emit children in that order; anything not named in the sequence goes last.

This applies to route entries, transformation rules, action set entries, SIP servers,
message translation entries and ACL entries.

## Enumerations

Only the ones needed early. The full set is in Greig's script around lines 400-560.

`Enabled`: `0` Disabled, `1` Enabled, `2` Drain (signaling groups only). This applies to the
row level `Enabled` field everywhere, **including media list profiles**.

### Media list feature flags

Verified against the WebUI on a 13.1.0 SWe Lite, 2026-07-30. Polarity is **per field**, not a
blanket rule for the profile, so each one has to be handled individually.

| Config field | WebUI label | Polarity |
| --- | --- | --- |
| `DeadCallDetection` | Dead Call Detection | Reversed: `0` Enabled, `1` Disabled |
| `SilenceSuppression` | Silence Suppression | Reversed |
| `EnforceCodecPriority` | Enforce SG Codec Priority | Reversed |
| `ModemRelay` | Modem Passthrough | Reversed |
| `FaxRelay` | Fax Passthrough | Reversed |
| `ChangeSSRCValue` | Change SSRC | Normal: `0` Disable, `1` Enable |
| `FAXToneDetection` | Fax Tone Detection | Normal |

`EnforceCodecPriority` is not in Greig's reversed list but behaves the same way.

`CNGToneDetection` is listed as reversed by Greig. Evidence from the sample set suggests he is
wrong and it is actually normal polarity:

- Its value distribution is identical to `FAXToneDetection`, which is confirmed normal.
- In both fields the value `1` sits almost exclusively on lists named "Default Media List",
  so the split reflects factory default versus user edited rather than anything semantic.

An earlier reading of this project inferred reversed polarity because a list named "Fax Media
List" held `0`. That inference did not account for the default versus edited confound and
should not be relied on.

The field is present and varying from 6.1.2 through 13.1.0, so it was never merged or
removed. Newer platforms without analog ports simply do not expose it in the WebUI.

Until it can be confirmed against a WebUI that exposes it, most likely an SBC 1000 or 2000
with analog ports, this field is excluded from the report.

CNG is the calling tone sent by the transmitting fax. CED, the answer tone from the receiving
side, is the other half of the pair.

Note the WebUI uses "Disable"/"Enable" for Change SSRC and "Disabled"/"Enabled" elsewhere.

Other media list values:

| Field | Meaning |
| --- | --- |
| `MediaRTCPMode` | `0` RTCP |
| `DigitRelayType` | `1` RFC 2833/RFC 4733 |
| `DSCP`, `DigitRelayPayloadType` | Literal values, no translation |

`DestinationType`: `0` Standard, `1` Registrar Table, `2` Deny, `3` Trunk Group.

`Protocol`: `1` UDP, `2` TCP, `4` TLS.

`CallPriority`: `0` Non-Urgent, `1` Standard, `2` Urgent, `3` Emergency.

`CRMediaMode`: `0` DSP, `1` Proxy, `2` Proxy preferred over DSP, `3` DSP preferred over
Proxy, `4` Disabled, `5` Direct.

`MatchType`: `0` Mandatory, `1` Optional.

`ServerSelection`: `0` Round Robin, `1` Priority: Register All, `2` First,
`4` Priority: Register Active Only.

`InteropMode`: `0` Standard, `1` Broadsoft Extension, `2` Office 365,
`3` Office 365 w/AD PBX, `4` Header Transparency.

`SwitchVariant`: `0` ATT 4ESS, `1` ATT 5ESS, `2` DMS 100, `3` NI2, `4` Euro ISDN,
`5` QSIG, `6` Japanese ISDN.

Transformation `InputField` / `OutputField` share one large enum (0 Called Address through
42 SIP domain fields); see Greig's script for the full table.

## Gotchas

- Rows with a null `classname` are deleted slots. Skip them.
- Field name casing is not consistent between signaling group types. Rely on case insensitive
  lookups, or normalise on import.
- Singleton settings groups such as `System/SystemNet`, `System/Media` and `System/QOE` put
  their `IE` directly under the token with no `ID` wrapper.
- `0.0.0.0` is the "not configured" sentinel for server address fields. Rendering it verbatim
  makes an unset secondary DNS or NTP server look configured.
- PowerShell's XML adapter shadows `.Name` with a `name` attribute. On `<Token name="X">`,
  `$node.Name` returns `X`, not `Token`. Use `.LocalName`.
- Media list feature flags such as `DeadCallDetection` are reportedly reversed. Unverified,
  see the enumerations section.
- `DestinationType` 2 (Deny) means the signaling group columns are meaningless; 3 (Trunk
  Group) should render as N/A.
- Old configs populate `TranslationTable`; v6.0+ populate `TransformationTable`. Greig
  treats `TranslationTable -eq '0'` as "use Transformation".
- Signaling group IDs at or above 50000 are SIPREC recorders, not normal trunks.
- Certificate `FileType`: `1` user-provided, `4` Ribbon default, `5` supplementary
  (supplementary IDs are offset by 1000).
- DHCP lease `2147483647` means infinite.
- Some fields are platform or release specific and may be absent or literally
  `<n/a this rls>`.
