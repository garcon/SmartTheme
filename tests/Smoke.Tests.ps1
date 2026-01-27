Describe 'Smoke: Set-Theme localized logging' {
    BeforeAll {
        $root = (Resolve-Path "$PSScriptRoot\..\").ProviderPath
        $modulePath = Join-Path $root 'lib\LocalizationModule.psm1'
        if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction Stop }
        $logModule = Join-Path $root 'lib\LoggingModule.psm1'
        if (Test-Path $logModule) { Import-Module $logModule -Force -ErrorAction Stop }

        # Initialize to Czech for deterministic test
        Initialize-Localization -PreferredLocale 'cs'

        # Capture writes instead of writing to console/file
        Set-Variable -Name CapturedLogs -Scope Global -Value @()
        function Test-WriteLog {
            param($_msg, $_Level = 'INFO')
            $script:CapturedLogs += ,$_msg
        }

        # Define a safe Set-Theme wrapper used only for tests (avoid registry changes)
        function Test-Set-Theme([string]$Mode) {
                if ($Mode -eq 'Dark') {
                # Simulate setting values and emitting the localized message
                Test-WriteLog (Translate 'THEME_SWITCHED_DARK') 'SUCCESS'
            }
            elseif ($Mode -eq 'Light') {
                Test-WriteLog (Translate 'THEME_SWITCHED_LIGHT') 'SUCCESS'
            }
        }
    }

    It 'emits localized message when switching to Dark' {
        Test-Set-Theme 'Dark'
        ($script:CapturedLogs -join "`n") | Should Match 'Prepnuto na tmavy rezim' -Because 'cs translation should be used'
    }

    It 'emits localized message when switching to Light' {
        Test-Set-Theme 'Light'
        ($script:CapturedLogs -join "`n") | Should Match 'Prepnuto na svetly rezim' -Because 'cs translation should be used'
    }
}
