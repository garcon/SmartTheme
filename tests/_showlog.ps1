Set-StrictMode -Version Latest
Set-Location 'c:\Users\Martin\AppData\Local\SmartTheme'
$log = Join-Path $env:LOCALAPPDATA 'SmartTheme\smarttheme.log'
if (Test-Path -Path $log) {
    Get-Content -Path $log -Tail 20 | Out-Host
} else {
    Write-Host 'no log'
}
