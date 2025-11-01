<#
.SYNOPSIS
    Přepíná světlý/tmavý režim Windows 11 podle času východu a západu slunce.
.DESCRIPTION
    - Bez parametru → přepne (toggle) mezi světlým a tmavým režimem a naplánuje další přepnutí.
    - -Dark → nastaví tmavý režim a naplánuje přepnutí na světlý.
    - -Light → nastaví světlý režim a naplánuje přepnutí na tmavý.
    - -Schedule → pouze aktualizuje plán přepnutí podle aktuální polohy (bez změny režimu).
#>

param(
    [switch]$Dark,
    [switch]$Light,
    [switch]$Schedule
    ,[switch]$Debug
    ,[double]$Lat
    ,[double]$Lon
    ,[switch]$Ensure
)

$ErrorActionPreference = 'Stop'

# Script-level debug flag (use script: scope so functions can read it)
$script:ShowDebug = $false
if ($PSBoundParameters.ContainsKey('Debug')) { $script:ShowDebug = $true }
# --- Zjištění aktuální cesty skriptu -------------------------------------------
$ScriptPath = (Resolve-Path $MyInvocation.MyCommand.Path).Path
# Cache & log file (cacheDir must exist before using log)
$cacheDir = Join-Path $env:LOCALAPPDATA 'SmartTheme'
$cacheFile = Join-Path $cacheDir 'location.json'
$logDir = $cacheDir
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory | Out-Null }
$logFile = Join-Path $logDir 'smarttheme.log'

function Write-Log {
    param(
        [string]$msg,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG')][string]$Level = 'INFO'
    )
    $line = "$(Get-Date -Format o) - $msg"

    # Map level to color
    switch ($Level) {
        'INFO'    { $color = 'White' }
        'WARN'    { $color = 'Yellow' }
        'ERROR'   { $color = 'Red' }
        'SUCCESS' { $color = 'Green' }
        'DEBUG'   { $color = 'DarkGray' }
        default   { $color = 'White' }
    }

    # If DEBUG level and debug not enabled, only write to the log file and skip console output
    if ($Level -eq 'DEBUG' -and -not $script:ShowDebug) {
        try { $line | Out-File -FilePath $logFile -Append -Encoding UTF8 } catch {}
        Trim-LogFile -Path $logFile -Lines 100
        return
    }

    try { Write-Host $line -ForegroundColor $color } catch { Write-Output $line }
    try { $line | Out-File -FilePath $logFile -Append -Encoding UTF8 } catch {}
    Trim-LogFile -Path $logFile -Lines 100
}

# Trim log helper (top-level so it's not recreated on every log write)
function Trim-LogFile {
    param(
        [string]$Path,
        [int]$Lines = 100
    )
    try {
        $tail = Get-Content -Path $Path -Tail $Lines -ErrorAction SilentlyContinue
        if ($tail) { $tail | Set-Content -Path $Path -Encoding UTF8 }
    } catch {
        # Best-effort: ignore trimming failures
    }
}

