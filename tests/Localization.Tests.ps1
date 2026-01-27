Describe 'Localization module' {
    BeforeAll {
        # $PSScriptRoot points to the directory containing this test file when run via Invoke-Pester
        $root = (Resolve-Path "$PSScriptRoot\..\").ProviderPath
        $modulePath = Join-Path $root 'lib\LocalizationModule.psm1'
        if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction Stop }
    }

    It 'loads English locale and has DEFAULT_CITY London' {
        $en = Import-Locale 'en'
    $en | Should Not Be $null
    $en.DEFAULT_CITY | Should Be 'London'
    }

    It 'loads Czech locale and has DEFAULT_CITY Prague' {
        $cs = Import-Locale 'cs'
    $cs | Should Not Be $null
    $cs.DEFAULT_CITY | Should Be 'Prague'
    }

    It 'translates a basic key for cs locale' {
        Set-Localization -PreferredLocale 'cs'
        $out = Translate 'SCRIPT_RUNNING' 'C:\\temp\\script.ps1'
    $out | Should Not Be $null
    $out.GetType().Name | Should Be 'String'
    $out | Should Match '.+'
    }

    It 'translates with formatting arguments' {
        Set-Localization -PreferredLocale 'en'
        $out = Translate 'CURRENT_TO_TARGET' 'light' 'dark'
    $out | Should Not Be $null
        $out | Should Match 'light'
        $out | Should Match 'dark'
    }

    It 'has all english keys present in cs and de locales' {
        $root = (Resolve-Path "$PSScriptRoot\..\").ProviderPath
        $en = Get-Content "$root\lib\locales\en.json" -Raw | ConvertFrom-Json
        $cs = Get-Content "$root\lib\locales\cs.json" -Raw | ConvertFrom-Json
        $de = Get-Content "$root\lib\locales\de.json" -Raw | ConvertFrom-Json

        foreach ($p in $en.PSObject.Properties) {
            $k = $p.Name
            ($cs.PSObject.Properties.Name -contains $k) | Should Be $true
            ($de.PSObject.Properties.Name -contains $k) | Should Be $true
        }
    }
}
