function Get-PreferredLocale {
    <#
    .SYNOPSIS
        Return the preferred two-letter locale for the current environment.
    #>
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
    <#
    .SYNOPSIS
        Load a locale JSON file from the `locales` directory and return it as an object.
    #>
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
function Import-Locale([string]$lang) {
    <#
    .SYNOPSIS
        Compatibility wrapper for loading a locale by language code.
    #>
    return Get-Locale $lang
}

# Initialize module-scoped localization data
function Set-Localization {
    [CmdletBinding(SupportsShouldProcess=$true)]
    <#
    .SYNOPSIS
        Initialize module localization variables (`PreferredLocale` and `LocaleData`).
    #>
    param(
        [string]$PreferredLocale
    )
    if (-not $PreferredLocale) { $PreferredLocale = Get-PreferredLocale }
    $data = Get-Locale $PreferredLocale
    if (-not $data) {
        $data = Get-Locale 'en'
        $PreferredLocale = 'en'
    }
    if ($PSCmdlet -and -not $PSCmdlet.ShouldProcess('LocaleData', "Set preferred locale to $PreferredLocale")) { return }
    Set-Variable -Name PreferredLocale -Scope Script -Value $PreferredLocale
    Set-Variable -Name LocaleData -Scope Script -Value $data
    if (-not (Get-Variable -Name EnLocaleData -Scope Script -ErrorAction SilentlyContinue)) {
        Set-Variable -Name EnLocaleData -Scope Script -Value (Get-Locale 'en')
    }
}

function Translate($key, [Parameter(ValueFromRemainingArguments=$true)][object[]]$formatArgs) {
    <#
    .SYNOPSIS
        Translate a message key using the loaded locale, formatting with optional args.
    #>
    $locale = (Get-Variable -Name LocaleData -Scope Script -ErrorAction SilentlyContinue).Value
    $en = (Get-Variable -Name EnLocaleData -Scope Script -ErrorAction SilentlyContinue).Value

    if ($locale -and $locale.PSObject.Properties.Name -contains $key) {
        $val = $locale.$key
    }
    elseif ($en -and $en.PSObject.Properties.Name -contains $key) {
        $val = $en.$key
    }
    else { return $key }

    if ($formatArgs) {
        try {
            return ($val -f $formatArgs)
        } catch {
            return ($val + ' ' + ($formatArgs -join ' '))
        }
    } else { return $val }
}

Export-ModuleMember -Function Get-PreferredLocale,Get-Locale,Import-Locale,Set-Localization,Translate
