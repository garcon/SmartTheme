function Import-TaskXml {
    [CmdletBinding()]
    [OutputType([bool])]
    <#
    .SYNOPSIS
        Import a scheduled task from XML using ScheduledTasks or schtasks.exe.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$XmlPath,
        [Parameter(Mandatory=$true)][string]$TaskName,
        [string]$SchtasksExe = 'schtasks.exe',
        [psobject]$Config
    )
    try {
        # Prefer built-in ScheduledTasks cmdlets when available
        if (Get-Command -Name 'Register-ScheduledTask' -ErrorAction SilentlyContinue) {
            try {
                $xml = Get-Content -Path $XmlPath -Raw
                $definition = New-ScheduledTask -Xml $xml
                Register-ScheduledTask -TaskName $TaskName -InputObject $definition -Force
                return $true
            } catch {
                Write-Verbose "Import-TaskXml: ScheduledTasks import failed, will fallback to schtasks.exe. $_"
            }
        }

        # Fallback to schtasks.exe import via /Create /XML
        $exe = if ($Config -and $Config.SchtasksExe) { $Config.SchtasksExe } else { $SchtasksExe }
        $argList = @('/Create','/TN',$TaskName,'/XML',$XmlPath,'/F')
        $p = Start-Process -FilePath $exe -ArgumentList $argList -NoNewWindow -Wait -PassThru -ErrorAction Stop
        return ($p.ExitCode -eq 0)
    } catch {
        return $false
    }
}

function Export-TaskXml {
    [CmdletBinding()]
    [OutputType([bool])]
    <#
    .SYNOPSIS
        Export a scheduled task to XML using ScheduledTasks cmdlets if available.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$TaskName,
        [Parameter(Mandatory=$true)][string]$OutPath,
        [string]$CmdExe = 'cmd.exe',
        [string]$SchtasksExe = 'schtasks.exe',
        [psobject]$Config
    )
    try {
        # Try using ScheduledTasks module
        if (Get-Command -Name 'Export-ScheduledTask' -ErrorAction SilentlyContinue) {
            try {
                $null = $CmdExe; $null = $SchtasksExe; $null = $Config
                Export-ScheduledTask -TaskName $TaskName -Xml $OutPath -Force
                return $true
            } catch {
                Write-Verbose "Export-TaskXml: Export-ScheduledTask failed, falling back. $_"
            }
        }
        # No reliable cross-platform schtasks export; return $false as fallback
        return $false
    } catch {
        return $false
    }
}

function Register-Schtask {
    [CmdletBinding()]
    [OutputType([bool])]
    <#
    .SYNOPSIS
        Create a scheduled task using schtasks.exe.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$TaskName,
        [Parameter(Mandatory=$true)][string]$Cmd,
        [Parameter(Mandatory=$false)][string]$Time,
        [string]$ScheduleType = 'ONCE', # ONCE | ONSTART | ONLOGON
        [string]$User,
        [string]$RunnerExe = 'powershell.exe',
        [string]$SchtasksExe = 'schtasks.exe',
        [psobject]$Config
    )
    try {
        $exe = if ($Config -and $Config.SchtasksExe) { $Config.SchtasksExe } else { $SchtasksExe }
        $arguments = @('/Create')
        switch ($ScheduleType.ToUpper()) {
            'ONSTART' { $arguments += @('/SC','ONSTART') }
            'ONLOGON' { $arguments += @('/SC','ONLOGON') }
            default { $arguments += @('/SC','ONCE') }
        }
        $arguments += @('/TN',$TaskName)
        if ($ScheduleType.ToUpper() -eq 'ONCE' -and $Time) { $arguments += @('/ST',$Time) }
            $trCmd = '"' + ($RunnerExe + ' -NoProfile -WindowStyle Hidden -Command "& { ' + $Cmd + ' }"') + '"'
            $arguments += @('/TR',$trCmd,'/F')
        if ($User) { $arguments += @('/RU',$User) }
        $p = Start-Process -FilePath $exe -ArgumentList $arguments -NoNewWindow -Wait -PassThru -ErrorAction Stop
        return ($p.ExitCode -eq 0)
    } catch {
        return $false
    }
}

Export-ModuleMember -Function Import-TaskXml,Export-TaskXml,Register-Schtask
