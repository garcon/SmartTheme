Describe 'Utils: Normalize string' {
    BeforeAll {
        $root = (Resolve-Path "$PSScriptRoot\..\").ProviderPath
        $modulePath = Join-Path $root 'lib\Utils.psm1'
        if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction Stop }
    }

    It 'removes diacritics and normalizes whitespace/case' {
        $in = 'Přepnuto   na světlý  režim '
        $out = Normalize-StringForComparison $in
        $out | Should Be 'prepnuto na svetly rezim'
    }

    It 'returns empty string for null/empty' {
        $out = Normalize-StringForComparison $null
        $out | Should Be ''
    }
}
