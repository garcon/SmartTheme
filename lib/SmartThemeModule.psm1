function Test-IsElevated {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}

# Wrapper to execute schtasks.exe with splatted args. Allows mocking in tests.
function Invoke-Schtask([string[]]$sArgs, [string]$SchtasksExe = 'schtasks.exe') {
    try {
        return & $SchtasksExe @sArgs 2>&1
    } catch {
        return @($_)
    }
}

# Wrapper to execute cmd.exe /c "...". Allows mocking in tests.
function Invoke-Cmd([string]$cmdStr, [string]$CmdExe = 'cmd.exe') {
    try {
        return & $CmdExe /c $cmdStr 2>$null
    } catch {
        return @($_)
    }
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
    # Allow overriding via a config object for easier testing and DI
    if ($Config) {
        if ($Config.User) { $User = $Config.User }
        if ($Config.RunnerExe) { $RunnerExe = $Config.RunnerExe }
        if ($Config.SchtasksExe) { $SchtasksExe = $Config.SchtasksExe }
    }
    $st = $Time.ToString('HH:mm')
    $sd = $Time.ToString('MM\/dd\/yyyy')
    # Try creating task for given user with limited privileges
    $fullCmd = "$RunnerExe $cmd"
    if ($PSCmdlet.ShouldProcess($taskName, 'Create limited schtasks for current user')) {
        $out = Invoke-Schtask -sArgs @('/Create','/SC','ONCE','/TN',$taskName,'/TR',$fullCmd,'/ST',$st,'/SD',$sd,'/RL','LIMITED','/RU',$User,'/F') -SchtasksExe $SchtasksExe
        $out | ForEach-Object { Write-Log (Translate 'SCHTASKS_USER' $_) }
    }
    if ($LASTEXITCODE -eq 0) { return $true } else { return $false }
}

function Get-CurrentTheme {
    param(
        [string]$RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
        [psobject]$Config = $null
    )
    if ($Config -and $Config.RegPath) { $RegPath = $Config.RegPath }
    try {
        $appsTheme = Get-ItemPropertyValue -Path $RegPath -Name AppsUseLightTheme -ErrorAction Stop
        if ($appsTheme -eq 1) { 'Light' } else { 'Dark' }
    } catch { 'Unknown' }
}

