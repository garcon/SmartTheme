function Write-SmartThemeLogFallback {
    param($msg, $level='INFO')
    try { Get-Command -Name Write-SmartThemeLog -ErrorAction Stop | Out-Null; Write-SmartThemeLog -msg $msg -Level $level; return }
    catch { Write-Verbose 'Write-SmartThemeLog not available; falling back' }
    try { Get-Command -Name Write-Log -ErrorAction Stop | Out-Null; Write-Log $msg $level; return }
    catch { Write-Verbose 'Write-Log not available; falling back' }
    Write-Output "[$level] $msg"
}

function Test-IsElevated {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}

function Get-EnsureTarget {
    param(
        [datetime]$Now,
        [datetime]$Sunrise,
        [datetime]$Sunset
    )
    try {
        if (($Now -ge $Sunrise) -and ($Now -lt $Sunset)) { return 'Light' } else { return 'Dark' }
    } catch { return 'Dark' }
}

function Test-ConfigExecutable {
    param([psobject]$Config)
    if (-not $Config) { return $null }
    $c = $Config
    foreach ($key in @('RunnerExe','SchtasksExe','CmdExe')) {
        $val = $null
        try { $val = $c.$key } catch { $val = $null }
        if (-not $val) { continue }
        try {
            $cmd = Get-Command -Name $val -ErrorAction SilentlyContinue
            if ($cmd -and $cmd.Path) { $c | Add-Member -NotePropertyName $key -NotePropertyValue $cmd.Path -Force }
            else {
                if (Test-Path $val) { $c | Add-Member -NotePropertyName $key -NotePropertyValue (Resolve-Path $val).Path -Force }
                else { Write-SmartThemeLogFallback ("EXEC_NOT_FOUND: $key $val") 'WARN' }
            }
        } catch {
            Write-SmartThemeLogFallback ("EXEC_CHECK_ERROR: $key $_") 'DEBUG'
        }
    }
    return $c
}

function Invoke-Schtask([string[]]$sArgs, [string]$SchtasksExe = 'schtasks.exe') {
    try {
        try { Write-SmartThemeLogFallback ("Invoke-Schtask: $SchtasksExe " + ($sArgs -join ' ')) 'DEBUG' } catch { Write-Verbose 'Invoke-Schtask logging failed; continuing' }
        Write-Output ("INVOKE-SCHTASK: $SchtasksExe " + ($sArgs -join ' '))
        return & $SchtasksExe @sArgs 2>&1
    } catch {
        Write-SmartThemeLogFallback ("Invoke-Schtask failed: $_") 'WARN'
        return @($_)
    }
}

function Invoke-Cmd([string]$cmdStr, [string]$CmdExe = 'cmd.exe') {
    try { return & $CmdExe /c $cmdStr 2>$null } catch { return @($_) }
}

function Register-SmartThemeUserTask {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$taskName,
        [string]$cmd,
        [datetime]$Time,
        [string]$User = $env:USERNAME,
        [string]$RunnerExe = 'powershell.exe',
        [string]$SchtasksExe = 'schtasks.exe',
        [psobject]$Config = $null
    )
    if ($Config) {
        if ($Config.User) { $User = $Config.User }
        if ($Config.RunnerExe) { $RunnerExe = $Config.RunnerExe }
        if ($Config.SchtasksExe) { $SchtasksExe = $Config.SchtasksExe }
    }
    $st = $Time.ToString('HH:mm')
    $sd = $Time.ToString('MM\/dd\/yyyy')
    $fullCmd = "$RunnerExe $cmd"
    if ($PSCmdlet.ShouldProcess($taskName, 'Create limited schtasks for current user')) {
        $tr = '"' + $fullCmd + '"'
        $out = Invoke-Schtask -sArgs @('/Create','/SC','ONCE','/TN',$taskName,'/TR',$tr,'/ST',$st,'/SD',$sd,'/RL','LIMITED','/RU',$User,'/F') -SchtasksExe $SchtasksExe
        $out | ForEach-Object { Write-SmartThemeLogFallback ("SCHTASKS_USER: $_") }
    }
    if ($LASTEXITCODE -eq 0) { return $true } else { return $false }
}

