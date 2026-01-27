Describe 'Wrappers: Invoke-RestWithRetry and command wrappers' {
    BeforeAll {
        $root = (Resolve-Path "$PSScriptRoot\..\").ProviderPath
        $modulePath = Join-Path $root 'lib\SmartThemeModule.psm1'
        if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction Stop }
    }

    It 'Invoke-RestWithRetry retries and returns on success' {
        $script:counter = 0
        $sb = { $script:counter++; if ($script:counter -lt 3) { throw 'fail' } else { return 'ok' } }
        $res = Invoke-RestWithRetry -ScriptBlock $sb -maxAttempts 5 -baseDelay 0
        $res | Should Be 'ok'
        $script:counter | Should Be 3
    }

    It 'wrapper functions exist' {
        (Get-Command Invoke-Schtask -ErrorAction SilentlyContinue) | Should Not Be $null
        (Get-Command Invoke-Cmd -ErrorAction SilentlyContinue) | Should Not Be $null
    }
}
