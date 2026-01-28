$libDir = Join-Path $PSScriptRoot '..\lib'
# Minimal Translate/Write-Log for tests
function global:Translate { param($key, [Parameter(ValueFromRemainingArguments=$true)][object[]]$fmtArgs) $null = $fmtArgs; return $key }
function global:Write-Log { param($_message,$_level='INFO') $null = $_message; $null = $_level; return $null }

$modulePath = Join-Path $libDir 'SmartThemeModule.psm1'
if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction Stop }

Describe 'Get-EnsureTarget' {
    It 'returns Light when now is between sunrise and sunset' {
        $sunrise = Get-Date '2026-01-28T08:00:00'
        $sunset  = Get-Date '2026-01-28T18:00:00'
        $now     = Get-Date '2026-01-28T12:00:00'
        Get-EnsureTarget -Now $now -Sunrise $sunrise -Sunset $sunset | Should -Be 'Light'
    }

    It 'returns Dark when now is before sunrise' {
        $sunrise = Get-Date '2026-01-28T08:00:00'
        $sunset  = Get-Date '2026-01-28T18:00:00'
        $now     = Get-Date '2026-01-28T05:00:00'
        Get-EnsureTarget -Now $now -Sunrise $sunrise -Sunset $sunset | Should -Be 'Dark'
    }

    It 'returns Dark when now is after sunset' {
        $sunrise = Get-Date '2026-01-28T08:00:00'
        $sunset  = Get-Date '2026-01-28T18:00:00'
        $now     = Get-Date '2026-01-28T20:00:00'
        Get-EnsureTarget -Now $now -Sunrise $sunrise -Sunset $sunset | Should -Be 'Dark'
    }

    It 'treats time equal to sunrise as Light and equal to sunset as Dark' {
        $sunrise = Get-Date '2026-01-28T08:00:00'
        $sunset  = Get-Date '2026-01-28T18:00:00'
        Get-EnsureTarget -Now $sunrise -Sunrise $sunrise -Sunset $sunset | Should -Be 'Light'
        Get-EnsureTarget -Now $sunset  -Sunrise $sunrise -Sunset $sunset  | Should -Be 'Dark'
    }
}
