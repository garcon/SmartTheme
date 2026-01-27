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

# Ensure console and PowerShell output use UTF-8 so elevated windows display diacritics correctly
try {
    $utf8Enc = [System.Text.Encoding]::UTF8
    try { [Console]::OutputEncoding = $utf8Enc } catch { Write-Verbose 'Could not set Console OutputEncoding (non-fatal).' }
    try { [Console]::InputEncoding  = $utf8Enc } catch { Write-Verbose 'Could not set Console InputEncoding (non-fatal).' }
    try { $OutputEncoding = $utf8Enc } catch { Write-Verbose 'Could not set PowerShell $OutputEncoding (non-fatal).' }
} catch {
    # Best-effort only; non-fatal if platform doesn't allow
    Write-Verbose 'Could not configure UTF-8 encodings (non-fatal).'
}

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
# Mark logFile as intentionally present for other modules
$null = $logFile

# Central config object for dependency injection / testing
# (initialized after determining the `lib` directory)

# Dot-source library helpers (logging, timezone) from ./lib
$scriptDir = Split-Path $ScriptPath -Parent
# Dot-source library helpers (localization, logging, timezone) from ./lib
$libDir = Join-Path $scriptDir 'lib'
. (Join-Path $libDir 'Localization.ps1')
# Initialize localization (sets $script:PreferredLocale and $script:LocaleData)
Set-Localization
 $loggingModule = Join-Path $libDir 'LoggingModule.psm1'
 if (Test-Path $loggingModule) { Import-Module $loggingModule -Force -ErrorAction Stop }
. (Join-Path $libDir 'TimeZoneHelpers.ps1')
# Central config object for dependency injection / testing
$configModule = Join-Path $libDir 'Config.psm1'
if (Test-Path $configModule) { Import-Module $configModule -Force -ErrorAction Stop }
$Config = Get-DefaultConfig @{ CacheDir = $cacheDir; CacheFile = $cacheFile; User = $env:USERNAME; TempDir = $env:TEMP }
try { Test-Config -Config $Config } catch { Write-Error "Invalid configuration: $_"; exit 1 }
try {
    $modulePath = (Join-Path $libDir 'SmartThemeModule.psm1')
    if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction Stop }
} catch {
    Write-SmartThemeLog (Translate 'IMPORT_MODULE_FAILED' $_) 'WARN'
}

# Import scheduler adapter when present
$schedulerModule = Join-Path $libDir 'Scheduler.psm1'
if (Test-Path $schedulerModule) { Import-Module $schedulerModule -Force -ErrorAction SilentlyContinue }



# Time zone resolution is provided by lib/TimeZoneHelpers.ps1 (Resolve-TimeZone).

# --- 1️⃣ Získání aktuální polohy ----------------------------------------------
Write-SmartThemeLog (Translate 'GET_LOCATION') 'INFO'