function Test-IsElevated {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([System.Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}

function Schtasks-CreateForCurrentUser($taskName, $cmd, [datetime]$Time) {
    $st = $Time.ToString('HH:mm')
    $sd = $Time.ToString('MM\/dd\/yyyy')
    # Try creating task for current user with limited privileges
    $user = $env:USERNAME
    $fullCmd = "powershell.exe $cmd"
    $out = schtasks.exe /Create /SC ONCE /TN $taskName /TR "$fullCmd" /ST $st /SD $sd /RL LIMITED /RU "$user" /F 2>&1
    $out | ForEach-Object { Write-Log "schtasks-user: $_" }
    if ($LASTEXITCODE -eq 0) { return $true } else { return $false }
}

Write-Log "Skript běží z: $ScriptPath" 'INFO'

# --- Pomocné funkce -------------------------------------------------------------
function Get-CurrentTheme {
    $RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    try {
        $appsTheme = Get-ItemPropertyValue -Path $RegPath -Name AppsUseLightTheme -ErrorAction Stop
    if ($appsTheme -eq 1) { 'Light' } else { 'Dark' }
    } catch { 'Unknown' }
}

function Set-Theme([string]$Mode) {
    $RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    if ($Mode -eq 'Dark') {
        Set-ItemProperty -Path $RegPath -Name AppsUseLightTheme -Value 0 -Type DWord
    Set-ItemProperty -Path $RegPath -Name SystemUsesLightTheme -Value 0 -Type DWord
    Write-Log 'Přepnuto na tmavý režim.' 'SUCCESS'
    }
    elseif ($Mode -eq 'Light') {
        Set-ItemProperty -Path $RegPath -Name AppsUseLightTheme -Value 1 -Type DWord
    Set-ItemProperty -Path $RegPath -Name SystemUsesLightTheme -Value 1 -Type DWord
    Write-Log 'Přepnuto na světlý režim.' 'SUCCESS'
    }
}

function Schedule-ThemeSwitch([string]$Mode, [datetime]$Time, [string]$ScriptPath) {
    $taskName = "SmartThemeSwitch-$Mode"
    # Use an "ensure" invocation for scheduled tasks so that any missed run
    # will recompute which theme *should* be active and apply it.
    # We intentionally DO NOT set WakeToRun — user requested not to wake the PC.
    $cmdEnsure = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Ensure"

    # Pokud je čas v minulosti, posuneme o 1 den
    $now = Get-Date
    if ($Time -lt $now) {
        Write-Log "Upravuji čas plánování ($Time) protože je dřívější než nyní ($now). Přidávám 1 den."
        $Time = $Time.AddDays(1)
    }

    # Pokud nejsme elevated, nejdříve zkusíme vytvořit úlohu pro aktuálního uživatele (bez elevace).
    # Create three related triggers/tasks: once (scheduled time) + AtStartup + AtLogOn as a fallback
    $scheduled = $false
    if (-not (Test-IsElevated)) {
        Write-Log "Proces běží bez administrátorských práv — pokusím se vytvořit úlohu pro aktuálního uživatele bez elevace."
        try {
            # create the ONCE variant using the ensure invocation
            if (Schtasks-CreateForCurrentUser -taskName $taskName -cmd $cmdEnsure -Time $Time) {
                Write-Log "Naplánováno (schtasks-user) ensure v $($Time.ToString('yyyy-MM-dd HH:mm')) (pro uživatele $env:USERNAME)"
            } else {
                Write-Log "Vytvoření ONCE úlohy pro aktuálního uživatele selhalo; budu pokračovat s API/fallbackem."
            }

            # Create ONSTART and ONLOGON fallback tasks for the same ensure action
            $st = $Time.ToString('HH:mm')
            $sd = $Time.ToString('MM\/dd\/yyyy')
            $fullCmd = "powershell.exe $cmdEnsure"
            $out1 = schtasks.exe /Create /SC ONSTART /TN "$taskName-Startup" /TR "$fullCmd" /F 2>&1
            $out1 | ForEach-Object { Write-Log "schtasks-user-startup: $_" }
            $out2 = schtasks.exe /Create /SC ONLOGON /TN "$taskName-Logon" /TR "$fullCmd" /F 2>&1
            $out2 | ForEach-Object { Write-Log "schtasks-user-logon: $_" }
            return $true
        }
        catch {
            Write-Log "Chyba při non-elevated schtasks: $_"
        }
    }

    # Nejprve se pokusíme použít Register-ScheduledTask (bez nutnosti string date formátu)
    try {
        # Backup existing task XML (if any) before unregistering
        $backupXml = Join-Path $env:TEMP "$taskName-backup.xml"
        Export-TaskXml -taskName $taskName -outPath $backupXml | Out-Null
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

        # If elevated, prefer creating/importing a full XML definition for precise settings
        if (Test-IsElevated) {
            $xmlPath = Join-Path $env:TEMP "$taskName.xml"
            $exe = 'powershell.exe'
            $arguments = $cmdEnsure
            if (Create-RecommendTaskXml -taskName $taskName -exe $exe -arguments $arguments -startTime $Time -outPath $xmlPath) {
                if (Import-TaskXml -xmlPath $xmlPath -taskName $taskName) {
                    Write-Log "Naplánováno (XML import) ensure/once+startup+logon v $($Time.ToString('yyyy-MM-dd HH:mm'))" 'INFO'
                    $scheduled = $true
                    return $scheduled
                } else {
                    Write-Log "Import XML selhal; budu zkoušet Register-ScheduledTask fallback." 'WARN'
                }
            }
        }

        # Settings: run as soon as possible if missed, but DO NOT wake the machine
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $cmdEnsure
        $triggerOnce = New-ScheduledTaskTrigger -Once -At $Time
        $triggerStartup = New-ScheduledTaskTrigger -AtStartup
        $triggerLogon = New-ScheduledTaskTrigger -AtLogOn
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($triggerOnce,$triggerStartup,$triggerLogon) -Settings $settings -Force -ErrorAction Stop
        Write-Log "Naplánováno (ScheduledTasks) ensure/once+startup+logon v $($Time.ToString('yyyy-MM-dd HH:mm'))"
        Write-Log "Poznámka: úloha je vytvořena s 'StartWhenAvailable' (spustí se co nejdříve, pokud byla start vynechán). WakeToRun je VYPNUTO (počítač se nebude probouzet)." 'INFO'
        $scheduled = $true
        return $scheduled
    }
    catch {
        Write-Log "ScheduledTasks API selhalo: $_. Pokus o fallback na schtasks.exe"
    }

    # Fallback: použít schtasks (stále s explicitním SD)
    try {
        $st = $Time.ToString('HH:mm')
        $sd = $Time.ToString('MM\/dd\/yyyy')
        schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
        # Create ONCE ensure task
        $out = schtasks.exe /Create /SC ONCE /TN $taskName /TR "powershell.exe $cmdEnsure" /ST $st /SD $sd /F 2>&1
        $out | ForEach-Object { Write-Log "schtasks: $_" }
        if ($LASTEXITCODE -eq 0) {
            Write-Log "Naplánováno (schtasks) ensure/once v $($Time.ToString('yyyy-MM-dd HH:mm')) (SD=$sd ST=$st)"
            Write-Log "Poznámka: fallback úloha ONCE byla vytvořena; také jsem vytvořil fallback ONSTART a ONLOGON úlohy, které spustí kontrolu (neprobouzet počítač)." 'INFO'
            $scheduled = $true
        } else {
            Write-Log "schtasks vracelo kód $LASTEXITCODE při vytváření ONCE úlohy."
        }

        # Also create ONSTART and ONLOGON fallback tasks (they run the ensure invocation too)
        $outS = schtasks.exe /Create /SC ONSTART /TN "$taskName-Startup" /TR "powershell.exe $cmdEnsure" /F 2>&1
        $outS | ForEach-Object { Write-Log "schtasks-startup: $_" }
        $outL = schtasks.exe /Create /SC ONLOGON /TN "$taskName-Logon" /TR "powershell.exe $cmdEnsure" /F 2>&1
        $outL | ForEach-Object { Write-Log "schtasks-logon: $_" }

        return $scheduled
    }
    catch {
        Write-Log "Chyba při plánování úlohy: $_"
        return $false
    }
}

# --- XML helpers for advanced task import/export (used when elevated) ----------
function Export-TaskXml($taskName, $outPath) {
        try {
                $cmd = "schtasks /Query /TN `"$taskName`" /XML"
                Write-Log "Exportuji existující úlohu $taskName do $outPath (pokud existuje)..." 'DEBUG'
                # Use cmd.exe to redirect output reliably
                cmd.exe /c "$cmd > `"$outPath`"" 2>$null
                if (Test-Path $outPath) { Write-Log "Export úlohy do $outPath dokončen." 'DEBUG'; return $true }
        }
        catch {
                Write-Log "Nelze exportovat úlohu ${taskName}: $_" 'WARN'
        }
        return $false
}

function Create-RecommendTaskXml($taskName, $exe, $arguments, [datetime]$startTime, $outPath) {
        $startBoundary = $startTime.ToString('yyyy-MM-ddTHH:mm:ss')
        $xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
    <RegistrationInfo>
        <Author>SmartTheme</Author>
        <Description>SmartTheme ensure task - auto-generated</Description>
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
                # Write as UTF-16 (Unicode) which Task Scheduler expects
                [System.IO.File]::WriteAllText($outPath, $xml, [System.Text.Encoding]::Unicode)
                Write-Log "Vytvořeno doporučené XML pro úlohu: $outPath" 'DEBUG'
                return $true
        }
        catch {
                Write-Log "Nelze vytvořit XML soubor ${outPath}: $_" 'ERROR'
                return $false
        }
}

function Import-TaskXml($xmlPath, $taskName) {
        try {
                Write-Log "Importuji úlohu z XML $xmlPath jako $taskName..." 'DEBUG'
                $out = schtasks.exe /Create /TN $taskName /XML $xmlPath /F 2>&1
                $out | ForEach-Object { Write-Log "schtasks-import: $_" }
                if ($LASTEXITCODE -eq 0) { Write-Log "Import XML úlohy $taskName dokončen." 'INFO'; return $true }
        }
        catch {
                Write-Log "Chyba při importu XML úlohy: $_" 'ERROR'
        }
        return $false
}

# --- Retry + cache helpery -----------------------------------------------------
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
            Write-Log "Počkáme $delay s před dalším pokusem... (pokusu $i/$maxAttempts)" 'DEBUG'
            Start-Sleep -Seconds $delay
        }
    }
}
function Save-LocationCache($lat, $lon, $tz, $city, [string]$sunriseUtc=$null, [string]$sunsetUtc=$null, [string]$dateStr=$null) {
    if (-not (Test-Path $cacheDir)) { New-Item -Path $cacheDir -ItemType Directory | Out-Null }
    $obj = @{ latitude = $lat; longitude = $lon; timezone = $tz; city = $city; timestamp = (Get-Date).ToString('o') }
    if ($sunriseUtc) { $obj.sunriseUtc = $sunriseUtc }
    if ($sunsetUtc)  { $obj.sunsetUtc  = $sunsetUtc }
    if ($dateStr)    { $obj.date = $dateStr }
    $obj | ConvertTo-Json | Set-Content -Path $cacheFile -Encoding UTF8
}

