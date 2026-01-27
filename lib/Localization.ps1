## Shim: import the proper Localization module. This file exists for backward compatibility
# Module `LocalizationModule.psm1` provides `Get-PreferredLocale`, `Get-Locale`, `Load-Locale`,
# `Initialize-Localization` and `Translate`. Import it when this script is dot-sourced.
$modulePath = Join-Path $PSScriptRoot 'LocalizationModule.psm1'
if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction SilentlyContinue }
