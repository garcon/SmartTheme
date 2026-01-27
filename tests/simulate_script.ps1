# Simulation runner: defines safe mocks then executes SmartTheme.ps1

# Define global mocks to avoid system changes
function global:Register-SmartThemeUserTask { param($taskName,$cmd,$Time,$User,$RunnerExe,$SchtasksExe,$Config); Write-Output "[MOCK] Register-SmartThemeUserTask: $taskName at $Time"; return $true }
function global:Register-ThemeSwitch { param($Mode,$Time,$ScriptPath,$Config); Write-Output "[MOCK] Register-ThemeSwitch: $Mode at $Time"; return $true }
function global:Set-Theme { param($Mode,$Config); Write-Output "[MOCK] Set-Theme: $Mode" }
function global:Register-ScheduledTask { param($TaskName,$Action,$Trigger,$Settings,$Force,$ErrorAction); Write-Output "[MOCK] Register-ScheduledTask: $TaskName" }
function global:Export-SmartThemeTaskXml { param($taskName,$outPath,$CmdExe,$SchtasksExe,$Config); Write-Output "[MOCK] Export-SmartThemeTaskXml: $taskName -> $outPath"; return $true }
function global:Invoke-Schtask { param($sArgs,$SchtasksExe); Write-Output "[MOCK] Invoke-Schtask: $($sArgs -join ' ')"; return @() }
function global:Invoke-Cmd { param($cmdStr,$CmdExe); Write-Output "[MOCK] Invoke-Cmd: $cmdStr"; return @() }
function global:Set-ItemProperty { param($Path,$Name,$Value,$Type); Write-Output "[MOCK] Set-ItemProperty $Path $Name $Value" }
function global:Unregister-ScheduledTask { param($TaskName,$Confirm,$ErrorAction); Write-Output "[MOCK] Unregister-ScheduledTask: $TaskName" }

# Ensure logging functions are available (no-op if not)
if (-not (Get-Command Write-SmartThemeLog -ErrorAction SilentlyContinue)) {
    function global:Write-SmartThemeLog { param($msg,$level) Write-Output "[LOG $level] $msg" }
}
if (-not (Get-Command Write-Log -ErrorAction SilentlyContinue)) {
    function global:Write-Log { param($msg,$level) Write-Output "[LOG $level] $msg" }
}

# Run the real script from repository root with safe parameters (manual coords, schedule mode, debug)
$scriptPath = Resolve-Path (Join-Path $PSScriptRoot '..\SmartTheme.ps1')
Write-Output "--- Running SmartTheme.ps1 simulation (no destructive actions) ---"
& $scriptPath -Schedule -Lat 50.0755 -Lon 14.4378 -Debug
Write-Output "--- Simulation finished ---"