function Load-LocationCache {
    if (Test-Path $cacheFile) {
        try { return Get-Content $cacheFile -Raw | ConvertFrom-Json } catch { return $null }
    }
    return $null
}

# --- IANA -> Windows timezone resolver ---------------------------------------
function Resolve-TimeZone([string]$tz) {
    if (-not $tz) { throw 'Timezone string is empty' }

    # Try direct Windows ID first
    try {
        [void][System.TimeZoneInfo]::FindSystemTimeZoneById($tz)
        return $tz
    } catch { }

    # Common IANA -> Windows map (extendable)
    $ianaToWindows = @{
        'Europe/Prague' = 'Central Europe Standard Time'
        'Europe/Bratislava' = 'Central Europe Standard Time'
        'Europe/Berlin' = 'W. Europe Standard Time'
        'Europe/Amsterdam' = 'W. Europe Standard Time'
        'Europe/Rome' = 'W. Europe Standard Time'
        'Europe/London' = 'GMT Standard Time'
        'UTC' = 'UTC'
        'Europe/Madrid' = 'Romance Standard Time'
        'America/New_York' = 'Eastern Standard Time'
        'America/Detroit' = 'Eastern Standard Time'
        'America/Chicago' = 'Central Standard Time'
        'America/Denver' = 'Mountain Standard Time'
        'America/Los_Angeles' = 'Pacific Standard Time'
    }

    if ($ianaToWindows.ContainsKey($tz)) { return $ianaToWindows[$tz] }

    # Fuzzy search: try matching last segment of IANA id against display names
    $parts = $tz -split '/'
    $needle = $parts[-1].Replace('_',' ')
    foreach ($s in [System.TimeZoneInfo]::GetSystemTimeZones()) {
        if ($s.Id -like "*$needle*" -or $s.DisplayName -like "*$needle*") { return $s.Id }
    }

    throw "Nelze převést timezone '$tz' na Windows timezone ID."
}

