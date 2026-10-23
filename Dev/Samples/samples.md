# About the samples folder

This folder contains sample config files used during development. They are not intended to be a comprehensive test suite, but they do cover a wide range of real-world configurations and are useful for diagnostics and CI test fixtures.

They are based on real customer configurations that have been sanitized to remove any sensitive information. The sanitization process is lossy, so the samples are not suitable for testing the importer against every possible configuration. They are intended to be a representative sample of what the importer will encounter in the field.

These configs are provided as-is, and shouldn't be taken as the correct way to configure a Ribbon SBC. Some data may not make sense, or may be inconsistent due to the way I've manually sanitized them. The goal is to provide a wide range of real-world configurations for testing, not to provide a reference configuration.

# Testing on real hardware

If you need to restore these to your own hardware for development, you will find the credentials below useful. They are the same for every sample, and are not sensitive because the samples have been sanitized.

# Creating your own samples

Please, if you upload any additional samples, make sure they are sanitized first and that they use the same credentials.  This will make validation easier and avoid confusion if I need to test them in my lab.

ℹ️ Note: You will need to log in at least once as the SBC forces a password reset on sign in!
When exporting the config, do NOT set a password. If you do, the export will include data that should stay on the appliance like private keys!

⚠️ Warning! Do NOT sanitize the XML files directly. I've tried this, it breaks stuff. Instead, restore the config to a test appliance, sanitize it there, and export it again from the WebUI. This will produce a clean export that is safe to share.

# Checking your sanitisation

Before you share a sample, run it through the safety scanner:

```powershell
.\Dev\Test-AbrRibbonSampleSafety.ps1 -Path '.\Dev\Samples\your-export.tar'
```

It walks every field in the export and reports anything that doesn't match the conventions on this page: routable IP addresses outside the RFC 5737 and RFC 1918 ranges, host names outside `contoso.com`, numbers outside the 7010 range, email addresses, certificate and key material, and populated credential fields. It also lists every local account, because a leftover admin user is invisible in a diff but obvious in a list.

Use `-MustNotContain` for the things only you know to look for - the real customer name, their domain, their number ranges:

```powershell
.\Dev\Test-AbrRibbonSampleSafety.ps1 -Path '.\Dev\Samples\your-export.tar' -MustNotContain @('realcustomer', 'realcustomer.com.au', '203.15.')
```

The script exits non-zero if it finds anything, so you can use it as a gate.

Some findings are expected and fine to ignore:

- Carrier and vendor names (Telstra, Genesys, Enghouse and so on). These identify the *carrier*, not the customer, and keeping them makes the sample realistic.
- Public endpoints like `time.windows.com`, `sipfed.online.lync.com`, `8.8.8.8` and the `pstnhub.microsoft.com` addresses.
- The trusted root CA certificates that ship on the appliance, and their content.
- Populated `EncryptedPassword` fields, provided they hold the sample credentials below and not something carried over from the original appliance.
- Carrier service numbers. Add them to `-AllowedNumber` so they stop being reported.

⚠️ A clean result means nothing matched the patterns. It does not mean nothing was missed. Read the findings, then read the export.

# Credentials for all samples

- GUI Username: `Twilight`
- Password: `TwiReadsDocs`

- REST Username: 'Luna'
- Password: `NightPrincess_Auth`

- Generic Secrets for anything else in the config
  - User/ID/Auth: `user1`
  - Group Names: `group1`
  - Realm: `contoso.com`
  - Number/Address: `+61370105555`
  - Secret/password: `P@ssw0rd!`

# Certificates for samples

  - Common Name: `sbc1.contoso.com`

You can use the following script to generate a new test certificate chain:

```powershell
.\Dev\New-AbrRibbonTestCertificate.ps1
```

That writes two files to `Dev\output\certificates`. Import them in this order:

1. `sbc1.contoso.com-root-ca.cer` under **Settings > Security > SBC Certificates > Trusted CA Certificates**
2. `sbc1.contoso.com.pfx` under **Settings > Security > SBC Certificates > SBC Primary Certificate**,
   choosing PKCS12 and supplying the password you were prompted for


If you are building a sample and want it to demonstrate the certificate expiry health check,
generate one that is about to expire:

```powershell
.\Dev\New-AbrRibbonTestCertificate.ps1 -ValidityDays 20
```

# IP Addressing
In my lab I use the RFC 5737 ranges for addresses, and +61 x7010 xxxx for numbers as defined by the ACMA. This is to avoid any risk of using real customer data in the samples.

You might see 10.193.x.x alot too, again, my lab so dont stress.

For public IP addresses please use the RFC 5737 ranges. They are listed below
- `192.0.2.0/24`
- `198.51.100.0/24`
- `203.0.113.0/24`


Thanks.
James "UcMadScientist" Arber
