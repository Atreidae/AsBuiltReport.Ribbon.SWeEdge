# :world_map: Roadmap

Planned and proposed work for the Ribbon SWeEdge As Built Report.

Nothing here is committed to a release. Items are recorded so the reasoning behind them is not
lost, and so a contributor picking one up starts from what has already been established rather
than rediscovering it. Anything already shipped lives in [CHANGELOG.md](CHANGELOG.md).

Status key:

| Status | Meaning |
|--------|---------|
| Proposed | Idea captured. Design not settled. |
| Designed | Approach agreed and written down below. Ready to be picked up. |
| Blocked | Waiting on something outside this repository. |

---

## Topology diagrams

**Status:** Partly delivered. Diagram 1 (trunk topology) shipped in 0.3.0 behind the
`ShowTopologyDiagram` option. Diagrams 2 and 3 remain Proposed.

Render the appliance and the SIP peers it talks to as a diagram, using the AsBuiltReport
diagram framework, and embed it in the report.

A signalling group table tells you a peer exists. It does not show you, at a glance, that three
groups share one interface, that the Teams trunk is the only one on TLS, or that a route table
points at a group that is drained. A diagram does.

### Which framework

Use **[AsBuiltReport.Diagram](https://github.com/AsBuiltReport/AsBuiltReport.Diagram)**.

> :warning: The older `Diagrammer.Core` module is **archived**. Its README redirects to
> `AsBuiltReport.Diagram`, which now lives under the AsBuiltReport organisation. The cmdlets
> were renamed in the move: `Add-DiaNodeIcon` became `Add-NodeIcon`, `Add-DiaHTMLNodeTable`
> became `Add-HtmlNodeTable`, and so on. Do not follow `Diagrammer.Core` examples verbatim.

Version 1.0.12 adds a ChartForgeX-backed topology API (`New-AbrTopologyDiagram`,
`Add-AbrTopologyNode`, `Add-AbrTopologyGroup`, `Add-AbrTopologyEdge`,
`Export-AbrTopologyDiagram`) that renders PNG, SVG or base64 **without Graphviz**. The trunk
topology uses it with the Manual layout and computed coordinates, because the Layered layout
does not keep nodes inside their interface containers. The classic route below still needs
Graphviz and is only relevant to diagrams 2 and 3 if the topology API proves insufficient.

The classic route wraps [PSGraph](https://github.com/KevinMarquette/PSGraph) over Graphviz. Existing modules
that use the framework and are worth reading before starting are `Veeam.Diagrammer` and
`Diagrammer.Microsoft.AD`.

### Proposed diagrams

**1. Trunk topology.** The appliance at the centre, its SIP peers around it.

- One central node per appliance, labelled with node name, platform type and release.
- A subgraph per logical interface, so it is obvious which groups share an interface.
- One node per signalling group, connected to the interface that carries its signalling.
- Beyond each group, its far end: SIP server table entries and federated hosts, with port and
  transport.
- Edge style carries transport. TLS, TCP and UDP should be distinguishable without reading the
  label.
- Group state carries through to the node. A drained group must not look like a healthy one.
- Where the peer is a recognised provider, use the provider identity rather than a bare host
  name. The firewall section already detects Microsoft Teams Direct Routing, so that detection
  is reusable rather than something to build again.

**2. Call flow.** Signalling group to route table to destination group, following the SBC's own
evaluation order. This is the picture people actually draw on whiteboards, and the data behind
it is already resolved.

**3. Multi-appliance.** When several targets are in one report, an appliance whose federated
host list contains another target's interface address is talking to it. Draw that link. This
falls out of the existing per-appliance data and needs no new parsing.

### What already exists to build on

No new configuration parsing should be needed. The resolvers hold everything:

| Data | Source |
|------|--------|
| Groups, state, interfaces, listen ports, federated hosts | `Resolve-AbrRibbonSignalingGroup` |
| Far end hosts, ports, transports | `Resolve-AbrRibbonSipConfiguration` |
| Interface names and addresses | `Resolve-AbrRibbonNetworkInterface` |
| Route tables in evaluation order | `Resolve-AbrRibbonCallRoute` |
| Provider identification | `Resolve-AbrRibbonFirewallRule` |

### Constraints to respect

- **The dependency must be optional.** Do not add `AsBuiltReport.Diagram` to
  `RequiredModules`. Detect it, and skip the diagram with a `Write-PScriboMessage -IsWarning`
  when it is absent.
- **Text format cannot carry an image.** `$Format` is not visible inside the report
  scriptblock, so the diagram cannot be gated on it. PScribo ignores images in Text output
  and the report still succeeds, which was verified.
- **CI must not need the diagram module.** The analyzer and Pester workflows run on a clean
  runner. Any test touching this has to skip cleanly when the framework is not installed.
- **PowerShell 5.1 is supported.** The report as a whole must run on 5.1. The topology API in
  `AsBuiltReport.Diagram` ships only a .NET 8 assembly, so with `ShowTopologyDiagram` enabled the report stops
  immediately on 5.1 and suggests re-running with `pwsh`.
- Gate it behind its own report option, as the firewall table is, rather than only an
  InfoLevel. A diagram is a presentation choice, not a detail level.

### Open questions

- Resolved for diagram 1: it sits inline after Signaling Groups. A combined multi-appliance
  diagram (diagram 3) would still belong in one section at the end.
- Resolved for diagram 1: above 24 rows with several interfaces, one diagram per interface is
  rendered. At most six far ends are drawn per group, with a "+N more" node for the rest.
- Is there a usable Ribbon icon set, and what are the licensing terms for redistributing it in
  this repository?

---

## SIP message manipulation (SMM)

**Status:** Designed

Report SMM tables: message rule tables, header rules, element descriptors, condition rules and
request line rules.

The volume across the current sample set justifies it: 126 element descriptors, 112 header
rules, 97 message tables, 19 request line rules and 6 condition rules. SMM changes what the far
end actually receives, so a build document that omits it is incomplete.

Tokens are `SIP/SIPSPRMessageRules/ID` and `SIP/SIPSPRConditionRules`.

Blocked on enum confirmation for the message rule table action values. These are **not** known
and must not be guessed. A saved copy of the WebUI message rule table edit page and condition
rule table page would settle them, which is how every other enum in this module was confirmed.

Signalling groups already resolve their ingress and egress rule table names, so the cross
reference exists. This is about rendering the rule contents.

---

## Configuration coverage gaps

**Status:** Proposed

Whole features present in real configurations that the report says nothing about:

- Secure Border Application (SBA)
- Link monitors
- Alarm and threshold crossing (TCA) configuration
- SIP registration tables

Before implementing any field from the coverage tooling, confirm the WebUI actually exposes a
control for it. The configuration export carries internal state the administrator has no say
over, and internal state does not belong in an as-built document. `PasswordHashType` was
measured as a coverage gap, then dropped once it turned out to have no WebUI control at all.

`Dev/Get-AbrRibbonFieldCoverage.ps1` measures the gap, but it overstates it for exactly that
reason.

---

## Unmapped enumerations

**Status:** Blocked

Values known to be unmapped, with what would unblock them:

| Field | Needed |
|-------|--------|
| `IsdnSgHuntMethod` | A saved ISDN signalling group WebUI page |
| `CNGToneDetection` polarity | Confirmation against the WebUI |
| SMM message rule table actions | A saved message rule table edit page |

Ribbon field names are not evidence of type or polarity. `SendConnectivityPacket` reads like a
boolean and is actually a packet type selector. Media list feature flags have per-field
polarity, some inverted and some not. Confirm against the WebUI or a controlled
before-and-after export. Do not infer.

---

## Additional sample configurations

**Status:** Proposed

The published sample set should exercise every health check and both platform families.

Sanitisation is done by restoring to real hardware, cleaning there, and re-exporting from the
WebUI. Editing the XML directly breaks cross references and the base64 sequence fields. See
[Dev/Samples/samples.md](Dev/Samples/samples.md) for the full procedure and
`Dev/Test-AbrRibbonSampleSafety.ps1` for the pre-publication gate.

---

## Language support

**Status:** Proposed

Only `en-US` ships today. The module is already fully externalised: every rendered string comes
from `Language/<culture>/RibbonSWeEdge.psd1`, and the test suite automatically extends its key
coverage to any culture folder that is added. A translation is a new folder, not a code change.

One thing to fix before a second culture is added. Object state values such as `Enabled`,
`Disabled` and `Drain` are emitted by the resolvers as invariant literals and rendered without
translation, and the health checks compare them against the localised strings. That works in
`en-US` only because the localised value happens to be identical to the literal. In any other
culture the comparison silently stops matching and the affected health checks stop
highlighting, without failing a test. The fix is to compare against the invariant literal and
translate only at render time. This is pre-existing, not specific to any one check.