# --- 1️⃣ Získání aktuální polohy ----------------------------------------------
Write-Log 'Zjišťuji aktuální polohu...' 'INFO'

# Pokud uživatel zadal manuální souřadnice, použijeme je přímo
if ($PSBoundParameters.ContainsKey('Lat') -and $PSBoundParameters.ContainsKey('Lon')) {
    $lat = $Lat
    $lon = $Lon
    $tz  = [System.TimeZoneInfo]::Local.Id
    $city = '(manually provided)'
    Write-Log "Použity manuální souřadnice: $lat, $lon" 'INFO'
}
else {
    try {
        $loc = Invoke-RestWithRetry { Invoke-RestMethod 'https://ipapi.co/json/' }
        $lat = $loc.latitude
        $lon = $loc.longitude
        $tz  = $loc.timezone
        $city = $loc.city
    Write-Log "Místo: $city ($lat, $lon) [$tz]"
    try { Save-LocationCache $lat $lon $tz $city } catch { Write-Log 'Nelze uložit cache polohy: ' + $_ }
    }
    catch {
    Write-Log 'Varování: Nepodařilo se zjistit polohu přes ipapi.'
        $cached = Load-LocationCache
        if ($cached) {
            $lat = $cached.latitude
            $lon = $cached.longitude
            $tz  = $cached.timezone
            $city = $cached.city
            Write-Log "Použita cache: $city ($lat, $lon) [$tz]"
        }
        else {
            # Poslední záloha: Praha (CZ)
            $lat = 50.0755
            $lon = 14.4378
            $tz  = [System.TimeZoneInfo]::Local.Id
            $city = 'Prague (fallback)'
            Write-Log 'Upozornění: Nebyla nalezena žádná poloha ani cache. Používám záložní souřadnice Prahy (CZ).'
        }
    }
}