function Get-CurrentTheme {
    param([string]$RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', [psobject]$Config = $null)
    if ($Config -and $Config.RegPath) { $RegPath = $Config.RegPath }
    try { $appsTheme = Get-ItemPropertyValue -Path $RegPath -Name AppsUseLightTheme -ErrorAction Stop; if ($appsTheme -eq 1) { 'Light' } else { 'Dark' } } catch { 'Unknown' }
}

function Set-Theme {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$Mode, [string]$RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize', [psobject]$Config = $null)
    if ($Config -and $Config.RegPath) { $RegPath = $Config.RegPath }
    if ($Mode -eq 'Dark') {
        if ($PSCmdlet.ShouldProcess("Registry: $RegPath", 'Set AppsUseLightTheme/SystemUsesLightTheme to Dark')) {
            Set-ItemProperty -Path $RegPath -Name AppsUseLightTheme -Value 0 -Type DWord
            Set-ItemProperty -Path $RegPath -Name SystemUsesLightTheme -Value 0 -Type DWord
                Write-SmartThemeLogFallback ("THEME_SWITCHED_DARK") 'SUCCESS'
        }
    }
    elseif ($Mode -eq 'Light') {
        if ($PSCmdlet.ShouldProcess("Registry: $RegPath", 'Set AppsUseLightTheme/SystemUsesLightTheme to Light')) {
            Set-ItemProperty -Path $RegPath -Name AppsUseLightTheme -Value 1 -Type DWord
            Set-ItemProperty -Path $RegPath -Name SystemUsesLightTheme -Value 1 -Type DWord
            Write-SmartThemeLogFallback ("THEME_SWITCHED_LIGHT") 'SUCCESS'
        }
    }
}

function Register-ThemeSwitch {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$Mode,
        [datetime]$Time,
        [string]$ScriptPath,
        [string]$TempDir = $env:TEMP,
        [string]$RunnerExe = 'powershell.exe',
        [string]$SchtasksExe = 'schtasks.exe',
        [string]$User = $env:USERNAME,
        [psobject]$Config = $null
    )

    if ($Config) {
        if ($Config.TempDir) { $TempDir = $Config.TempDir }
        if ($Config.RunnerExe) { $RunnerExe = $Config.RunnerExe }
        if ($Config.SchtasksExe) { $SchtasksExe = $Config.SchtasksExe }
        if ($Config.User) { $User = $Config.User }
    }

    $taskName = "SmartThemeSwitch-$Mode"
    $shimPath = Join-Path $env:LOCALAPPDATA 'SmartTheme\\theme.cmd'
    $useShim = $false
    if (Test-Path $shimPath) { $useShim = $true }
    # Commands: use Ensure for scheduled invocation to avoid incorrect late-run behavior
    if ($useShim) {
        $cmdEnsure = "`"$shimPath`" -Ensure"
        $cmdAtTime = $cmdEnsure
    } else {
        $cmdEnsure = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Ensure"
        $cmdAtTime = $cmdEnsure
    }

    $now = Get-Date
    if ($Time -lt $now) { Write-SmartThemeLogFallback ("SCHEDULE_ADJUSTED_ADD_DAY $Time $now") 'DEBUG'; $Time = $Time.AddDays(1) }

    $scheduled = $false

    if (-not (Test-IsElevated)) {
        Write-SmartThemeLogFallback ("NON_ELEVATED_ATTEMPT") 'DEBUG'
        try {
            if (Get-Command -Name 'Register-ScheduledTask' -ErrorAction SilentlyContinue) {
                $actionExe = if ($useShim) { $shimPath } else { $RunnerExe }
                $actionArgs = if ($useShim) { '-Ensure' } else { $cmdEnsure }
                $action = New-ScheduledTaskAction -Execute $actionExe -Argument $actionArgs
                $triggerOnce = New-ScheduledTaskTrigger -Once -At $Time
                Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggerOnce -User $User -Force -ErrorAction Stop
                Write-SmartThemeLogFallback ("SCHEDULED_USER_API $taskName $User") 'INFO'
                $scheduled = $true
            } else {
                if (Register-SmartThemeUserTask -taskName $taskName -cmd $cmdEnsure -Time $Time -User $User -RunnerExe $RunnerExe -SchtasksExe $SchtasksExe) {
                    Write-SmartThemeLogFallback ("SCHEDULED_USER_ATTIME $taskName $User") 'INFO'
                    $scheduled = $true
                } else { Write-SmartThemeLogFallback ("SCHEDULE_USER_ONCE_FAILED $taskName") 'WARN' }

                $st = $Time.ToString('HH:mm'); $sd = $Time.ToString('MM\/dd\/yyyy')
                if ($useShim) { $fullCmd = $cmdEnsure } else { $fullCmd = "$RunnerExe $cmdEnsure" }
                if ($PSCmdlet.ShouldProcess($taskName + '-Startup', 'Create startup schtask for current user')) {
                    $tr1 = '"' + $fullCmd + '"'
                    $out1 = Invoke-Schtask -sArgs @('/Create','/SC','ONSTART','/TN',"$taskName-Startup",'/TR',$tr1,'/F') -SchtasksExe $SchtasksExe
                    $out1 | ForEach-Object { Write-SmartThemeLogFallback ("SCHTASKS_USER_STARTUP: $_") }
                }
                if ($PSCmdlet.ShouldProcess($taskName + '-Logon', 'Create logon schtask for current user')) {
                    $tr2 = '"' + $fullCmd + '"'
                    $out2 = Invoke-Schtask -sArgs @('/Create','/SC','ONLOGON','/TN',"$taskName-Logon",'/TR',$tr2,'/F') -SchtasksExe $SchtasksExe
                    $out2 | ForEach-Object { Write-SmartThemeLogFallback ("SCHTASKS_USER_LOGON: $_") }
                }
            }
        } catch { Write-SmartThemeLogFallback ("NON_ELEVATED_ERROR: $_") 'ERROR' }
        return $scheduled
    }

    try {
        $backupXml = Join-Path $TempDir "$taskName-backup.xml"
        Export-SmartThemeTaskXml -taskName $taskName -outPath $backupXml -SchtasksExe $SchtasksExe | Out-Null
        if ($PSCmdlet.ShouldProcess($taskName, 'Unregister existing scheduled task')) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue }

        $xmlPath = Join-Path $TempDir "$taskName.xml"
        $exe = if ($useShim) { $shimPath } else { $RunnerExe }
        # For the ONCE schedule run `-Ensure` (so late runs use current conditions); startup/logon also run Ensure
        $argumentsForXml = if ($useShim) { "-Ensure" } else { $cmdEnsure }

        if (New-SmartThemeTaskXml -taskName $taskName -exe $exe -arguments $argumentsForXml -startTime $Time -outPath $xmlPath) {
            if ($PSCmdlet.ShouldProcess($taskName, 'Import task XML into scheduled tasks')) {
                if (Import-SmartThemeTaskXml -xmlPath $xmlPath -taskName $taskName -SchtasksExe $SchtasksExe) {
                    Write-SmartThemeLogFallback ("SCHEDULE_XML_SCHEDULED $taskName") 'INFO'
                    $scheduled = $true
                    return $scheduled
                } else { Write-SmartThemeLogFallback ("IMPORT_XML_FAILED $taskName") 'WARN' }
            }
        }

        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries
        $action = New-ScheduledTaskAction -Execute $exe -Argument $arguments
        $triggerOnce = New-ScheduledTaskTrigger -Once -At $Time
        $triggerStartup = New-ScheduledTaskTrigger -AtStartup
        $triggerLogon = New-ScheduledTaskTrigger -AtLogOn
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerOnce,$triggerStartup,$triggerLogon) -Settings $settings -Force -ErrorAction Stop
        Write-SmartThemeLogFallback ("SCHEDULED_API $taskName") 'INFO'
        Write-SmartThemeLogFallback ("SCHEDULE_SETTINGS_INFO") 'INFO'
        $scheduled = $true
        return $scheduled
    } catch { Write-SmartThemeLogFallback ("SCHEDULE_API_FAILED: $_") 'ERROR' }

    try {
        $st = $Time.ToString('HH:mm'); $sd = $Time.ToString('MM\/dd\/yyyy')
        Invoke-Schtask -sArgs @('/Delete','/TN',$taskName,'/F') -SchtasksExe $SchtasksExe | Out-Null
        # Schedule the ONCE task to run the ensure command (not explicit Light/Dark)
        if ($useShim) { $trMain = '"' + $cmdEnsure + '"' } else { $trMain = '"' + "$RunnerExe $cmdEnsure" + '"' }
        $out = Invoke-Schtask -sArgs @('/Create','/SC','ONCE','/TN',$taskName,'/TR',$trMain,'/ST',$st,'/SD',$sd,'/F') -SchtasksExe $SchtasksExe
        $out | ForEach-Object { Write-SmartThemeLogFallback ("SCHTASKS_OUT: $_") }
        if ($LASTEXITCODE -eq 0) { Write-SmartThemeLogFallback ("SCHTASKS_SCHEDULED $taskName $sd $st") 'INFO'; Write-SmartThemeLogFallback ("SCHTASKS_FALLBACK_NOTE") 'INFO'; $scheduled = $true } else { Write-SmartThemeLogFallback ("SCHTASKS_EXITCODE $LASTEXITCODE") }

        # Create startup/logon tasks that run Ensure (keeps the system in correct mode)
        $trEnsure = if ($useShim) { '"' + $cmdEnsure + '"' } else { '"' + "$RunnerExe $cmdEnsure" + '"' }
        $outS = Invoke-Schtask -sArgs @('/Create','/SC','ONSTART','/TN',"$taskName-Startup",'/TR',$trEnsure,'/F') -SchtasksExe $SchtasksExe
        $outS | ForEach-Object { Write-SmartThemeLogFallback ("SCHTASKS_STARTUP_OUT: $_") }
        $outL = Invoke-Schtask -sArgs @('/Create','/SC','ONLOGON','/TN',"$taskName-Logon",'/TR',$trEnsure,'/F') -SchtasksExe $SchtasksExe
        $outL | ForEach-Object { Write-SmartThemeLogFallback ("SCHTASKS_LOGON_OUT: $_") }

        return $scheduled
    } catch { Write-SmartThemeLogFallback ("SCHEDULE_ERROR: $_") 'ERROR'; return $false }
}

function Export-SmartThemeTaskXml {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$taskName,
        [string]$outPath,
        [string]$CmdExe = 'cmd.exe',
        [string]$SchtasksExe = 'schtasks.exe',
        [psobject]$Config = $null
    )
    if ($Config) { if ($Config.CmdExe) { $CmdExe = $Config.CmdExe } if ($Config.SchtasksExe) { $SchtasksExe = $Config.SchtasksExe } }
    try {
        Write-SmartThemeLogFallback ("EXPORT_TASK $taskName $outPath") 'DEBUG'
        $cmd = "$SchtasksExe /Query /TN `"$taskName`" /XML"
        if ($PSCmdlet.ShouldProcess($outPath, 'Export scheduled task XML')) { & $CmdExe /c "$cmd > `"$outPath`"" 2>$null; if (Test-Path $outPath) { Write-SmartThemeLogFallback ("EXPORT_TASK_DONE $outPath") 'DEBUG'; return $true } }
    } catch { Write-SmartThemeLogFallback ("EXPORT_TASK_FAIL $taskName $_") 'WARN' }
    return $false
}

function New-SmartThemeTaskXml {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($taskName,$exe,$arguments,[datetime]$startTime,$outPath)
    $startBoundary = $startTime.ToString('yyyy-MM-ddTHH:mm:ss')
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
    <RegistrationInfo>
        <Author>SmartTheme</Author>
        <Description>SmartTheme ensure task - auto-generated ($taskName)</Description>
    </RegistrationInfo>
    <Triggers>
        <TimeTrigger>
            <StartBoundary>$startBoundary</StartBoundary>
            <Enabled>true</Enabled>
        </TimeTrigger>
        <BootTrigger />
        <LogonTrigger />
    </Triggers>
    <Principals>
        <Principal id="Author">
            <RunLevel>LeastPrivilege</RunLevel>
        </Principal>
    </Principals>
    <Settings>
        <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
        <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
        <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
        <AllowHardTerminate>true</AllowHardTerminate>
        <StartWhenAvailable>true</StartWhenAvailable>
        <WakeToRun>false</WakeToRun>
        <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    </Settings>
    <Actions Context="Author">
        <Exec>
            <Command>$exe</Command>
            <Arguments>$arguments</Arguments>
        </Exec>
    </Actions>
</Task>
"@
    try {
            if ($PSCmdlet.ShouldProcess($outPath, 'Create task XML file')) { [System.IO.File]::WriteAllText($outPath, $xml, [System.Text.Encoding]::Unicode); Write-SmartThemeLogFallback ("XML_CREATED $outPath") 'DEBUG'; return $true }
        } catch { Write-SmartThemeLogFallback ("XML_CREATE_FAIL $outPath $_") 'ERROR'; return $false }
}

function Import-SmartThemeTaskXml {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$xmlPath,[string]$taskName,[string]$SchtasksExe='schtasks.exe',[psobject]$Config=$null)
    if ($Config -and $Config.SchtasksExe) { $SchtasksExe = $Config.SchtasksExe }
    try {
        Write-SmartThemeLogFallback ("IMPORTING_XML $xmlPath $taskName") 'DEBUG'
        if ($PSCmdlet.ShouldProcess($taskName, 'Import task XML (schtasks /Create /XML)')) {
            $out = Invoke-Schtask -sArgs @('/Create','/TN',$taskName,'/XML',$xmlPath,'/F') -SchtasksExe $SchtasksExe
            $out | ForEach-Object { Write-SmartThemeLogFallback ("SCHTASKS_IMPORT: $_") }
            if ($LASTEXITCODE -eq 0) { Write-SmartThemeLogFallback ("IMPORT_XML_DONE $taskName") 'INFO'; return $true }
        }
    } catch { Write-SmartThemeLogFallback ("IMPORT_XML_ERROR: $_") 'ERROR' }
    return $false
}

function Invoke-RestWithRetry {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([scriptblock]$ScriptBlock,[int]$maxAttempts=3,[int]$baseDelay=2)
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess(($ScriptBlock.ToString()), 'Execute scriptblock')) { Write-SmartThemeLogFallback ('EXEC_CANCELLED_BY_SHOULDPROCESS') 'DEBUG'; return $null }
            $result = & $ScriptBlock
            return $result
        }
        catch {
            if ($i -eq $maxAttempts) { throw }
            $delay = [int]($baseDelay * [math]::Pow(2, $i - 1))
            Write-SmartThemeLogFallback (Translate 'RETRY_WAIT' $delay $i $maxAttempts) 'DEBUG'
            Start-Sleep -Seconds $delay
        }
    }
    if (-not $CacheDir) { $CacheDir = Join-Path $env:LOCALAPPDATA 'SmartTheme' }
    if (-not (Test-Path $CacheDir)) { New-Item -Path $CacheDir -ItemType Directory | Out-Null }
    if (-not $CacheFile) { $CacheFile = Join-Path $CacheDir 'location.json' }
    $obj = @{ latitude=$lat; longitude=$lon; timezone=$tz; city=$city; timestamp=(Get-Date).ToString('o') }
    if ($sunriseUtc) { $obj.sunriseUtc = $sunriseUtc }
    if ($sunsetUtc)  { $obj.sunsetUtc  = $sunsetUtc }
    if ($dateStr)    { $obj.date = $dateStr }
    $json = $obj | ConvertTo-Json
    if ($PSCmdlet.ShouldProcess($CacheFile, 'Write location cache')) { $json | Set-Content -Path $CacheFile -Encoding UTF8 }
}

function Get-LocationCache([string]$CacheFile=$null,[string]$CacheDir=$null,[psobject]$Config=$null) { if ($Config -and $Config.CacheDir) { $CacheDir = $Config.CacheDir } ; if ($Config -and $Config.CacheFile) { $CacheFile = $Config.CacheFile } ; if (-not $CacheDir) { $CacheDir = Join-Path $env:LOCALAPPDATA 'SmartTheme' } ; if (-not $CacheFile) { $CacheFile = Join-Path $CacheDir 'location.json' } ; if (Test-Path $CacheFile) { try { return Get-Content $CacheFile -Raw | ConvertFrom-Json } catch { return $null } } ; return $null }

Export-ModuleMember -Function *

function Export-SmartThemeTaskXml {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$taskName,
        [string]$outPath,
        [string]$CmdExe = 'cmd.exe',
        [string]$SchtasksExe = 'schtasks.exe',
        [psobject]$Config = $null
    )
    if ($Config) {
        if ($Config.CmdExe) { $CmdExe = $Config.CmdExe }
        if ($Config.SchtasksExe) { $SchtasksExe = $Config.SchtasksExe }
    }
    try {
        Write-SmartThemeLogFallback (Translate 'EXPORT_TASK' $taskName $outPath) 'DEBUG'
        if (Get-Command -Name Export-TaskXml -ErrorAction SilentlyContinue) {
            return Export-TaskXml -TaskName $taskName -OutPath $outPath -CmdExe $CmdExe -SchtasksExe $SchtasksExe -Config $Config
        }
        $cmd = "$SchtasksExe /Query /TN `"$taskName`" /XML"
        if ($PSCmdlet.ShouldProcess($outPath, 'Export scheduled task XML')) {
            & $CmdExe /c "$cmd > `"$outPath`"" 2>$null
            if (Test-Path $outPath) { Write-SmartThemeLogFallback (Translate 'EXPORT_TASK_DONE' $outPath) 'DEBUG'; return $true }
        }
    }
    catch {
        Write-SmartThemeLogFallback (Translate 'EXPORT_TASK_FAIL' $taskName $_) 'WARN'
    }
    return $false
}

function New-SmartThemeTaskXml {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        $taskName,
        $exe,
        $arguments,
        [datetime]$startTime,
        $outPath
    )
    $startBoundary = $startTime.ToString('yyyy-MM-ddTHH:mm:ss')
    $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
    <RegistrationInfo>
        <Author>SmartTheme</Author>
        <Description>SmartTheme ensure task - auto-generated ($taskName)</Description>
    </RegistrationInfo>
    <Triggers>
        <TimeTrigger>
            <StartBoundary>$startBoundary</StartBoundary>
            <Enabled>true</Enabled>
        </TimeTrigger>
        <BootTrigger />
        <LogonTrigger />
    </Triggers>
    <Principals>
        <Principal id="Author">
            <RunLevel>LeastPrivilege</RunLevel>
        </Principal>
    </Principals>
    <Settings>
        <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
        <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
        <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
        <AllowHardTerminate>true</AllowHardTerminate>
        <StartWhenAvailable>true</StartWhenAvailable>
        <WakeToRun>false</WakeToRun>
        <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    </Settings>
    <Actions Context="Author">
        <Exec>
            <Command>$exe</Command>
            <Arguments>$arguments</Arguments>
        </Exec>
    </Actions>
</Task>
"@
    try {
        if ($PSCmdlet.ShouldProcess($outPath, 'Create task XML file')) {
            [System.IO.File]::WriteAllText($outPath, $xml, [System.Text.Encoding]::Unicode)
            Write-SmartThemeLogFallback (Translate 'XML_CREATED' $outPath) 'DEBUG'
            return $true
        }
    }
    catch {
        Write-SmartThemeLogFallback (Translate 'XML_CREATE_FAIL' $outPath $_) 'ERROR'
        return $false
    }
}

function Import-SmartThemeTaskXml {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$xmlPath,
        [string]$taskName,
        [string]$SchtasksExe = 'schtasks.exe',
        [psobject]$Config = $null
    )
    if ($Config -and $Config.SchtasksExe) { $SchtasksExe = $Config.SchtasksExe }
    try {
        Write-SmartThemeLogFallback (Translate 'IMPORTING_XML' $xmlPath $taskName) 'DEBUG'
        if ($PSCmdlet.ShouldProcess($taskName, 'Import task XML (schtasks /Create /XML)')) {
            if (Get-Command -Name Import-TaskXml -ErrorAction SilentlyContinue) {
                if (Import-TaskXml -XmlPath $xmlPath -TaskName $taskName -SchtasksExe $SchtasksExe -Config $Config) {
                    Write-SmartThemeLogFallback (Translate 'IMPORT_XML_DONE' $taskName) 'INFO'
                    return $true
                }
            } else {
                $out = Invoke-Schtask -sArgs @('/Create','/TN',$taskName,'/XML',$xmlPath,'/F') -SchtasksExe $SchtasksExe
                $out | ForEach-Object { Write-SmartThemeLogFallback (Translate 'SCHTASKS_IMPORT' $_) }
                if ($LASTEXITCODE -eq 0) { Write-SmartThemeLogFallback (Translate 'IMPORT_XML_DONE' $taskName) 'INFO'; return $true }
            }
        }
    }
    catch {
        Write-SmartThemeLogFallback (Translate 'IMPORT_XML_ERROR' $_) 'ERROR'
    }
    return $false
}



function Set-LocationCache {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [double]$lat,
        [double]$lon,
        [string]$tz,
        [string]$city,
        [string]$sunriseUtc = $null,
        [string]$sunsetUtc = $null,
        [string]$dateStr = $null,
        [string]$CacheFile = $null,
        [string]$CacheDir = $null,
        [psobject]$Config = $null
    )
    # ensure parameters are referenced so static analysis knows they are used (some code paths use them dynamically)
    $dummy = "$lat|$lon|$tz|$city|$sunriseUtc|$sunsetUtc|$dateStr|$CacheFile|$CacheDir"
    $null = $dummy; $null = $Config
    # Parameterized save to avoid implicit script-level variables. If CacheFile/CacheDir
    # not supplied, fall back to sensible defaults under LOCALAPPDATA. Honor config overrides.
    if ($Config -and $Config.CacheDir) { $CacheDir = $Config.CacheDir }
    if ($Config -and $Config.CacheFile) { $CacheFile = $Config.CacheFile }
    if (-not $CacheDir) { $CacheDir = Join-Path $env:LOCALAPPDATA 'SmartTheme' }
    if (-not (Test-Path $CacheDir)) { New-Item -Path $CacheDir -ItemType Directory | Out-Null }
    if (-not $CacheFile) { $CacheFile = Join-Path $CacheDir 'location.json' }

    $obj = @{ latitude = $lat; longitude = $lon; timezone = $tz; city = $city; timestamp = (Get-Date).ToString('o') }
    if ($sunriseUtc) { $obj.sunriseUtc = $sunriseUtc }
    if ($sunsetUtc)  { $obj.sunsetUtc  = $sunsetUtc }
    if ($dateStr)    { $obj.date = $dateStr }
    $json = $obj | ConvertTo-Json
    if ($PSCmdlet.ShouldProcess($CacheFile, 'Write location cache')) {
        $json | Set-Content -Path $CacheFile -Encoding UTF8
    }
}

function Get-LocationCache([string]$CacheFile = $null, [string]$CacheDir = $null, [psobject]$Config = $null) {
    # Parameterized loader. If not provided, use defaults under LOCALAPPDATA. Honor config overrides.
    if ($Config -and $Config.CacheDir) { $CacheDir = $Config.CacheDir }
    if ($Config -and $Config.CacheFile) { $CacheFile = $Config.CacheFile }
    if (-not $CacheDir) { $CacheDir = Join-Path $env:LOCALAPPDATA 'SmartTheme' }
    if (-not $CacheFile) { $CacheFile = Join-Path $CacheDir 'location.json' }

    if (Test-Path $CacheFile) {
        try { return Get-Content $CacheFile -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

Export-ModuleMember -Function *
