# Developer Tooling

Diagnostic and regression harnesses for working on this module. Nothing here ships with the
module itself; it exists so a contributor can inspect a Ribbon configuration, see what the
report does with it, and prove a change did not break anything.

## Before you start

You need a Ribbon SBC configuration export. The module reads the same backup file the WebUI
produces, so no appliance access is required to develop against it.

Put exports in `Dev/Samples`. That folder is gitignored, as is every configuration export
format anywhere in the tree, because a real export contains hostnames, addresses, dial plans,
SIP credentials and certificate material. **Read the `.gitignore` before adding anything to
this folder.** Publishing a sanitised sample is a deliberate act that requires `git add -f`;
that friction is intentional.

Generate an AsBuiltReport configuration once and save it as `Dev/output/AsBuiltReport.json`:

```powershell
New-AsBuiltConfig
```

Without it, `New-AsBuiltReport` starts its interactive wizard on every run. The file holds
your own name and company details, so it is gitignored.

## Harnesses

| Script | Purpose |
| --- | --- |
| `New-AbrRibbonTestReport.ps1` | Render one sample through AsBuiltReport.Core exactly as an end user would. The fastest way to see the effect of a change. |
| `Invoke-AbrRibbonRegression.ps1` | Render every sample you have, in Text, HTML and Word, and report failures and secret leaks. Run this before raising a pull request. |
| `Test-AbrRibbonImport.ps1` | Inspect what the importer produced from a configuration, by section. Use `-TokenPath` to dump an arbitrary part of the XML. |
| `Test-AbrRibbonFirewall.ps1` | Show the derived firewall flows for a configuration, and optionally the appliance access control list. |
| `Get-AbrRibbonSampleCoverage.ps1` | Report which samples exercise which features, so you can tell whether a change is actually covered. |
| `Get-AbrRibbonFieldUsage.ps1` | Tally the distinct values a given configuration field takes across every sample. Use this to establish what an enumeration means before writing a mapping for it. |
| `Get-AbrRibbonFirewallProbe.ps1` | Dump the raw fields of the configuration branches that feed the firewall section. |
| `New-AbrRibbonTestCertificate.ps1` | Generate a throwaway certificate chain to load into a lab appliance. Produces the root authority and the PKCS#12 bundle as separate files, which is what the appliance actually wants. |
| `redact_helper.ps1` | Helper for reducing a configuration object when sharing diagnostics. |

## Certificates for a lab appliance

Most quick certificate generators hand you a single self signed certificate, which a Ribbon
appliance will not accept. It wants the issuing authority in its trusted store before it will
take the certificate that authority signed. `New-AbrRibbonTestCertificate.ps1` produces both
halves:

```powershell
.\Dev\New-AbrRibbonTestCertificate.ps1
```

Import them in this order:

1. `<name>-root-ca.cer` under **Settings > Security > SBC Certificates > Trusted CA Certificates**
2. `<name>.pfx` under **Settings > Security > SBC Certificates > SBC Primary Certificate**,
   choosing PKCS12 and supplying the password

The certificate carries subject alternative names, server and client authentication, and a
2048 bit RSA key with SHA256. Client authentication matters: a trunk doing mutual TLS presents
its certificate as a client as well as a server.

Use `-ValidityDays` to produce a certificate that is about to expire, which is the easiest way
to exercise the certificate expiry health check:

```powershell
.\Dev\New-AbrRibbonTestCertificate.ps1 -ValidityDays 20
```

## Typical loop

```powershell
# See what the importer made of a configuration
.\Dev\Test-AbrRibbonImport.ps1 -Path '.\Dev\Samples\your-export.tar' -Section Summary

# Render it
.\Dev\New-AbrRibbonTestReport.ps1 -InfoLevel 3 -Format Word -Path '.\Dev\Samples\your-export.tar'

# Prove nothing broke
Invoke-Pester -Path .\Tests
Invoke-ScriptAnalyzer -Path '.\AsBuiltReport.Ribbon.SWeEdge' -Recurse -Severity Warning, Error
.\Dev\Invoke-AbrRibbonRegression.ps1
```

## Things that will catch you out

- **Always test the Word output.** Word fails outright when the number of `ColumnWidths` does
  not match the number of columns in a table. Text and HTML silently tolerate the mismatch and
  render a misleading table, so a change that looks fine in Text can be broken.
- **Test every InfoLevel from 1 to 5.** Columns are added conditionally by level, so a
  `ColumnWidths` mismatch usually only appears at one of them.
- **A Word document open in Word holds a lock on the file.** A render failing with
  `Exception calling "Open"` is a lock, not a code fault. Use `-Filename` to write elsewhere.
- **Never guess at a configuration value.** Ribbon references objects by exact numeric ID.
  If an ID cannot be resolved, the report says `Unresolved (ID n)` rather than inferring a
  match by name. Use `Get-AbrRibbonFieldUsage.ps1` to establish what an enumeration actually
  contains before mapping it.
- **Evaluation order is not document order.** Route entries, transformation rules and SIP
  servers are ordered by the parent table's base64 `Sequence` field. Rendering in ID order
  misrepresents how the appliance behaves.

## Reference

`config_model.md` documents the Ribbon configuration data model: how tokens, IDs and
information elements nest, which fields carry cross-references, and the enumerations that have
been confirmed against the WebUI. Read it before adding a section.
