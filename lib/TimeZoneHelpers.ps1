function Resolve-TimeZone([string]$tz) {
    if (-not $tz) { throw 'Timezone string is empty' }

    # Try direct Windows ID first
    try {
        [void][System.TimeZoneInfo]::FindSystemTimeZoneById($tz)
        return $tz
    } catch { Write-Verbose "Resolve-TimeZone: not a Windows tz id: $tz" }

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
