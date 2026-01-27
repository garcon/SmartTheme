function Clear-SmartThemeLogFile {
    [CmdletBinding()]
    param(
        [string]$Path,
        [int]$Lines = 500
    )
    try {
        $tail = Get-Content -Path $Path -Tail $Lines -ErrorAction SilentlyContinue
        if ($tail) { $tail | Set-Content -Path $Path -Encoding UTF8 }
    } catch {
        Write-Error "Clear-SmartThemeLogFile failed: $($_)"
    }
}

function Write-SmartThemeLog {
    [CmdletBinding()]
    param(
        [string]$msg,
        [ValidateSet('INFO','WARN','ERROR','SUCCESS','DEBUG')][string]$Level = 'INFO',
        [switch]$DebugMode,
        [string]$LogFile
    )
    $line = "$(Get-Date -Format o) [$Level] - $msg"

    # If DEBUG level and debug not enabled, only write to the log file and skip console output
    # Determine debug mode if not provided
    if (-not $PSBoundParameters.ContainsKey('DebugMode')) {
        $v = Get-Variable -Name ShowDebug -Scope Script -ErrorAction SilentlyContinue
        if ($v) { $DebugMode = [switch]$v.Value }
    }

    # Determine logfile if not provided
    if (-not $PSBoundParameters.ContainsKey('LogFile')) {
        $vf = Get-Variable -Name logFile -Scope Script -ErrorAction SilentlyContinue
        if ($vf) { $LogFile = $vf.Value } else { $LogFile = Join-Path $env:LOCALAPPDATA 'SmartTheme\smarttheme.log' }
    }

    if ($Level -eq 'DEBUG' -and -not $DebugMode) {
        try { $line | Out-File -FilePath $LogFile -Append -Encoding UTF8 } catch { Write-Error "Write-Log (debug): $($_)" }
        Clear-SmartThemeLogFile -Path $LogFile -Lines $Lines
        return
    }

    # Avoid Write-Host for better compatibility; write to output stream instead
    try { Write-Output $line } catch { Write-Output $line }
    try {
        # Ensure file starts with UTF-8 BOM so other readers detect encoding
        if (-not (Test-Path -Path $LogFile)) {
            $preamble = [System.Text.Encoding]::UTF8.GetPreamble()
            if ($preamble -and $preamble.Length -gt 0) { [System.IO.File]::WriteAllBytes($LogFile, $preamble) }
        }
        [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch { Write-Error "Write-SmartThemeLog (file): $($_)" }
    Clear-SmartThemeLogFile -Path $LogFile -Lines 500
}

# Compatibility wrapper: older code/tests call Write-Log
function global:Write-Log {
    param(
        [string]$msg,
        [string]$level = 'INFO'
    )
    Write-SmartThemeLog $msg $level
}