# Pokud uživatel zadal manuální souřadnice, použijeme je přímo
if ($PSBoundParameters.ContainsKey('Lat') -and $PSBoundParameters.ContainsKey('Lon')) {
    $lat = $Lat
    $lon = $Lon
    $tz  = [System.TimeZoneInfo]::Local.Id
    $city = '(manually provided)'
    Write-SmartThemeLog (Translate 'USED_MANUAL_COORDS' $lat $lon) 'INFO'
}
else {
    try {
        $loc = Invoke-RestWithRetry { Invoke-RestMethod 'https://ipapi.co/json/' }
        $lat = $loc.latitude
        $lon = $loc.longitude
        $tz  = $loc.timezone
        $city = $loc.city
    Write-SmartThemeLog (Translate 'LOCATION_INFO' $city $lat $lon $tz)
    try { Set-LocationCache $lat $lon $tz $city -Config $Config } catch { Write-SmartThemeLog (Translate 'SAVE_CACHE_FAIL' $_) }
    }
    catch {
    Write-SmartThemeLog (Translate 'IPAPI_FAIL')
    $cached = Get-LocationCache -Config $Config
        if ($cached) {
            $lat = $cached.latitude
            $lon = $cached.longitude
            $tz  = $cached.timezone
            $city = $cached.city
            Write-SmartThemeLog (Translate 'USED_CACHE' $city $lat $lon $tz)
        }
        else {
            # Poslední záloha: použij default z lokalizace (pokud dostupná), jinak London
            $loc = $script:LocaleData
            if ($loc -and $loc.DEFAULT_LAT -and $loc.DEFAULT_LON) {
                $lat = [double]$loc.DEFAULT_LAT
                $lon = [double]$loc.DEFAULT_LON
                $city = "$($loc.DEFAULT_CITY) (fallback)"
                # tz is kept as system local id for safety; Resolve-TimeZone will handle mapping
                $tz = $loc.DEFAULT_TZ
                Write-SmartThemeLog (Translate 'NO_LOCATION_FALLBACK_USING_LOC' $city) 'WARN'
            }
            else {
                # fallback hard-coded
                $lat = 51.5074
                $lon = -0.1278
                $tz  = [System.TimeZoneInfo]::Local.Id
                $city = 'London (fallback)'
                Write-SmartThemeLog (Translate 'NO_LOCATION_FALLBACK_HARD') 'WARN'
            }
        }
    }
}

