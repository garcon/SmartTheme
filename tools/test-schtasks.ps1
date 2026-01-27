$fullCmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\Martin\AppData\Local\SmartTheme\SmartTheme.ps1" -Ensure'
$tr = '"' + $fullCmd + '"'
Write-Output "TR=[$tr]"
Write-Output "Invoking: schtasks.exe /Create /SC ONCE /TN TestTask /TR $tr /ST 07:39 /SD 01/28/2026 /F"
try {
    $out = & schtasks.exe /Create /SC ONCE /TN TestTask /TR $tr /ST 07:39 /SD 01/28/2026 /F 2>&1
    Write-Output "SCHT OUTPUT:"
    $out | ForEach-Object { Write-Output "SCHT: $_" }
} catch {
    Write-Output "SCHT EXCEPTION: $_"
}
