# :arrows_clockwise: Ribbon SWeEdge As Built Report Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - Unreleased

### Added

- Trunk Topology diagram: the appliance, its logical interfaces, signalling groups and their
  far ends. Line style carries transport (TLS solid, TCP dashed, UDP dotted) and drained or
  disabled groups are visibly different. Recognised providers such as Microsoft Teams Direct
  Routing are shown by name. Large configurations are split per interface.
  Controlled by the `ShowTopologyDiagram` report option, which defaults to disabled.
  Requires the optional `AsBuiltReport.Diagram` module (1.0.12 or later); Graphviz is not
  needed. The diagram engine only supports PowerShell 7 or later, so when
    `ShowTopologyDiagram` is enabled in Windows PowerShell 5.1 the report stops immediately and
    suggests re-running with `pwsh`. If the module is missing the diagram is skipped with a warning.
- `-ShowTopologyDiagram` switch on the `Dev\New-AbrRibbonTestReport.ps1` harness.

### Changed

- Passing an offline export file through `Target` is deprecated and now logs a warning. Use
  the native `-InputFile` parameter of `New-AsBuiltReport` (AsBuiltReport.Core 1.7.0 or later).
  `Target` still works for file paths and host names, so nothing breaks.
- Provider detection was moved into shared helpers (`Find-AbrRibbonProvider`) and is reused by
  the Firewall Requirements section. Behaviour is unchanged.

## [0.2.0] - 2026-09-30

### Added

- Firewall Requirements section, placed immediately after System. It derives the network
  flows the appliance needs from its own configuration rather than from a generic vendor
  requirements list, covering management, DNS, NTP, syslog, SNMP, LDAP, SIP signalling and
  media. Controlled by the `ShowFirewallTable` report option, which defaults to enabled.
- Well known provider detection in the Firewall Requirements section. Where a SIP peer
  matches a published provider endpoint, that provider's documented media and transport relay
  ranges are included in place of the unknown peer placeholder. Microsoft Teams Direct
  Routing is recognised. Matching is by exact host name or exact domain suffix, so a host that
  merely resembles a provider endpoint is not claimed to be one.
- The appliance's own access control list is reported alongside the derived flows, because a
  flow permitted upstream still fails if the appliance denies it.
- Message translation rules, SIP to Q.850 and Q.850 to SIP mappings, and tone profiles are now
  reported in full. Previously only the table names were listed.
- Support for the `InputFile` parameter set introduced in AsBuiltReport.Core 1.7.0, so a
  report can be generated from one or more offline configuration exports without supplying
  them as targets. `Target` remains supported and, in `InputFile` mode, acts as an optional
  display name override mapped 1:1 onto each file. Core 1.6.x is still supported; `InputFile`
  simply requires the newer Core to reach this module.
- The verbose logging health check now covers syslog destinations as well as subsystem log
  levels, since a destination left at Trace or Debug has the same effect.
- Five health checks that the default report configuration offered but that were never
  implemented now work. `System.NtpEnabled` flags an appliance with no time source, because
  certificate validity is judged against the appliance clock and drift presents as TLS
  failures that look like certificate faults. `SignalingGroup.DisabledGroup` and
  `CallRouting.DisabledRoute` flag objects that are switched off, which is the usual
  explanation for a trunk or route that appears configured and carries no calls.
  `SignalingGroup.UnresolvedReference` and `CallRouting.UnresolvedReference` flag a reference
  to an object that is not present in the configuration, which happens when an object is
  deleted and the reference to it is left behind.
- A roadmap, covering topology diagrams built on the AsBuiltReport diagram framework, SIP
  message manipulation reporting, and the remaining configuration coverage gaps.

### Changed

- Management, syslog and SNMP flows are attributed to the management interface only, rather
  than to every configured address. That is `mgt0` on SWe Lite and the first Ethernet port on
  the 1000 and 2000.
- Certificates at or past expiry now have their entire row highlighted rather than just the
  remaining days cell, which was easy to miss in a long table.
- The Security section states that remaining certificate validity is counted from the report
  generation date and will be out of date if the report is read later.
- Section descriptions expanded across every section to explain what the configuration
  actually does, rather than restating the section title.
