BeforeDiscovery {
    $ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\AsBuiltReport.Ribbon.SWeEdge' -Resolve
    $script:LanguageFolder = Join-Path -Path $ModuleRoot -ChildPath 'Language'

    # One test case per supported culture, so adding a language automatically extends coverage.
    $script:Culture = @(
        Get-ChildItem -Path $script:LanguageFolder -Directory -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name }
    )

    # One test case per source file that scopes translations, so a missing key is attributed
    # to the file that would fail at runtime.
    $script:SourceFile = @(
        Get-ChildItem -Path (Join-Path $ModuleRoot 'Src') -Filter '*.ps1' -Recurse |
            Where-Object { (Get-Content -Path $_.FullName -Raw) -match '\$reportTranslate\.' } |
            ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } }
    )
}

BeforeAll {
    $script:ModuleRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\AsBuiltReport.Ribbon.SWeEdge' -Resolve
    $script:LanguageFolder = Join-Path -Path $script:ModuleRoot -ChildPath 'Language'
    $script:DefaultCulture = 'en-US'

    function Get-TranslationData {
        param([String] $Culture)

        Import-LocalizedData -BaseDirectory $script:LanguageFolder -FileName 'RibbonSWeEdge' -UICulture $Culture
    }
}

Describe 'Language files' {

    It 'provides the default en-US culture' {
        Join-Path -Path $script:LanguageFolder -ChildPath 'en-US\RibbonSWeEdge.psd1' | Should -Exist
    }

    It 'loads the <_> language file' -ForEach $script:Culture {
        { Get-TranslationData -Culture $_ } | Should -Not -Throw
    }

    It 'declares the culture comment in <_>' -ForEach $script:Culture {
        $Path = Join-Path -Path $script:LanguageFolder -ChildPath "$_\RibbonSWeEdge.psd1"
        (Get-Content -Path $Path -TotalCount 1) | Should -Match "^#\s*culture\s*=\s*'$_'"
    }

    It 'has the same keys in <_> as en-US' -ForEach ($script:Culture | Where-Object { $_ -ne 'en-US' }) {
        $Default = Get-TranslationData -Culture $script:DefaultCulture
        $Other = Get-TranslationData -Culture $_

        # Compare the full group.key path so a missing key inside a group is caught, not just
        # a missing group.
        $DefaultKey = foreach ($Group in $Default.Keys) {
            foreach ($Key in $Default[$Group].Keys) { "$Group.$Key" }
        }
        $OtherKey = foreach ($Group in $Other.Keys) {
            foreach ($Key in $Other[$Group].Keys) { "$Group.$Key" }
        }

        (Compare-Object -ReferenceObject @($DefaultKey) -DifferenceObject @($OtherKey)) | Should -BeNullOrEmpty
    }
}

Describe 'Translation coverage' {

    BeforeAll {
        $script:Translation = Get-TranslationData -Culture $script:DefaultCulture
    }

    It 'has a translation group for every function that scopes one' -ForEach $script:SourceFile {
        $Content = Get-Content -Path $_.Path -Raw

        foreach ($Match in [Regex]::Matches($Content, '\$reportTranslate\.(?<Group>\w+)')) {
            $Group = $Match.Groups['Group'].Value
            $script:Translation.Keys | Should -Contain $Group -Because "$($_.Name) scopes translations from $Group"
        }
    }

    It 'references only keys that exist, in <Name>' -ForEach $script:SourceFile {
        $Content = Get-Content -Path $_.Path -Raw

        $GroupMatch = [Regex]::Match($Content, '\$reportTranslate\.(?<Group>\w+)')
        if (-not $GroupMatch.Success) {
            Set-ItResult -Skipped -Because 'the file does not scope a translation group'
            return
        }

        $Group = $GroupMatch.Groups['Group'].Value
        $Available = @($script:Translation[$Group].Keys)

        # A missing key silently renders an empty heading or column name, so it is worth
        # catching at test time rather than in a customer's report.
        $Missing = foreach ($Match in [Regex]::Matches($Content, '\$LocalizedData\.(?<Key>\w+)')) {
            $Key = $Match.Groups['Key'].Value
            if ($Key -notin $Available) {
                $Key
            }
        }

        @($Missing | Sort-Object -Unique) | Should -BeNullOrEmpty
    }
}
