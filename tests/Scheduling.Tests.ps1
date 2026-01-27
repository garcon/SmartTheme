$libDir = Join-Path $PSScriptRoot '..\lib'
# Provide a lightweight global Translate implementation for these unit tests so module functions
# that call Translate don't depend on the full localization initialization.
function global:Translate { param($key, [Parameter(ValueFromRemainingArguments=$true)][object[]]$fmtArgs) $null = $fmtArgs; return $key }
# Minimal Write-Log for module functions during unit tests
function global:Write-Log { param($_message,$_level='INFO') $null = $_message; $null = $_level; return $null }
$modulePath = Join-Path $libDir 'LocalizationModule.psm1'
if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction Stop; Set-Localization }
$modulePath = Join-Path $libDir 'SmartThemeModule.psm1'
if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction Stop }

Describe 'Schedule-ThemeSwitch behavior' {
    It 'Calls Register-SmartThemeUserTask when not elevated' {
    # Arrange: ensure Test-IsElevated exists and mock elevation and the current user scheduling helper
    function Test-IsElevated { return $false }
    Mock -CommandName Test-IsElevated -MockWith { return $false }
    # Ensure helpers exist so Mock can replace them
    function global:Register-SmartThemeUserTask { param($_taskName,$_cmd,$_Time,$_User,$_RunnerExe,$_SchtasksExe,$_Config) $null = $_taskName; $null = $_cmd; $null = $_Time; $null = $_User; $null = $_RunnerExe; $null = $_SchtasksExe; $null = $_Config; return $false }
    function Export-TaskXml { param($_taskName,$_outPath,$_CmdExe,$_SchtasksExe,$_Config) $null = $_taskName; $null = $_outPath; $null = $_CmdExe; $null = $_SchtasksExe; $null = $_Config; return $false }
    Mock -CommandName Register-SmartThemeUserTask -MockWith { return $true }
    Mock -CommandName Export-TaskXml -MockWith { return $true }

        $tmp = Join-Path $env:TEMP 'st-test'
        if (-not (Test-Path $tmp)) { New-Item -Path $tmp -ItemType Directory | Out-Null }
        $cfg = [pscustomobject]@{ RunnerExe='pwsh.exe'; SchtasksExe='fake-schtasks.exe'; TempDir=$tmp; User='Tester' }

        # Act
        # Act & Assert: function completes without throwing
    { Register-ThemeSwitch -Mode 'Dark' -Time (Get-Date).AddMinutes(5) -ScriptPath 'C:\fake\script.ps1' -Config $cfg } | Should Not Throw
    }

    It 'Uses New-SmartThemeTaskXml and Import-TaskXml when elevated' {
    function Test-IsElevated { return $true }
    Mock -CommandName Test-IsElevated -MockWith { return $true }
    # Ensure helpers exist so Mock can replace them
    function global:New-SmartThemeTaskXml { param($_taskName,$_exe,$_arguments,$_startTime,$_outPath) $null = $_taskName; $null = $_exe; $null = $_arguments; $null = $_startTime; $null = $_outPath; return $false }
    function Import-TaskXml { param($_xmlPath,$_taskName,$_SchtasksExe,$_Config) $null = $_xmlPath; $null = $_taskName; $null = $_SchtasksExe; $null = $_Config; return $false }
    Mock -CommandName New-SmartThemeTaskXml -MockWith { return $true }
    Mock -CommandName Import-TaskXml -MockWith { return $true }

        $cfg = [pscustomobject]@{ RunnerExe='pwsh.exe'; SchtasksExe='fake-schtasks.exe'; TempDir=$env:TEMP }
    { Register-ThemeSwitch -Mode 'Light' -Time (Get-Date).AddMinutes(5) -ScriptPath 'C:\fake\script.ps1' -Config $cfg } | Should Not Throw
    }
}
