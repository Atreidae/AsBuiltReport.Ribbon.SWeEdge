<!-- ********** DO NOT EDIT THESE LINKS ********** -->
<p align="center">
    <a href="https://www.asbuiltreport.com/" alt="AsBuiltReport"></a>
            <img src='https://github.com/AsBuiltReport.png' width="8%" height="8%" /></a>
</p>
<p align="center">
    <a href="https://www.powershellgallery.com/packages/AsBuiltReport.Ribbon.SWeEdge/" alt="PowerShell Gallery Version">
        <img src="https://img.shields.io/powershellgallery/v/AsBuiltReport.Ribbon.SWeEdge.svg" /></a>
    <a href="https://www.powershellgallery.com/packages/AsBuiltReport.Ribbon.SWeEdge/" alt="PS Gallery Downloads">
        <img src="https://img.shields.io/powershellgallery/dt/AsBuiltReport.Ribbon.SWeEdge.svg" /></a>
    <a href="https://www.powershellgallery.com/packages/AsBuiltReport.Ribbon.SWeEdge/" alt="PS Platform">
        <img src="https://img.shields.io/powershellgallery/p/AsBuiltReport.Ribbon.SWeEdge.svg" /></a>
</p>
<p align="center">
    <a href="https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge/graphs/commit-activity" alt="GitHub Last Commit">
        <img src="https://img.shields.io/github/last-commit/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge/master.svg" /></a>
    <a href="https://raw.githubusercontent.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge/master/LICENSE" alt="GitHub License">
        <img src="https://img.shields.io/github/license/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge.svg" /></a>
    <a href="https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge/graphs/contributors" alt="GitHub Contributors">
        <img src="https://img.shields.io/github/contributors/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge.svg"/></a>
</p>
<p align="center">
    <a href="https://twitter.com/AsBuiltReport" alt="Twitter">
            <img src="https://img.shields.io/twitter/follow/AsBuiltReport.svg?style=social"/></a>
</p>

<p align="center">
    <a href='https://ko-fi.com/B0B7DDGZ7' target='_blank'><img height='36' style='border:0px;height:36px;' src='https://ko-fi.com/img/githubbutton_sm.svg' border='0' alt='Want to keep alive this project? Support me on Ko-fi' /></a>
</p>
<!-- ********** DO NOT EDIT THESE LINKS ********** -->

# Ribbon SWeEdge As Built Report