function Set-Theme {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [string]$Mode,
        [string]$RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
        [psobject]$Config = $null
    )
    if ($Config -and $Config.RegPath) { $RegPath = $Config.RegPath }
    if ($Mode -eq 'Dark') {
        if ($PSCmdlet.ShouldProcess("Registry: $RegPath", 'Set AppsUseLightTheme/SystemUsesLightTheme to Dark')) {
            Set-ItemProperty -Path $RegPath -Name AppsUseLightTheme -Value 0 -Type DWord
            Set-ItemProperty -Path $RegPath -Name SystemUsesLightTheme -Value 0 -Type DWord
            Write-Log (Translate 'THEME_SWITCHED_DARK') 'SUCCESS'
        }
    }
    elseif ($Mode -eq 'Light') {
        if ($PSCmdlet.ShouldProcess("Registry: $RegPath", 'Set AppsUseLightTheme/SystemUsesLightTheme to Light')) {
            Set-ItemProperty -Path $RegPath -Name AppsUseLightTheme -Value 1 -Type DWord
            Set-ItemProperty -Path $RegPath -Name SystemUsesLightTheme -Value 1 -Type DWord
            Write-Log (Translate 'THEME_SWITCHED_LIGHT') 'SUCCESS'
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
    $cmdEnsure = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Ensure"

    $now = Get-Date
    if ($Time -lt $now) {
        Write-Log (Translate 'SCHEDULE_ADJUSTED_ADD_DAY' $Time $now)
        $Time = $Time.AddDays(1)
    }

    $scheduled = $false
    if (-not (Test-IsElevated)) {
        Write-Log (Translate 'NON_ELEVATED_ATTEMPT')
        try {
            if (Register-SmartThemeUserTask -taskName $taskName -cmd $cmdEnsure -Time $Time -User $User -RunnerExe $RunnerExe -SchtasksExe $SchtasksExe) {
                Write-Log (Translate 'SCHEDULED_USER_ENSURE' $($Time.ToString('yyyy-MM-dd HH:mm')) $User)
            } else {
                Write-Log (Translate 'SCHEDULE_USER_ONCE_FAILED')
            }

            $st = $Time.ToString('HH:mm')
            $sd = $Time.ToString('MM\/dd\/yyyy')
            $fullCmd = "$RunnerExe $cmdEnsure"
                if ($PSCmdlet.ShouldProcess($taskName + '-Startup', 'Create startup schtask for current user')) {
                    $out1 = Invoke-Schtask -sArgs @('/Create','/SC','ONSTART','/TN',"$taskName-Startup",'/TR',$fullCmd,'/F') -SchtasksExe $SchtasksExe
                    $out1 | ForEach-Object { Write-SmartThemeLog (Translate 'SCHTASKS_USER_STARTUP' $_) }
                }
                if ($PSCmdlet.ShouldProcess($taskName + '-Logon', 'Create logon schtask for current user')) {
                    $out2 = Invoke-Schtask -sArgs @('/Create','/SC','ONLOGON','/TN',"$taskName-Logon",'/TR',$fullCmd,'/F') -SchtasksExe $SchtasksExe
                    $out2 | ForEach-Object { Write-SmartThemeLog (Translate 'SCHTASKS_USER_LOGON' $_) }
                }
            return $true
        }
        catch {
            Write-Log (Translate 'NON_ELEVATED_ERROR' $_)
        }
    }

    try {
    $backupXml = Join-Path $TempDir "$taskName-backup.xml"
    Export-SmartThemeTaskXml -taskName $taskName -outPath $backupXml -SchtasksExe $SchtasksExe | Out-Null
            if ($PSCmdlet.ShouldProcess($taskName, 'Unregister existing scheduled task')) {
                Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            }

        if (Test-IsElevated) {
            $xmlPath = Join-Path $TempDir "$taskName.xml"
            $exe = $RunnerExe
            $arguments = $cmdEnsure
            if (New-SmartThemeTaskXml -taskName $taskName -exe $exe -arguments $arguments -startTime $Time -outPath $xmlPath) {
                    if ($PSCmdlet.ShouldProcess($taskName, 'Import task XML into scheduled tasks')) {
                        if (Import-SmartThemeTaskXml -xmlPath $xmlPath -taskName $taskName -SchtasksExe $SchtasksExe) {
                    Write-Log (Translate 'SCHEDULE_XML_SCHEDULED' $($Time.ToString('yyyy-MM-dd HH:mm'))) 'INFO'
                    $scheduled = $true
                    return $scheduled
                } else {
                    Write-Log (Translate 'IMPORT_XML_FAILED') 'WARN'
                }
                    }
            }
        }

    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries
    $action = New-ScheduledTaskAction -Execute $RunnerExe -Argument $cmdEnsure
        $triggerOnce = New-ScheduledTaskTrigger -Once -At $Time
        $triggerStartup = New-ScheduledTaskTrigger -AtStartup
        $triggerLogon = New-ScheduledTaskTrigger -AtLogOn
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerOnce,$triggerStartup,$triggerLogon) -Settings $settings -Force -ErrorAction Stop
        Write-Log (Translate 'SCHEDULED_API' $($Time.ToString('yyyy-MM-dd HH:mm')))
        Write-Log (Translate 'SCHEDULE_SETTINGS_INFO') 'INFO'
        $scheduled = $true
        return $scheduled
    }
    catch {
        Write-Log (Translate 'SCHEDULE_API_FAILED' $_)
    }

    try {
    $st = $Time.ToString('HH:mm')
    $sd = $Time.ToString('MM\/dd\/yyyy')
    Invoke-Schtask -sArgs @('/Delete','/TN',$taskName,'/F') -SchtasksExe $SchtasksExe | Out-Null
    $out = Invoke-Schtask -sArgs @('/Create','/SC','ONCE','/TN',$taskName,'/TR',"$RunnerExe $cmdEnsure",'/ST',$st,'/SD',$sd,'/F') -SchtasksExe $SchtasksExe
    $out | ForEach-Object { Write-Log (Translate 'SCHTASKS_OUT' $_) }
        if ($LASTEXITCODE -eq 0) {
            Write-Log (Translate 'SCHTASKS_SCHEDULED' $($Time.ToString('yyyy-MM-dd HH:mm')) $sd $st)
            Write-Log (Translate 'SCHTASKS_FALLBACK_NOTE') 'INFO'
            $scheduled = $true
        } else {
            Write-Log (Translate 'SCHTASKS_EXITCODE' $LASTEXITCODE)
        }

    $outS = Invoke-Schtask -sArgs @('/Create','/SC','ONSTART','/TN',"$taskName-Startup",'/TR',"$RunnerExe $cmdEnsure",'/F') -SchtasksExe $SchtasksExe
    $outS | ForEach-Object { Write-Log (Translate 'SCHTASKS_STARTUP_OUT' $_) }
    $outL = Invoke-Schtask -sArgs @('/Create','/SC','ONLOGON','/TN',"$taskName-Logon",'/TR',"$RunnerExe $cmdEnsure",'/F') -SchtasksExe $SchtasksExe
    $outL | ForEach-Object { Write-Log (Translate 'SCHTASKS_LOGON_OUT' $_) }

        return $scheduled
    }
    catch {
        Write-Log (Translate 'SCHEDULE_ERROR' $_)
        return $false
    }
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
    if ($Config) {
        if ($Config.CmdExe) { $CmdExe = $Config.CmdExe }
        if ($Config.SchtasksExe) { $SchtasksExe = $Config.SchtasksExe }
    }
    try {
        $cmd = "$SchtasksExe /Query /TN `"$taskName`" /XML"
        Write-Log (Translate 'EXPORT_TASK' $taskName $outPath) 'DEBUG'
        if ($PSCmdlet.ShouldProcess($outPath, 'Export scheduled task XML')) {
            & $CmdExe /c "$cmd > `"$outPath`"" 2>$null
            if (Test-Path $outPath) { Write-Log (Translate 'EXPORT_TASK_DONE' $outPath) 'DEBUG'; return $true }
        }
    }
    catch {
        Write-Log (Translate 'EXPORT_TASK_FAIL' $taskName $_) 'WARN'
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
            Write-Log (Translate 'XML_CREATED' $outPath) 'DEBUG'
            return $true
        }
    }
    catch {
        Write-Log (Translate 'XML_CREATE_FAIL' $outPath $_) 'ERROR'
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
        Write-Log (Translate 'IMPORTING_XML' $xmlPath $taskName) 'DEBUG'
        if ($PSCmdlet.ShouldProcess($taskName, 'Import task XML (schtasks /Create /XML)')) {
        $out = Invoke-Schtask -sArgs @('/Create','/TN',$taskName,'/XML',$xmlPath,'/F') -SchtasksExe $SchtasksExe
            $out | ForEach-Object { Write-Log (Translate 'SCHTASKS_IMPORT' $_) }
            if ($LASTEXITCODE -eq 0) { Write-Log (Translate 'IMPORT_XML_DONE' $taskName) 'INFO'; return $true }
        }
    }
    catch {
        Write-Log (Translate 'IMPORT_XML_ERROR' $_) 'ERROR'
    }
    return $false
}

function Invoke-RestWithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$maxAttempts = 3,
        [int]$baseDelay = 2
    )
    for ($i = 1; $i -le $maxAttempts; $i++) {
        try {
            return & $ScriptBlock
        }
        catch {
            if ($i -eq $maxAttempts) { throw }
            $delay = [int]($baseDelay * [math]::Pow(2, $i - 1))
            Write-Log (Translate 'RETRY_WAIT' $delay $i $maxAttempts) 'DEBUG'
            Start-Sleep -Seconds $delay
        }
    }
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