# --- 2️⃣ Získání časů východu a západu slunce ----------------------------------
Write-SmartThemeLog (Translate 'GET_SUN_TIMES') 'INFO'
try {
    $latStr = $lat.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $lonStr = $lon.ToString([System.Globalization.CultureInfo]::InvariantCulture)

    $url = "https://api.sunrise-sunset.org/json?lat=$latStr&lng=$lonStr&formatted=0"
    Write-SmartThemeLog (Translate 'CALL_API_URL' $url) 'DEBUG'

    $sun = Invoke-RestWithRetry { Invoke-RestMethod -Uri $url -UseBasicParsing }
    Write-SmartThemeLog (Translate 'API_STATUS' $($sun.status)) 'DEBUG'

    if ($sun.status -ne 'OK') { throw "API vrátilo chybu: $($sun.status)" }

    # Parse UTC times
    try {
        $sunriseDto = [datetimeoffset]::Parse($sun.results.sunrise, [System.Globalization.CultureInfo]::InvariantCulture)
        $sunsetDto  = [datetimeoffset]::Parse($sun.results.sunset,  [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        # Could be polar day/night or unexpected format
    Write-SmartThemeLog (Translate 'PARSE_SUN_WARN' $_) 'WARN'
        throw
    }

    $sunriseUTC = $sunriseDto.UtcDateTime
    $sunsetUTC  = $sunsetDto.UtcDateTime
    Write-SmartThemeLog (Translate 'UTC_SUNRISE' $sunriseUTC $sunriseUTC.Kind) 'DEBUG'
    Write-SmartThemeLog (Translate 'UTC_SUNSET' $sunsetUTC $sunsetUTC.Kind) 'DEBUG'

        try {
        $windowsTzId = Resolve-TimeZone $tz
    Write-SmartThemeLog (Translate 'USING_WINDOWS_TZ' $windowsTzId $tz) 'DEBUG'
        $tzinfo = [System.TimeZoneInfo]::FindSystemTimeZoneById($windowsTzId)
    }
    catch {
    Write-SmartThemeLog (Translate 'TZ_MAP_WARN' $tz $_) 'WARN'
        $tzinfo = [System.TimeZoneInfo]::Local
    }

    # Convert to local tz
    $sunrise = [System.TimeZoneInfo]::ConvertTimeFromUtc($sunriseUTC, $tzinfo)
    $sunset  = [System.TimeZoneInfo]::ConvertTimeFromUtc($sunsetUTC,  $tzinfo)

    $now = Get-Date
    $dateUsed = (Get-Date).ToString('yyyy-MM-dd')

    # If any event already passed today, query API once for tomorrow (both times)
    if ($sunrise -lt $now -or $sunset -lt $now) {
    Write-SmartThemeLog (Translate 'EVENTS_PASSED' $sunrise $sunset) 'DEBUG'
        try {
            $dateStr = $now.AddDays(1).ToString('yyyy-MM-dd')
            $url2 = "https://api.sunrise-sunset.org/json?lat=$latStr&lng=$lonStr&formatted=0&date=$dateStr"
            Write-SmartThemeLog (Translate 'CALL_API_NEXTDAY' $url2) 'DEBUG'
            $sun2 = Invoke-RestWithRetry { Invoke-RestMethod -Uri $url2 -UseBasicParsing }
            if ($sun2.status -eq 'OK') {
                $sunriseDto2 = [datetimeoffset]::Parse($sun2.results.sunrise, [System.Globalization.CultureInfo]::InvariantCulture)
                $sunsetDto2  = [datetimeoffset]::Parse($sun2.results.sunset,  [System.Globalization.CultureInfo]::InvariantCulture)
                $sunriseUTC = $sunriseDto2.UtcDateTime
                $sunsetUTC  = $sunsetDto2.UtcDateTime
                $sunrise = [System.TimeZoneInfo]::ConvertTimeFromUtc($sunriseUTC, $tzinfo)
                $sunset  = [System.TimeZoneInfo]::ConvertTimeFromUtc($sunsetUTC,  $tzinfo)
                $dateUsed = $dateStr
                Write-SmartThemeLog (Translate 'NEW_LOCAL_TIMES' $sunrise $sunset) 'DEBUG'
            }
                else {
                Write-SmartThemeLog (Translate 'CANNOT_GET_NEXTDAY' $($sun2.status)) 'WARN'
            }
        }
        catch {
            Write-SmartThemeLog (Translate 'ERROR_QUERY_NEXTDAY' $_) 'WARN'
        }
    }

    # Save to cache (store UTC times and the date they correspond to)
            try { Set-LocationCache $lat $lon $tz $city $sunriseUTC.ToString('o') $sunsetUTC.ToString('o') $dateUsed -Config $Config } catch { Write-SmartThemeLog (Translate 'CANNOT_SAVE_SUN_CACHE' $_) 'WARN' }

    Write-SmartThemeLog (Translate 'LOCAL_SUNRISE' $sunrise) 'INFO'
    Write-SmartThemeLog (Translate 'LOCAL_SUNSET' $sunset) 'INFO'

}
catch {
    Write-SmartThemeLog (Translate 'SUN_API_FAIL' $_) 'WARN'
    # Pokusíme se použít cache se sun-times pokud existuje
    $cached = Get-LocationCache -Config $Config
    if ($cached -and $cached.sunriseUtc -and $cached.sunsetUtc -and $cached.date) {
        try {
            Write-SmartThemeLog (Translate 'USING_CACHED_SUN' $($cached.date)) 'INFO'
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
                Write-SmartThemeLog (Translate 'CACHE_STILL_PAST') 'WARN'
                # Naplánujeme znovu spuštění skriptu na zítřejší 03:00
                $retryTime = (Get-Date).Date.AddDays(1).AddHours(3)
                $retryCmd = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Schedule"
                    if (Register-SmartThemeUserTask -taskName 'SmartThemeRetry' -cmd $retryCmd -Time $retryTime -Config $Config) {
                    Write-SmartThemeLog (Translate 'RETRY_SCHEDULED' $($retryTime)) 'INFO'
                } else {
                    Write-SmartThemeLog (Translate 'RETRY_SCHEDULE_FAIL') 'WARN'
                }
                # Don't change scheduling now
                exit 0
            }
                Write-SmartThemeLog (Translate 'USING_CACHED_SHIFTED' $sunrise $sunset) 'INFO'
        }
        catch {
            Write-SmartThemeLog (Translate 'CACHE_USE_ERROR' $_) 'WARN'
            Write-SmartThemeLog (Translate 'CACHE_FETCH_ERROR' $_) 'ERROR'
            exit 1
        }
    }
    else {
    Write-SmartThemeLog (Translate 'NO_SUITABLE_CACHE') 'ERROR'
        exit 1
    }
}

# --- 3️⃣ Logika přepnutí -------------------------------------------------------
$now = Get-Date
$current = Get-CurrentTheme -Config $Config
$target  = $null

if ($Schedule) {
    Write-SmartThemeLog (Translate 'SCHEDULE_ONLY') 'INFO'
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
    Write-SmartThemeLog (Translate 'CANNOT_DETERMINE_CURRENT_THEME') 'ERROR'
        exit 1
    }
}

