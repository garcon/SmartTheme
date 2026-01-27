# Simulation runner: defines safe mocks then executes SmartTheme.ps1

# Define global mocks to avoid system changes
function global:Register-SmartThemeUserTask {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($taskName,$cmd,$Time,$User,$RunnerExe,$SchtasksExe,$Config)
    $null = $User; $null = $RunnerExe; $null = $SchtasksExe; $null = $Config; $null = $cmd
    if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess($taskName, 'Register mock task')) { return $false }
    Write-Output "[MOCK] Register-SmartThemeUserTask: $taskName at $Time"; return $true
}

function global:Register-ThemeSwitch {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($Mode,$Time,$ScriptPath,$Config)
    $null = $ScriptPath; $null = $Config
    if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess($Mode, 'Register theme switch mock')) { return $false }
    Write-Output "[MOCK] Register-ThemeSwitch: $Mode at $Time"; return $true
}

function global:Set-Theme {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($Mode,$Config)
    $null = $Config
    if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess($Mode, 'Set theme mock')) { return }
    Write-Output "[MOCK] Set-Theme: $Mode"
}

function global:Register-ScheduledTask {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($TaskName,$Action,$Trigger,$Settings,$Force,$ErrorActionParam)
    $null = $Action; $null = $Trigger; $null = $Settings; $null = $Force; $null = $ErrorActionParam
    if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess($TaskName, 'Register scheduled task mock')) { return }
    Write-Output "[MOCK] Register-ScheduledTask: $TaskName"
}

function global:Export-SmartThemeTaskXml {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($taskName,$outPath,$CmdExe,$SchtasksExe,$Config)
    $null = $CmdExe; $null = $SchtasksExe; $null = $Config
    if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess($taskName, 'Export task xml mock')) { return $false }
    Write-Output "[MOCK] Export-SmartThemeTaskXml: $taskName -> $outPath"; return $true
}

function global:Invoke-Schtask {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($sArgs,$SchtasksExe)
    $null = $SchtasksExe
    if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess(($sArgs -join ' '), 'Invoke schtask mock')) { return @() }
    Write-Output "[MOCK] Invoke-Schtask: $($sArgs -join ' ')"; return @()
}

function global:Invoke-Cmd {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($cmdStr,$CmdExe)
    $null = $CmdExe
    if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess($cmdStr, 'Invoke cmd mock')) { return @() }
    Write-Output "[MOCK] Invoke-Cmd: $cmdStr"; return @()
}

function global:Set-ItemProperty {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($Path,$Name,$Value,$Type)
    $null = $Type
    if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess($Path, 'Set item property mock')) { return }
    Write-Output "[MOCK] Set-ItemProperty $Path $Name $Value"
}

function global:Unregister-ScheduledTask {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($TaskName,$ConfirmParam,$ErrorActionParam)
    $null = $ConfirmParam; $null = $ErrorActionParam
    if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess($TaskName, 'Unregister scheduled task mock')) { return }
    Write-Output "[MOCK] Unregister-ScheduledTask: $TaskName"
}

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