Ribbon SWeEdge As Built Report is a PowerShell module which works in conjunction with [AsBuiltReport.Core](https://github.com/AsBuiltReport/AsBuiltReport.Core).

[AsBuiltReport](https://github.com/AsBuiltReport/AsBuiltReport) is an open-sourced community project which utilises PowerShell to produce as-built documentation in multiple document formats for multiple vendors and technologies.

Please refer to the AsBuiltReport [website](https://www.asbuiltreport.com) for more detailed information about this project.

# :beginner: Getting Started
Below are the instructions on how to install, configure and generate a Ribbon SWeEdge As Built report.

## :floppy_disk: Supported Versions

The Ribbon SWeEdge As Built Report works from a configuration export rather than from live
queries, so it is not tied to a single firmware release. The export can be one you already
hold, or the report can collect a fresh one from the appliance for you. It has been validated
against configuration exports from the following;

| Platform | Validated releases |
|----------|--------------------|
| SWe Lite / SWe Edge | 9.1.0, 12.0.1, 12.2.0, 12.3.0, 13.0.0, 13.1.0 |
| SBC 1000 | 6.1.2, 9.0.7, 12.1.1, 12.2.0 |
| SBC 2000 | 6.1.2, 9.0.8, 12.3.0 |

Both `.tar` archive exports and raw `symphonyconfig.xml` exports are supported.

Collecting an export directly from an appliance requires the REST API. Older releases may not
offer it, in which case export the configuration from the WebUI and report on the file.

Where a release predates a feature, the legacy equivalent is read instead. For example,
configurations older than 6.0 use translation tables rather than transformation tables.

### PowerShell
This report is compatible with the following PowerShell versions;

| Windows PowerShell 5.1 |    PowerShell 7    |
|:----------------------:|:------------------:|
|   :white_check_mark:   | :white_check_mark: |

## :world_map: Language Support
The Ribbon SWeEdge As Built Report supports the following languages;

- English (US) (Default)

## :wrench: System Requirements

PowerShell 5.1 or PowerShell 7, and the following PowerShell modules are required for generating a Ribbon SWeEdge As Built Report.

- [AsBuiltReport.Ribbon.SWeEdge Module](https://www.powershellgallery.com/packages/AsBuiltReport.Ribbon.SWeEdge/)
- [AsBuiltReport.Core Module](https://www.powershellgallery.com/packages/AsBuiltReport.Core/)

`tar` is required to read `.tar` configuration exports. It ships with Windows 10 1803 and
later, and is present by default on Linux and macOS.

### :closed_lock_with_key: Required Privileges

What you need depends on how you point the report at the appliance.

**Reporting from an export file.** No appliance credentials are required. The only privilege
needed is read access to the file. A credential must still be supplied, because
AsBuiltReport.Core requires one for every report module, but any placeholder value is accepted
and it is not used.

**Collecting from the appliance.** The report signs in to the SBC REST API and downloads a
configuration backup. That needs a local account with the **REST** access level.

The SBC does not create one for you, and an existing WebUI administrator will not work: REST is
a separate access level, not an additional permission on an existing account. Create the account
under local user management in the WebUI and set its access level to **REST**. It is usable
straight away, as the forced password change on first sign in applies to WebUI accounts only.

The account only needs to read configuration. Do not reuse an account you use for anything else.

> [!IMPORTANT]
> A Ribbon configuration export contains sensitive material, including certificate private
> keys, SNMP community strings and shared secrets. Treat the export file with the same care as
> access to the appliance itself.
>
> The generated report never renders certificate content, private keys, passwords, shared
> secrets or SNMP community strings. These are discarded when the configuration is parsed
> rather than filtered at render time.

## :package: Module Installation

### PowerShell

```powershell
# Install
install-module AsBuiltReport.Ribbon.SWeEdge -Force

# Update
update-module AsBuiltReport.Ribbon.SWeEdge -Force
```

### GitHub
If you are unable to use the PowerShell Gallery, you can still install the module manually. Ensure you repeat the following steps for the [system requirements](https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge#wrench-system-requirements) also.

1. Download the code package / [latest release](https://github.com/AsBuiltReport/AsBuiltReport.Ribbon.SWeEdge/releases/latest) zip from GitHub
2. Extract the zip file
3. Copy the folder `AsBuiltReport.Ribbon.SWeEdge` to a path that is set in `$env:PSModulePath`.
4. Open a PowerShell terminal window and unblock the downloaded files with
    ```powershell
    $path = (Get-Module -Name AsBuiltReport.Ribbon.SWeEdge -ListAvailable).ModuleBase; Unblock-File -Path $path\*.psd1; Unblock-File -Path $path\Src\Public\*.ps1; Unblock-File -Path $path\Src\Private\*.ps1
    ```
5. Close and reopen the PowerShell terminal window.

_Note: You are not limited to installing the module to those example paths, you can add a new entry to the environment variable PSModulePath if you want to use another path._

## :pencil2: Configuration

The Ribbon SWeEdge As Built Report utilises a JSON file to allow configuration of report information, options, detail and healthchecks.

> [!IMPORTANT]
> Please remember to generate a new report JSON configuration file after each module update to ensure the report functions correctly.

A Ribbon SWeEdge report configuration file can be generated by executing the following command;
```powershell
New-AsBuiltReportConfig -Report Ribbon.SWeEdge -FolderPath <User specified folder> -Filename <Optional>
```

Executing this command will copy the default Ribbon SWeEdge report JSON configuration to a user specified folder.

All report settings can then be configured via the JSON file.

The following provides information of how to configure each schema within the report's JSON file.

<!-- ********** DO NOT CHANGE THE REPORT SCHEMA SETTINGS ********** -->
### Report
The **Report** schema provides configuration of the Ribbon SWeEdge report information.

| Sub-Schema          | Setting      | Default                                                                            | Description                                                                                     |
|---------------------|--------------|------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|
| Name                | User defined | Ribbon SWeEdge As Built Report | The name of the As Built Report                                                                 |
| Version             | User defined | 1.0                                                                                | The report version                                                                              |
| Status              | User defined | Released                                                                           | The report release status                                                                       |
| Language            | User defined | en-US                                                                              | The default report language. This can be customised if the report module provides multilingual support |
| ShowCoverPageImage  | true / false | true                                                                               | Toggle to enable/disable the display of the cover page image                                    |
| ShowTableOfContents | true / false | true                                                                               | Toggle to enable/disable table of contents                                                      |
| ShowHeaderFooter    | true / false | true                                                                               | Toggle to enable/disable document headers & footers                                             |
| ShowTableCaptions   | true / false | true                                                                               | Toggle to enable/disable table captions/numbering                                               |

### Options
The **Options** schema allows certain options within the report to be toggled on or off.

| Sub-Schema | Setting | Default | Description |
|------------|--------------|---------|-------------|
| ShowFirewallTable | true / false | true | Toggle to enable/disable the Firewall Requirements section |
| ShowTopologyDiagram | true / false | false | Toggle to enable/disable the Trunk Topology diagram. Requires the optional `AsBuiltReport.Diagram` module (`Install-Module AsBuiltReport.Diagram`); Graphviz is not needed. Requires PowerShell 7 or later. If the module is missing the diagram is skipped with a warning. In Windows PowerShell 5.1 the report stops immediately and suggests re-running with `pwsh` |
| SkipCertificateCheck | true / false | true | Ignore certificate validation errors when collecting an export from an appliance. Only applies when `Target` is a host name or IP address. Appliances normally present a self signed certificate, so this defaults to enabled. Set it to `false` once the SBC holds a certificate your machine trusts |

### InfoLevel
The **InfoLevel** schema allows configuration of each section of the report at a granular level. The following sections can be set.

| Sub-Schema | Default | Section |
|------------|:-------:|---------|
| System | 1 | Node identity, time and NTP, DNS and split DNS, static hosts, media system settings |
| Firewall | 1 | Network flows the appliance needs, derived from its configuration. On-box access control lists at level 5 |
| Networking | 1 | Logical interfaces, VLANs, static routes, DHCP, static ARP |
| Security | 1 | Certificates with expiry, TLS profiles |
| Media | 1 | Media lists with codec preference order, voice and fax codec profiles, crypto profiles |
| SIP | 1 | SIP server tables in failover order, SIP profiles |
| PhysicalTelephonyPort | 1 | Digital and analog telephony ports. Rendered only on appliances fitted with them |
| SignalingGroup | 1 | Signaling groups with resolved route table, media list, interfaces and federated peers |
| CallRouting | 1 | Route tables and transformation tables, in SBC evaluation order |
| TelephonyMapping | 1 | Cause code reroute, message translation, SIP to Q.850 and tone tables |
| EmergencyService | 1 | Emergency services configuration, callback number pools, notification managers |
| Logging | 1 | Syslog destinations, SNMP managers, per subsystem log levels |

There are 6 levels (0-5) of detail granularity for each section as follows;

| Setting | InfoLevel         | Description                                                                                         |
|:-------:|-------------------|-----------------------------------------------------------------------------------------------------|
|    0    | Disabled          | Does not collect or display any information                                                         |
|    1    | Enabled / Summary | Provides summarised information for a collection of objects                                         |
|    2    | Adv Summary       | Provides condensed, detailed information for a collection of objects                                |
|    3    | Detailed          | Provides detailed information for individual objects                                                |
|    4    | Adv Detailed      | Provides detailed information for individual objects, as well as information for associated objects |
|    5    | Comprehensive     | Provides comprehensive information for individual objects, such as advanced configuration settings  |

### Healthcheck
The **Healthcheck** schema is used to toggle health checks on or off.

| Sub-Schema | Setting | Default | Description | Highlight |
|------------|--------------|---------|-------------|-----------|
| System.NtpEnabled | true / false | true | Highlights an appliance with no NTP server enabled. Certificate validity is judged against the appliance clock, so drift presents as TLS failures that look like certificate faults | ![Critical](https://place-hold.it/15/FEDDD7/FEDDD7.png) No time synchronisation |
| Security.CertificateExpiry | true / false | true | Highlights appliance certificates by remaining validity | ![Critical](https://place-hold.it/15/FEDDD7/FEDDD7.png) Expired &nbsp; ![Warning](https://place-hold.it/15/FFF4C7/FFF4C7.png) Expiring soon |
| Security.CertificateExpiryWarningDays | Number | 60 | Days remaining below which a certificate is treated as expiring soon | |
| SignalingGroup.DrainState | true / false | true | Highlights a signalling group left in the Drain state. It still answers OPTIONS, so monitoring shows it healthy, but it rejects every call | ![Warning](https://place-hold.it/15/FFF4C7/FFF4C7.png) Draining |
| SignalingGroup.DisabledGroup | true / false | true | Highlights a disabled signalling group. Usually deliberate, but the common explanation for a trunk that looks configured and does not work | ![Warning](https://place-hold.it/15/FFF4C7/FFF4C7.png) Disabled |
| SignalingGroup.UnresolvedReference | true / false | true | Highlights a signalling group referring to an object that is not in the configuration, such as a deleted route table or media list | ![Critical](https://place-hold.it/15/FEDDD7/FEDDD7.png) Broken reference |
| CallRouting.DisabledRoute | true / false | true | Highlights a disabled route entry. Calls that appear to match it fall through to the next route, or fail | ![Warning](https://place-hold.it/15/FFF4C7/FFF4C7.png) Disabled |
| CallRouting.UnresolvedReference | true / false | true | Highlights a route referring to an object that is not in the configuration, such as a deleted destination signalling group or transformation table | ![Critical](https://place-hold.it/15/FEDDD7/FEDDD7.png) Broken reference |
| Configuration.UnreferencedObject | true / false | true | Adds a section listing configuration objects that nothing refers to, and objects reached only through a disabled referrer | |
| Logging.VerboseLogging | true / false | true | Highlights subsystems and syslog destinations left at Trace or Debug level | ![Warning](https://place-hold.it/15/FFF4C7/FFF4C7.png) Verbose logging enabled |
| SIP.ConsistentTlsProfile | true / false | true | Highlights a SIP server using a different TLS profile to the rest of its server table | ![Warning](https://place-hold.it/15/FFF4C7/FFF4C7.png) Inconsistent profile |

> [!NOTE]
> Some health checks are tied to an InfoLevel, because they highlight a row in a table that
> is not rendered at every level. `CallRouting.DisabledRoute` and
> `CallRouting.UnresolvedReference` need `InfoLevel.CallRouting` at 2 or above, and
> `System.NtpEnabled` needs `InfoLevel.System` at 2 or above.

## :computer: Examples

The `Target` parameter takes either the path to a Ribbon configuration export, or the host name
or IP address of an appliance. Given a path, the report is generated entirely offline. Given a
host, it signs in to the REST API, downloads a configuration backup, reports on it, and deletes
the downloaded archive when it is finished.

```powershell
# Reporting from an export file. A credential is required by AsBuiltReport.Core but is not used.
$Credential = Get-Credential

# Generate a Ribbon SWeEdge As Built Report in HTML format from a .tar export.
New-AsBuiltReport -Report Ribbon.SWeEdge -Target 'C:\Configs\SBC_Config_sbc01.tar' -Credential $Credential -Format HTML -OutputFolderPath 'C:\Reports'

# Generate the report in Word and HTML from a raw XML export.
New-AsBuiltReport -Report Ribbon.SWeEdge -Target 'C:\Configs\symphonyconfig.xml' -Credential $Credential -Format Word,HTML -OutputFolderPath 'C:\Reports'

# Report on several appliances in one document.
New-AsBuiltReport -Report Ribbon.SWeEdge -Target 'C:\Configs\sbc01.tar','C:\Configs\sbc02.tar' -Credential $Credential -Format HTML -OutputFolderPath 'C:\Reports'

# Use a saved report configuration to control section detail and health checks.
New-AsBuiltReport -Report Ribbon.SWeEdge -Target 'C:\Configs\sbc01.tar' -Credential $Credential -Format HTML -OutputFolderPath 'C:\Reports' -ReportConfigFilePath 'C:\Reports\RibbonSWeEdge.json'

# Collect from a live appliance. Here the credential is a REST account on the SBC and is used.
$RestCredential = Get-Credential

New-AsBuiltReport -Report Ribbon.SWeEdge -Target 'sbc01.contoso.com' -Credential $RestCredential -Format HTML -OutputFolderPath 'C:\Reports'

# Collect from several appliances that share a REST account.
New-AsBuiltReport -Report Ribbon.SWeEdge -Target 'sbc01.contoso.com','sbc02.contoso.com' -Credential $RestCredential -Format HTML -OutputFolderPath 'C:\Reports'
```

### Obtaining a configuration export

From the SBC WebUI, use **Tasks** then **Backup/Restore** to download a configuration backup.
The resulting `.tar` file is the input to this report.

> [!IMPORTANT]
> Do not set a password when exporting. A password protected export carries material that
> should stay on the appliance, including certificate private keys.

If you would rather not handle the file yourself, give `Target` the host name of the appliance
instead and the report will collect one. The archive is written to your temporary directory and
removed once the report has been rendered.

## :world_map: Roadmap

Planned and proposed work is recorded in [ROADMAP.md](ROADMAP.md), including topology diagrams,
SIP message manipulation reporting and the remaining configuration coverage gaps.

## :heart: Acknowledgements

This module builds on work by [Greig Sheridan](https://greiginsydney.com), whose
`Convert-RibbonSbcConfigToWord` script documented a great deal of the Ribbon configuration
format long before this project existed. Greig gave his permission for that knowledge to be
carried across to a modern platform. Where his findings could be verified against the WebUI or
real configuration data they were, and a small number turned out to be incomplete, so any error
here is this project's rather than his.

## :x: Known Issues

- Highlighting from health checks is rendered as cell shading, which the Text output format
  cannot express. In Text, a flagged row looks the same as any other. The paragraph explaining
  why a row was flagged is still printed, and Word and HTML show the highlighting normally.
- The ISDN channel hunt method is reported as its raw numeric value. The enumeration behind it
  has not been confirmed against the WebUI, and this module does not guess at Ribbon
  enumerations. It affects SBC 1000 and 2000 appliances with ISDN signalling groups only.
- SIP message manipulation tables are reported by name where a signalling group references
  them, but the rules inside them are not yet rendered. See [ROADMAP.md](ROADMAP.md).
- The `-InputFile` parameter set requires AsBuiltReport.Core 1.7.0 or later. On earlier Core
  releases, pass the configuration export to `-Target` instead, which is supported on all
  supported Core versions.
- A configuration export taken with a password set cannot be read. The module extracts the
  archive directly and has no facility for supplying a password. Export without one, which is
  the recommended practice anyway: a password protected export carries material that should
  stay on the appliance, including certificate private keys.
