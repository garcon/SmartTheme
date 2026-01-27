Describe "Resolve-TimeZone" {
    BeforeAll {
        # Dot-source the helper to test
        . "$PSScriptRoot\..\lib\TimeZoneHelpers.ps1"
    }

    It "maps Europe/Prague to Central Europe Standard Time (or returns the same id if available)" {
        $res = Resolve-TimeZone 'Europe/Prague'
        ($res -in @('Central Europe Standard Time','Europe/Prague')) | Should Be $true
    }

    It "throws on empty string" {
        $threw = $false
        $err = $null
        try { Resolve-TimeZone '' } catch { $threw = $true; $err = $_.Exception.Message }
        $threw | Should Be $true
        $err | Should Not Be ''
    }
}