if (-not $Schedule) {
    Write-SmartThemeLog (Translate 'CURRENT_TO_TARGET' $current $target) 'INFO'
    Set-Theme $target -Config $Config
}
else {
    Write-SmartThemeLog (Translate 'SCHEDULE_MODE_NO_CHANGE') 'INFO'
}

# --- 4️⃣ Naplánování dalšího přepnutí ------------------------------------------
if ($target -eq 'Light') {
    if ($sunset -lt $now) {
        # Pokud je západ i po zítřejším dotazu v minulosti (nepravděpodobné), použijeme AddDays(1) jako poslední záchranu
    Write-SmartThemeLog (Translate 'SUNSET_STILL_PAST' $sunset) 'WARN'
        $sunset = $sunset.AddDays(1)
    }
    $scheduleOk = Register-ThemeSwitch -Mode 'Dark' -Time $sunset -ScriptPath $ScriptPath -Config $Config
}
else {
    if ($sunrise -lt $now) {
        # Pokud je východ i po zítřejším dotazu v minulosti (nepravděpodobné), použijeme AddDays(1) jako poslední záchranu
    Write-SmartThemeLog (Translate 'SUNRISE_STILL_PAST' $sunrise) 'WARN'
        $sunrise = $sunrise.AddDays(1)
    }
    $scheduleOk = Register-ThemeSwitch -Mode 'Light' -Time $sunrise -ScriptPath $ScriptPath -Config $Config
}
    if ($scheduleOk) {
    Write-SmartThemeLog (Translate 'SCHEDULED_DONE')
} else {
    $msg = "Hotovo. ALE: Nepodařilo se vytvořit plánovanou úlohu (pravděpodobně nedostatečná oprávnění)."
    Write-SmartThemeLog $msg

    # Instrukce pro spuštění jako správce
    $elevCmd = "Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" -Schedule' -Verb RunAs"
    Write-SmartThemeLog (Translate 'ELEVATED_INSTRUCTIONS')
    Write-SmartThemeLog (Translate 'ELEVATED_CMD' $elevCmd)

    # Návod pro ruční vytvoření úlohy přes schtasks (příklad)
    $exampleMode = if ($target -eq 'Light') { 'Light' } else { 'Dark' }
    $exampleTime = if ($target -eq 'Light') { $sunrise } else { $sunset }
    $sd = $exampleTime.ToString('MM\/dd\/yyyy')
    $st = $exampleTime.ToString('HH:mm')
    $escapedScript = $ScriptPath -replace '"','\"'
    $schtasksCmd = 'schtasks /Create /SC ONCE /TN "SmartThemeSwitch-' + $exampleMode + '" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $escapedScript + '" -' + $exampleMode + '" /ST ' + $st + ' /SD ' + $sd + ' /F'
    Write-SmartThemeLog (Translate 'SCHTASKS_EXAMPLE_CMD')
    Write-SmartThemeLog (Translate 'SCHTASKS_EXAMPLE_CMD_LINE' $schtasksCmd)

    Write-SmartThemeLog (Translate 'RUN_ELEVATED_SUGGEST')
}