- Fields that carry no useful information in practice, such as enabled flags on objects the
  WebUI offers no way to disable, moved to InfoLevel 5. Fields that vary meaningfully, such as
  the enabled state of individual route entries and transformation rules, are retained at
  every level.
- IPv6 interface addressing is only shown when at least one interface actually has an
  address, rather than rendering an empty column on every appliance.
- Explanations of highlighted rows are now only printed when a row is actually highlighted.
  A report with no drained signalling group, no expiring certificate and no verbose logging
  no longer carries paragraphs describing conditions it does not contain.

### Fixed

- Firewall source ports for UDP were reported as ephemeral. SIP over UDP is symmetric, so the
  appliance sends from the port it listens on. Outbound UDP flows now show that listen port,
  and inbound UDP flows show that the far end sources from its own signalling port rather
  than an ephemeral one. TCP and TLS are unchanged.
- Firewall flows were sourced from every appliance address, which asked the network team to
  permit private interfaces to public providers. Outbound SIP is now attributed to the
  signalling interface of the group that carries it, and provider media and transport relay
  flows to that group's media interface.
- DNS, NTP and Active Directory flows were sourced from every appliance address. They use the
  management interface, the same as syslog and SNMP.
- The Teams transport relay flow reported an ephemeral source port instead of the appliance
  media port range.
- `Sort-AbrRibbonRow` renamed to `Get-AbrRibbonOrderedRow`, because `Sort` is not an approved
  PowerShell verb.

## [0.1.0] - 2026-07-30

### Added

- Configuration importer supporting `.tar`, `.tgz`, `.tar.gz` and raw `symphonyconfig.xml`
  exports, validated against SWe Lite, SBC 1000 and SBC 2000 releases from 6.1.2 to 13.1.0.
- Report sections for System, Networking, Security, Media, SIP, Physical Telephony Ports,
  Signaling Groups, Call Routing, Telephony Mapping, Emergency Services, and Logging and
  Monitoring.
- Physical Telephony Ports renders only on appliances fitted with line cards, so virtual
  appliances do not show an empty section.
- Health check highlighting certificates that have expired or are close to expiry, with a
  configurable warning threshold.
- Health check highlighting a SIP server configured with a different TLS profile to the rest
  of its server table, which is easily missed on a low priority failover target.
- Health check highlighting subsystems left at Trace or Debug log level.
- English (US) localisation covering every section.
- Pester coverage for the configuration importer, the shared helpers and the section
  resolvers, using synthetic fixtures so no customer configuration is required.

### Changed

- Route entries, transformation rules and SIP servers are presented in the order the SBC
  evaluates them, decoded from the parent table's `Sequence` field, rather than in identifier
  order. These differ in most real configurations.
- Transformation rules show whether each rule is Mandatory or Optional, because a table only
  succeeds when every enabled Mandatory rule matches.
- Deny and Trunk Group routes no longer display a destination signaling group, which does not
  apply to them.
- Interface names on SBC 1000 and 2000 appliances are derived from the VLAN description held
  in the configuration, rather than from a hardcoded table of VLAN tags.

### Fixed

- Media lists are resolved to signaling groups by identifier. A previous approach inferred the
  relationship by comparing names, which produced confident but incorrect results, and invented
  a media list for ISDN and CAS groups that legitimately have none.
- Signaling group fields are read using each type's own field names. ISDN uses
  `RouteTableNumber` and `ActionsetTableNumber` where SIP and CAS use `RouteTableID` and
  `ActionSetTableID`, so tone tables and action sets previously resolved as unset on ISDN.
- Federated IP and callback number lists containing a single entry are no longer split into
  individual characters.
- `0.0.0.0` is presented as not configured rather than as an address, matching how Ribbon uses
  it as a sentinel for unset DNS servers, NTP servers, interface addresses and subnet masks.
- Media list feature flags use the correct polarity per field, verified against the WebUI.
  Several read `0` for enabled while others in the same record do not.

### Removed

- Certificate content, private keys, passwords, shared secrets and SNMP community strings are
  discarded when the configuration is parsed, so they cannot reach the report.
