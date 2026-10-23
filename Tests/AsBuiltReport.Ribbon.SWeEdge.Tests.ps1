BeforeDiscovery {
    # Samples/ holds the sanitised export that ships with the module, so a clone runs these
    # tests against the same data CI does. Dev/Samples is the uncommitted working folder and
    # is only consulted when the published sample is absent. Tests needing a sample are
    # skipped when neither exists, so the suite still passes in a bare checkout. This has to
    # run during discovery because -Skip is evaluated before BeforeAll executes.
    $SampleFolder = @(
        Join-Path -Path $PSScriptRoot -ChildPath '..\Samples'
        Join-Path -Path $PSScriptRoot -ChildPath '..\Dev\Samples'
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $script:SampleXmlPath = (Get-ChildItem -Path $SampleFolder -Filter '*.xml' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    $script:SampleTarPath = (Get-ChildItem -Path $SampleFolder -Filter '*.tar' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    $script:HasXml = -not [String]::IsNullOrEmpty($script:SampleXmlPath)
    $script:HasTar = -not [String]::IsNullOrEmpty($script:SampleTarPath)
}

BeforeAll {
    $script:ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\AsBuiltReport.Ribbon.SWeEdge' -Resolve
    $script:ManifestPath = Join-Path -Path $script:ModuleRoot -ChildPath 'AsBuiltReport.Ribbon.SWeEdge.psd1'

    Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop

    # Private functions are not exported, so dot-source them for direct testing.
    Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Src\Private') -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }

    # Resolved again here because discovery phase variables are not visible during the run
    # phase. The BeforeDiscovery copies above exist purely to drive the -Skip conditions.
    $SampleFolder = @(
        Join-Path -Path $PSScriptRoot -ChildPath '..\Samples'
        Join-Path -Path $PSScriptRoot -ChildPath '..\Dev\Samples'
    ) | Where-Object { Test-Path -LiteralPath $_ }

    $script:SampleXmlPath = (Get-ChildItem -Path $SampleFolder -Filter '*.xml' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    $script:SampleTarPath = (Get-ChildItem -Path $SampleFolder -Filter '*.tar' -File -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
}

Describe 'Module Manifest' {

    BeforeAll {
        $script:Manifest = Test-ModuleManifest -Path $script:ManifestPath -ErrorAction Stop
    }

    It 'is a valid manifest' {
        $script:Manifest | Should -Not -BeNullOrEmpty
    }

    It 'is named AsBuiltReport.Ribbon.SWeEdge' {
        $script:Manifest.Name | Should -Be 'AsBuiltReport.Ribbon.SWeEdge'
    }

    It 'requires AsBuiltReport.Core' {
        $script:Manifest.RequiredModules.Name | Should -Contain 'AsBuiltReport.Core'
    }

    It 'exports only the Invoke-AsBuiltReport entry point' {
        $script:Manifest.ExportedFunctions.Keys | Should -Be 'Invoke-AsBuiltReport.Ribbon.SWeEdge'
    }
}

Describe 'Module Structure' {

    It 'has a <_> directory' -ForEach @('Src\Public', 'Src\Private', 'Language\en-US') {
        Join-Path -Path $script:ModuleRoot -ChildPath $_ | Should -Exist
    }

    It 'has an en-US language file' {
        Join-Path -Path $script:ModuleRoot -ChildPath 'Language\en-US\RibbonSWeEdge.psd1' | Should -Exist
    }

    It 'names every private function file after a function it defines' {
        $Failures = @()

        foreach ($File in Get-ChildItem -Path (Join-Path $script:ModuleRoot 'Src\Private') -Filter '*.ps1') {
            # Helpers.ps1 is the sanctioned home for shared utility functions.
            if ($File.BaseName -eq 'Helpers') {
                continue
            }

            $Tokens = $null
            $Errors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$Tokens, [ref]$Errors)
            $Defined = $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true).Name

            if ($Defined -notcontains $File.BaseName) {
                $Failures += $File.Name
            }
        }

        $Failures | Should -BeNullOrEmpty
    }
}

Describe 'Report Configuration' {

    BeforeAll {
        $script:ReportJson = Get-Content -Path (Join-Path $script:ModuleRoot 'AsBuiltReport.Ribbon.SWeEdge.json') -Raw | ConvertFrom-Json
    }

    It 'declares the standard Report properties' {
        $script:ReportJson.Report.Name | Should -Not -BeNullOrEmpty
        $script:ReportJson.Report.Language | Should -Not -BeNullOrEmpty
    }

    It 'has InfoLevel values within 0 to 5' {
        $Levels = $script:ReportJson.InfoLevel.PSObject.Properties |
            Where-Object { $_.Name -ne '_comment_' } |
            ForEach-Object { $_.Value }

        foreach ($Level in $Levels) {
            $Level | Should -BeGreaterOrEqual 0
            $Level | Should -BeLessOrEqual 5
        }
    }
}

Describe 'ConvertFrom-AbrRibbonSequence' {

    It 'returns an empty array for null or empty input' {
        @(ConvertFrom-AbrRibbonSequence -EncodedSequence '') | Should -HaveCount 0
        @(ConvertFrom-AbrRibbonSequence -EncodedSequence $null) | Should -HaveCount 0
    }

    It 'decodes little-endian Int16 pairs' {
        # 1, 2, 300 as little-endian Int16
        $Encoded = [Convert]::ToBase64String([Byte[]]@(1, 0, 2, 0, 44, 1))
        ConvertFrom-AbrRibbonSequence -EncodedSequence $Encoded -ByteCount 2 | Should -Be @(1, 2, 300)
    }

    It 'decodes single bytes when ByteCount is 1' {
        $Encoded = [Convert]::ToBase64String([Byte[]]@(3, 7, 9))
        ConvertFrom-AbrRibbonSequence -EncodedSequence $Encoded -ByteCount 1 | Should -Be @(3, 7, 9)
    }

    It 'discards zero padding' {
        $Encoded = [Convert]::ToBase64String([Byte[]]@(5, 0, 0, 0, 6, 0))
        ConvertFrom-AbrRibbonSequence -EncodedSequence $Encoded -ByteCount 2 | Should -Be @(5, 6)
    }

    It 'returns an empty array for malformed base64 rather than throwing' {
        @(ConvertFrom-AbrRibbonSequence -EncodedSequence 'not valid base64!!') | Should -HaveCount 0
    }
}

Describe 'ConvertFrom-AbrRibbonIeNode' {

    BeforeAll {
        [Xml] $script:Fragment = @'
<Configuration>
  <Token name="Test">
    <ID value="7">
      <IE classname="TEST_IE">
        <Description>Example row</Description>
        <MediaConfigID>4</MediaConfigID>
      </IE>
    </ID>
    <ID value="8">
      <IE />
    </ID>
  </Token>
</Configuration>
'@
        $script:Rows = @($script:Fragment.SelectNodes("//Token[@name='Test']/ID") | ConvertFrom-AbrRibbonIeNode)
    }

    It 'skips rows with no classname' {
        $script:Rows | Should -HaveCount 1
    }

    It 'exposes the row identifier as an integer' {
        $script:Rows[0].ID | Should -Be 7
        $script:Rows[0].ID | Should -BeOfType [Int]
    }

    It 'exposes the class name' {
        $script:Rows[0].ClassName | Should -Be 'TEST_IE'
    }

    It 'preserves every configuration field' {
        $script:Rows[0].Description | Should -Be 'Example row'
        $script:Rows[0].MediaConfigID | Should -Be '4'
    }
}

Describe 'Get-AbrRibbonOrderedRow' {

    BeforeAll {
        $script:Unordered = @(
            [PSCustomObject]@{ ID = 1 }
            [PSCustomObject]@{ ID = 2 }
            [PSCustomObject]@{ ID = 14 }
        )
    }

    It 'orders rows by the decoded sequence rather than by identifier' {
        $Sorted = Get-AbrRibbonOrderedRow -Row $script:Unordered -Order @(14, 1, 2)
        $Sorted.ID | Should -Be @(14, 1, 2)
    }

    It 'places rows missing from the sequence last' {
        $Sorted = Get-AbrRibbonOrderedRow -Row $script:Unordered -Order @(2)
        $Sorted[0].ID | Should -Be 2
        $Sorted[1].ID | Should -Be 1
        $Sorted[2].ID | Should -Be 14
    }

    It 'adds an ExecutionOrder property' {
        $Sorted = Get-AbrRibbonOrderedRow -Row $script:Unordered -Order @(14, 1, 2)
        $Sorted[0].ExecutionOrder | Should -Be 0
    }
}

Describe 'Resolve-AbrRibbonReference' {

    BeforeAll {
        $script:Lookup = @{ '2' = 'Telstra Production Media List' }
    }

    It 'resolves a known identifier' {
        Resolve-AbrRibbonReference -Id '2' -Lookup $script:Lookup | Should -Be 'Telstra Production Media List'
    }

    It 'treats zero and empty as not configured' {
        Resolve-AbrRibbonReference -Id '0' -Lookup $script:Lookup | Should -Be '--None--'
        Resolve-AbrRibbonReference -Id '' -Lookup $script:Lookup | Should -Be '--None--'
    }

    It 'marks an unknown identifier as unresolved instead of guessing' {
        Resolve-AbrRibbonReference -Id '99' -Lookup $script:Lookup | Should -Be 'Unresolved (ID 99)'
    }
}

Describe 'Import-AbrRibbonSWeEdgeConfig' {

    It 'throws for a missing file' {
        { Import-AbrRibbonSWeEdgeConfig -Path (Join-Path $TestDrive 'does-not-exist.xml') } | Should -Throw
    }

    It 'throws for an unsupported file type' {
        $Unsupported = Join-Path $TestDrive 'config.txt'
        Set-Content -Path $Unsupported -Value 'not a config'
        { Import-AbrRibbonSWeEdgeConfig -Path $Unsupported } | Should -Throw '*Unsupported configuration file type*'
    }

    It 'imports an XML export' -Skip:(-not $script:HasXml) {
        $Config = Import-AbrRibbonSWeEdgeConfig -Path $script:SampleXmlPath

        $Config.SourceFile | Should -Match '\.xml$'
        $Config.SystemRelease | Should -Not -BeNullOrEmpty
        $Config.SignalingGroups.Keys | Should -Contain 'SIP'
        $Config.RoutingTables.Count | Should -BeGreaterThan 0
    }

    It 'imports a TAR export' -Skip:(-not $script:HasTar) {
        $Config = Import-AbrRibbonSWeEdgeConfig -Path $script:SampleTarPath

        $Config.SourceFile | Should -Match '\.tar$'
        $Config.SystemRelease | Should -Not -BeNullOrEmpty
    }

    It 'preserves signaling group cross-references' -Skip:(-not $script:HasTar) {
        $Config = Import-AbrRibbonSWeEdgeConfig -Path $script:SampleTarPath
        $SipGroup = @($Config.SignalingGroups.SIP)[0]

        # Whichever sample happens to be present drives this test, and a factory default
        # export has no signalling groups at all. That is a gap in the sample rather than a
        # defect in the importer, so it is reported as skipped rather than failed.
        if (-not $SipGroup) {
            Set-ItResult -Skipped -Because 'the available sample export contains no SIP signaling groups'
            return
        }

        # These identifiers are how every downstream section resolves related objects.
        # Dropping them at import time is what previously forced name based guessing.
        $SipGroup.PSObject.Properties.Name | Should -Contain 'MediaConfigID'
        $SipGroup.PSObject.Properties.Name | Should -Contain 'RouteTableID'
    }

    It 'orders route entries by execution order' -Skip:(-not $script:HasTar) {
        $Config = Import-AbrRibbonSWeEdgeConfig -Path $script:SampleTarPath
        $Routes = @($Config.RoutingTables)[0].Routes

        if (-not $Routes) {
            Set-ItResult -Skipped -Because 'the available sample export contains no call routes'
            return
        }

        $Orders = @($Routes.ExecutionOrder)
        $Orders | Should -Be @($Orders | Sort-Object)
    }
}
