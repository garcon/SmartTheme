function Get-PreferredLocale {
    try {
        $ui = (Get-UICulture).Name
    } catch {
        $ui = [System.Globalization.CultureInfo]::InstalledUICulture.Name
    }
    try {
        $ci = New-Object System.Globalization.CultureInfo($ui)
        return $ci.TwoLetterISOLanguageName
    } catch {
        return 'en'
    }
}

function Get-Locale($lang) {
    $localesDir = Join-Path $PSScriptRoot 'locales'
    $langFile = Join-Path $localesDir ("$lang.json")
    if (-not (Test-Path $langFile)) { return $null }
    try {
        $json = Get-Content -Path $langFile -Raw
        return $json | ConvertFrom-Json
    } catch {
        return $null
    }
}

# Compatibility wrapper for older tests/code that called Load-Locale
function Load-Locale([string]$lang) {
    return Get-Locale $lang
}

# Convenience: load preferred locale into script-scoped variables
function Initialize-Localization {
    $lang = Get-PreferredLocale
    $data = Get-Locale $lang
    if (-not $data) {
        $data = Get-Locale 'en'
        $lang = 'en'
    }
    $Global:PreferredLocale = $lang
    $Global:LocaleData = $data
    # Ensure English baseline is available for fallback
    if (-not $Global:EnLocaleData) { $Global:EnLocaleData = Get-Locale 'en' }
}
function global:Translate($key, [Parameter(ValueFromRemainingArguments=$true)][object[]]$args) {
    if ($Global:LocaleData -and $Global:LocaleData.PSObject.Properties.Name -contains $key) {
        $val = $Global:LocaleData.$key
    }
    elseif ($Global:EnLocaleData -and $Global:EnLocaleData.PSObject.Properties.Name -contains $key) {
        $val = $Global:EnLocaleData.$key
    }
    else { return $key }

    if ($args) {
        try {
            return ($val -f $args)
        } catch {
            return ($val + ' ' + ($args -join ' '))
        }
    } else { return $val }
}
