function Import-TaskXml {
    [CmdletBinding()]
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
                $task = [xml]$xml
                $definition = New-ScheduledTask -Xml $xml
                Register-ScheduledTask -TaskName $TaskName -InputObject $definition -Force
                return $true
            } catch {
                # fallback to schtasks
            }
        }

        # Fallback to schtasks.exe import via /Create /XML
        $exe = if ($Config -and $Config.SchtasksExe) { $Config.SchtasksExe } else { $SchtasksExe }
        $args = @('/Create','/TN',$TaskName,'/XML',$XmlPath,'/F')
        $p = Start-Process -FilePath $exe -ArgumentList $args -NoNewWindow -Wait -PassThru -ErrorAction Stop
        return ($p.ExitCode -eq 0)
    } catch {
        return $false
    }
}

function Export-TaskXml {
    [CmdletBinding()]
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
                Export-ScheduledTask -TaskName $TaskName -Xml $OutPath -Force
                return $true
            } catch {
                # fallback
            }
        }
        # No reliable cross-platform schtasks export; return $false as fallback
        return $false
    } catch {
        return $false
    }
}

function Register-Schtasks {
    [CmdletBinding()]
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
        $arguments += @('/TR',"$RunnerExe -NoProfile -WindowStyle Hidden -Command `"& { $Cmd }`"",'/F')
        if ($User) { $arguments += @('/RU',$User) }
        $p = Start-Process -FilePath $exe -ArgumentList $arguments -NoNewWindow -Wait -PassThru -ErrorAction Stop
        return ($p.ExitCode -eq 0)
    } catch {
        return $false
    }
}

Export-ModuleMember -Function Import-TaskXml,Export-TaskXml,Register-Schtasks