# --- 2️⃣ Získání časů východu a západu slunce ----------------------------------
Write-Log 'Načítám časy východu a západu slunce...' 'INFO'
try {
    $latStr = $lat.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $lonStr = $lon.ToString([System.Globalization.CultureInfo]::InvariantCulture)

    $url = "https://api.sunrise-sunset.org/json?lat=$latStr&lng=$lonStr&formatted=0"
    Write-Log "Volám API: $url" 'DEBUG'

    $sun = Invoke-RestWithRetry { Invoke-RestMethod -Uri $url -UseBasicParsing }
    Write-Log "Stav odpovědi: $($sun.status)" 'DEBUG'

    if ($sun.status -ne 'OK') { throw "API vrátilo chybu: $($sun.status)" }

    # Parse UTC times
    try {
        $sunriseDto = [datetimeoffset]::Parse($sun.results.sunrise, [System.Globalization.CultureInfo]::InvariantCulture)
        $sunsetDto  = [datetimeoffset]::Parse($sun.results.sunset,  [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        # Could be polar day/night or unexpected format
        Write-Log "Nelze parsovat výsledky API (pravděpodobně polární den/noc nebo neplatné hodnoty): $_" 'WARN'
        throw
    }

    $sunriseUTC = $sunriseDto.UtcDateTime
    $sunsetUTC  = $sunsetDto.UtcDateTime
    Write-Log "UTC sunrise: $sunriseUTC (Kind=$($sunriseUTC.Kind))" 'DEBUG'
    Write-Log "UTC sunset : $sunsetUTC (Kind=$($sunsetUTC.Kind))" 'DEBUG'

    try {
        $windowsTzId = Resolve-TimeZone $tz
        Write-Log "Používám Windows timezone ID: $windowsTzId (původně: $tz)" 'DEBUG'
        $tzinfo = [System.TimeZoneInfo]::FindSystemTimeZoneById($windowsTzId)
    }
    catch {
        Write-Log "Varování: Nelze převést timezone '$tz' na Windows ID: $_. Používám lokální časovou zónu místo toho." 'WARN'
        $tzinfo = [System.TimeZoneInfo]::Local
    }

    # Convert to local tz
    $sunrise = [System.TimeZoneInfo]::ConvertTimeFromUtc($sunriseUTC, $tzinfo)
    $sunset  = [System.TimeZoneInfo]::ConvertTimeFromUtc($sunsetUTC,  $tzinfo)

    $now = Get-Date
    $dateUsed = (Get-Date).ToString('yyyy-MM-dd')

    # If any event already passed today, query API once for tomorrow (both times)
    if ($sunrise -lt $now -or $sunset -lt $now) {
        Write-Log "Jedna nebo více událostí už dnes proběhlo (sunrise=$sunrise, sunset=$sunset). Dotazuji se na zítřejší časy..." 'DEBUG'
        try {
            $dateStr = $now.AddDays(1).ToString('yyyy-MM-dd')
            $url2 = "https://api.sunrise-sunset.org/json?lat=$latStr&lng=$lonStr&formatted=0&date=$dateStr"
            Write-Log "Volám API (next day): $url2" 'DEBUG'
            $sun2 = Invoke-RestWithRetry { Invoke-RestMethod -Uri $url2 -UseBasicParsing }
            if ($sun2.status -eq 'OK') {
                $sunriseDto2 = [datetimeoffset]::Parse($sun2.results.sunrise, [System.Globalization.CultureInfo]::InvariantCulture)
                $sunsetDto2  = [datetimeoffset]::Parse($sun2.results.sunset,  [System.Globalization.CultureInfo]::InvariantCulture)
                $sunriseUTC = $sunriseDto2.UtcDateTime
                $sunsetUTC  = $sunsetDto2.UtcDateTime
                $sunrise = [System.TimeZoneInfo]::ConvertTimeFromUtc($sunriseUTC, $tzinfo)
                $sunset  = [System.TimeZoneInfo]::ConvertTimeFromUtc($sunsetUTC,  $tzinfo)
                $dateUsed = $dateStr
                Write-Log "Nové lokální časy (zítřek) — sunrise: $sunrise; sunset: $sunset" 'DEBUG'
            }
            else {
                Write-Log "Nepodařilo se získat zítřejší časy: $($sun2.status)" 'WARN'
            }
        }
        catch {
            Write-Log "Chyba při dotazu na zítřejší časy: $_" 'WARN'
        }
    }

    # Save to cache (store UTC times and the date they correspond to)
    try { Save-LocationCache $lat $lon $tz $city $sunriseUTC.ToString('o') $sunsetUTC.ToString('o') $dateUsed } catch { Write-Log "Nelze uložit cached sun times: $_" 'WARN' }

    Write-Log "Lokální čas východu: $sunrise" 'INFO'
    Write-Log "Lokální čas západu : $sunset" 'INFO'

}
catch {
    Write-Log "Varování: Nepodařilo se získat časy slunce z API nebo nastal problém při parsování: $_" 'WARN'
    # Pokusíme se použít cache se sun-times pokud existuje
    $cached = Load-LocationCache
    if ($cached -and $cached.sunriseUtc -and $cached.sunsetUtc -and $cached.date) {
        try {
            Write-Log "Používám cacheované časy slunce (datum $($cached.date))." 'INFO'
            $cachedSunriseUtc = [datetime]::Parse($cached.sunriseUtc, [System.Globalization.CultureInfo]::InvariantCulture)
            $cachedSunsetUtc  = [datetime]::Parse($cached.sunsetUtc,  [System.Globalization.CultureInfo]::InvariantCulture)

            try { $windowsTzId = Resolve-TimeZone $cached.timezone } catch { $windowsTzId = [System.TimeZoneInfo]::Local.Id }
            try { $tzinfo = [System.TimeZoneInfo]::FindSystemTimeZoneById($windowsTzId) } catch { $tzinfo = [System.TimeZoneInfo]::Local }

            # Convert cached UTCs to local
            $sunrise = [System.TimeZoneInfo]::ConvertTimeFromUtc($cachedSunriseUtc, $tzinfo)
            $sunset  = [System.TimeZoneInfo]::ConvertTimeFromUtc($cachedSunsetUtc,  $tzinfo)

            # If cached times are in the past, shift forward by whole days until in future (limit to 7 days)
            $now = Get-Date
            $attempts = 0
            while (($sunrise -lt $now -and $sunset -lt $now) -and $attempts -lt 7) {
                $sunrise = $sunrise.AddDays(1)
                $sunset  = $sunset.AddDays(1)
                $attempts++
            }

            if ($sunrise -lt $now -and $sunset -lt $now) {
                Write-Log "Cacheované časy jsou stále v minulosti i po posunu. Naplánuji znovu spuštění skriptu zítra pro pokus o opětovné naplánování." 'WARN'
                # Naplánujeme znovu spuštění skriptu na zítřejší 03:00
                $retryTime = (Get-Date).Date.AddDays(1).AddHours(3)
                $retryCmd = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Schedule"
                if (Schtasks-CreateForCurrentUser -taskName 'SmartThemeRetry' -cmd $retryCmd -Time $retryTime) {
                    Write-Log "Naplánováno zítřejší opětovné spuštění pro kontrolu (SmartThemeRetry) v $($retryTime)" 'INFO'
                } else {
                    Write-Log "Nepodařilo se naplánovat opětovné spuštění (SmartThemeRetry)." 'WARN'
                }
                # Don't change scheduling now
                exit 0
            }

            Write-Log "Používám cacheované (posunuté) časy: východ=$sunrise, západ=$sunset" 'INFO'
        }
        catch {
            Write-Log "Chyba při použití cache: $_" 'WARN'
            Write-Log "Chyba při získávání časů slunce: $_" 'ERROR'
            exit 1
        }
    }
    else {
        Write-Log "Žádná vhodná cache nebyla nalezena. Nelze pokračovat." 'ERROR'
        exit 1
    }
}

# --- 3️⃣ Logika přepnutí -------------------------------------------------------
$now = Get-Date
$current = Get-CurrentTheme
$target  = $null

if ($Schedule) {
    Write-Log '-Schedule: pouze aktualizuji plán.' 'INFO'
    $target = $current
}
elseif ($Dark) {
    $target = 'Dark'
}
elseif ($Light) {
    $target = 'Light'
}
else {
    if ($current -eq 'Light') { $target = 'Dark' }
    elseif ($current -eq 'Dark') { $target = 'Light' }
    else {
        Write-Log 'Chyba: Nelze určit aktuální režim.' 'ERROR'
        exit 1
    }
}

if (-not $Schedule) {
    Write-Log "Aktuální režim: $current → Nový režim: $target" 'INFO'
    Set-Theme $target
}
else {
    Write-Log 'Režim se nemění (Schedule mód).' 'INFO'
}

# --- 4️⃣ Naplánování dalšího přepnutí ------------------------------------------
if ($target -eq 'Light') {
    if ($sunset -lt $now) {
        # Pokud je západ i po zítřejším dotazu v minulosti (nepravděpodobné), použijeme AddDays(1) jako poslední záchranu
        Write-Log "Západ slunce je stále v minulosti ($sunset) — přidávám 1 den jako poslední opatření." 'WARN'
        $sunset = $sunset.AddDays(1)
    }
    $scheduleOk = Schedule-ThemeSwitch -Mode 'Dark' -Time $sunset -ScriptPath $ScriptPath
}
else {
    if ($sunrise -lt $now) {
        # Pokud je východ i po zítřejším dotazu v minulosti (nepravděpodobné), použijeme AddDays(1) jako poslední záchranu
        Write-Log "Východ slunce je stále v minulosti ($sunrise) — přidávám 1 den jako poslední opatření." 'WARN'
        $sunrise = $sunrise.AddDays(1)
    }
    $scheduleOk = Schedule-ThemeSwitch -Mode 'Light' -Time $sunrise -ScriptPath $ScriptPath
}
if ($scheduleOk) {
    Write-Log 'Hotovo. Další přepnutí bylo naplánováno.'
} else {
    $msg = "Hotovo. ALE: Nepodařilo se vytvořit plánovanou úlohu (pravděpodobně nedostatečná oprávnění)."
    Write-Log $msg

    # Instrukce pro spuštění jako správce
    $elevCmd = "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Schedule' -Verb RunAs"
    Write-Log "Instrukce pro spuštění elevated (spustí nové okno PowerShell s UAC prompt):"
    Write-Log "  $elevCmd"

    # Návod pro ruční vytvoření úlohy přes schtasks (příklad)
    $exampleMode = if ($target -eq 'Light') { 'Light' } else { 'Dark' }
    $exampleTime = if ($target -eq 'Light') { $sunrise } else { $sunset }
    $sd = $exampleTime.ToString('MM\/dd\/yyyy')
    $st = $exampleTime.ToString('HH:mm')
    $escapedScript = $ScriptPath -replace '"','\"'
    $schtasksCmd = 'schtasks /Create /SC ONCE /TN "SmartThemeSwitch-' + $exampleMode + '" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $escapedScript + '" -' + $exampleMode + '" /ST ' + $st + ' /SD ' + $sd + ' /F'
    Write-Log "Příklad příkazu pro ruční vytvoření (spusť jako administrátor):"
    Write-Log "  $schtasksCmd"

    Write-Log "Pokud chceš, spusť výše uvedený Start-Process příkaz nebo otevři PowerShell jako správce a spusť skript znovu s -Schedule."
}
