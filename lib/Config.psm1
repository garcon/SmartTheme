function Get-DefaultConfig {
    <#
    .SYNOPSIS
        Return a default configuration object for SmartTheme.
    #>
    param(
        [hashtable]$Overrides
    )
    $cacheDir = Join-Path $env:LOCALAPPDATA 'SmartTheme'
    $default = [pscustomobject]@{
        RunnerExe   = 'powershell.exe'
        SchtasksExe = 'schtasks.exe'
        CmdExe      = 'cmd.exe'
        User        = $env:USERNAME
        TempDir     = $env:TEMP
        RegPath     = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        CacheDir    = $cacheDir
        CacheFile   = Join-Path $cacheDir 'location.json'
    }
    if ($Overrides) {
        foreach ($k in $Overrides.Keys) {
            $default | Add-Member -NotePropertyName $k -NotePropertyValue $Overrides[$k] -Force
        }
    }
    return $default
}

function Test-Config {
    <#
    .SYNOPSIS
        Validate that a configuration object contains required keys.
    #>
    param(
        [Parameter(Mandatory=$true)][psobject]$Config
    )
    $required = @('RunnerExe','SchtasksExe','CmdExe','TempDir','CacheDir','CacheFile')
    foreach ($r in $required) {
        if (-not ($Config.PSObject.Properties.Name -contains $r)) {
            throw "Config missing required key: $r"
        }
    }
    return $true
}

Export-ModuleMember -Function Get-DefaultConfig,Test-Config
