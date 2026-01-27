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

    if (-not $PSBoundParameters.ContainsKey('DebugMode')) {
        $v = Get-Variable -Name ShowDebug -Scope Script -ErrorAction SilentlyContinue
        if ($v) { $DebugMode = [switch]$v.Value }
    }

    if (-not $PSBoundParameters.ContainsKey('LogFile')) {
        $vf = Get-Variable -Name logFile -Scope Script -ErrorAction SilentlyContinue
        if ($vf) { $LogFile = $vf.Value } else { $LogFile = Join-Path $env:LOCALAPPDATA 'SmartTheme\smarttheme.log' }
    }

    if ($Level -eq 'DEBUG' -and -not $DebugMode) {
        try { $line | Out-File -FilePath $LogFile -Append -Encoding UTF8 } catch { Write-Error "Write-Log (debug): $($_)" }
        Clear-SmartThemeLogFile -Path $LogFile -Lines $Lines
        return
    }

    try { Write-Output $line } catch { Write-Output $line }
    try {
        if (-not (Test-Path -Path $LogFile)) {
            $preamble = [System.Text.Encoding]::UTF8.GetPreamble()
            if ($preamble -and $preamble.Length -gt 0) { [System.IO.File]::WriteAllBytes($LogFile, $preamble) }
        }
        [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch { Write-Error "Write-SmartThemeLog (file): $($_)" }
    Clear-SmartThemeLogFile -Path $LogFile -Lines 500
}

function Write-Log {
    param(
        [string]$msg,
        [string]$level = 'INFO'
    )
    Write-SmartThemeLog $msg $level
}

Export-ModuleMember -Function Clear-SmartThemeLogFile,Write-SmartThemeLog,Write-Log
