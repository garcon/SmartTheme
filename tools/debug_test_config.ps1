Import-Module "$PSScriptRoot\..\lib\Config.psm1"
Import-Module "$PSScriptRoot\..\lib\SmartThemeModule.psm1"
$cfg = Get-DefaultConfig @{ CacheDir = "$env:LOCALAPPDATA\SmartTheme"; CacheFile = "$env:LOCALAPPDATA\SmartTheme\location.json" }
Write-Output 'Config before:'
$cfg | Format-List *
try {
    $out = Test-ConfigExecutable -Config $cfg
    Write-Output 'Result from Test-ConfigExecutable:'
    $out | Format-List *
} catch {
    Write-Output 'Caught error:'
    Write-Output $_
}
