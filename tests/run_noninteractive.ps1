<#
Safe non-interactive runner for SmartTheme.
Usage:
  - Non-elevated run: `pwsh -NoProfile -File .\tests\run_noninteractive.ps1`
  - Elevated run: `pwsh -NoProfile -File .\tests\run_noninteractive.ps1 -Elevated`

Notes:
  - Elevated run will trigger UAC because it uses Start-Process -Verb RunAs.
  - This script never prompts for input; it exits with non-zero code on failure.
#>
param(
    [switch]$Elevated
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $scriptPath = Join-Path $repoRoot 'SmartTheme.ps1'
    if (-not (Test-Path -Path $scriptPath)) { throw "SmartTheme.ps1 not found at $scriptPath" }

    $args = @('-Lat','50.0755','-Lon','14.4378','-Debug')

    if ($Elevated) {
        # Non-interactive policy: do NOT trigger UAC from this runner.
        # If the user requested elevated run, require the current process to already be elevated.
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object System.Security.Principal.WindowsPrincipal($id)
        if (-not $p.IsInRole([System.Security.Principal.WindowsBuiltinRole]::Administrator)) {
            Write-Error 'Elevated run requested but current process is not elevated. Please re-run this runner from an elevated PowerShell.'
            exit 3
        }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @args
    }
    else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath @args
    }

    Start-Sleep -Seconds 1
    $log = Join-Path $env:LOCALAPPDATA 'SmartTheme\smarttheme.log'
    if (Test-Path -Path $log) {
        $lines = (Get-Content -Path $log -ErrorAction Stop | Measure-Object -Line).Lines
        Write-Output "LOG_LINES:$lines"
        exit 0
    }
    else {
        Write-Error "Log file not found: $log"
        exit 2
    }
}
catch {
    Write-Error "Runner failed: $($_.Exception.Message)"
    exit 1
}
finally { Pop-Location }
