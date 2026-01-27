## Shim: import the Logging module so dot-sourcing this .ps1 preserves compatibility.
$modulePath = Join-Path $PSScriptRoot 'LoggingModule.psm1'
if (Test-Path $modulePath) { Import-Module $modulePath -Force -ErrorAction SilentlyContinue }
