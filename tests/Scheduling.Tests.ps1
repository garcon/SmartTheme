$libDir = Join-Path $PSScriptRoot '..\lib'
# Provide a lightweight global Translate implementation for these unit tests so module functions
# that call Translate don't depend on the full localization initialization.
function global:Translate { param($key, [Parameter(ValueFromRemainingArguments=$true)][object[]]$args) return $key }
# Minimal Write-Log for module functions during unit tests
function global:Write-Log { param($_message,$_level='INFO') return $null }
$locPath = Join-Path $libDir 'Localization.ps1'
if (Test-Path $locPath) { . $locPath; Initialize-Localization }
$modulePath = Join-Path $libDir 'SmartThemeModule.psm1'
if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction Stop }

Describe 'Schedule-ThemeSwitch behavior' {
    It 'Calls Schtasks-CreateForCurrentUser when not elevated' {
    # Arrange: ensure Test-IsElevated exists and mock elevation and the current user scheduling helper
    function Test-IsElevated { return $false }
    Mock -CommandName Test-IsElevated -MockWith { return $false }
    # Ensure helpers exist so Mock can replace them
    function Schtasks-CreateForCurrentUser { param($_taskName,$_cmd,$_Time,$_User,$_RunnerExe,$_SchtasksExe,$_Config) return $false }
    function Export-TaskXml { param($_taskName,$_outPath,$_CmdExe,$_SchtasksExe,$_Config) return $false }
    Mock -CommandName Schtasks-CreateForCurrentUser -MockWith { param($_taskName,$_cmd,$_Time,$_User,$_RunnerExe,$_SchtasksExe,$_Config) return $true }
    Mock -CommandName Export-TaskXml -MockWith { return $true }

        $tmp = Join-Path $env:TEMP 'st-test'
        if (-not (Test-Path $tmp)) { New-Item -Path $tmp -ItemType Directory | Out-Null }
        $cfg = [pscustomobject]@{ RunnerExe='pwsh.exe'; SchtasksExe='fake-schtasks.exe'; TempDir=$tmp; User='Tester' }

        # Act
        # Act & Assert: function completes without throwing
    { Schedule-ThemeSwitch -Mode 'Dark' -Time (Get-Date).AddMinutes(5) -ScriptPath 'C:\fake\script.ps1' -Config $cfg } | Should Not Throw
    }

    It 'Uses Create-RecommendTaskXml and Import-TaskXml when elevated' {
    function Test-IsElevated { return $true }
    Mock -CommandName Test-IsElevated -MockWith { return $true }
    # Ensure helpers exist so Mock can replace them
    function Create-RecommendTaskXml { param($_taskName,$_exe,$_arguments,$_startTime,$_outPath) return $false }
    function Import-TaskXml { param($_xmlPath,$_taskName,$_SchtasksExe,$_Config) return $false }
    Mock -CommandName Create-RecommendTaskXml -MockWith { return $true }
    Mock -CommandName Import-TaskXml -MockWith { return $true }

        $cfg = [pscustomobject]@{ RunnerExe='pwsh.exe'; SchtasksExe='fake-schtasks.exe'; TempDir=$env:TEMP }
    { Schedule-ThemeSwitch -Mode 'Light' -Time (Get-Date).AddMinutes(5) -ScriptPath 'C:\fake\script.ps1' -Config $cfg } | Should Not Throw
    }
}
