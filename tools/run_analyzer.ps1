Import-Module PSScriptAnalyzer -ErrorAction Stop
# Older PSScriptAnalyzer versions may not support -SettingsPath; explicitly analyze relevant files and exclude tests/ and tools/
$files = Get-ChildItem -Path . -Recurse -Include *.ps1,*.psm1 | Where-Object { $_.FullName -notmatch '\\\\tests\\\\' -and $_.FullName -notmatch '\\\\.github\\\\' -and $_.FullName -notmatch '\\\\tools\\\\' } | Select-Object -ExpandProperty FullName
$issues = @()
if ($files) {
    foreach ($f in $files) {
        try {
            $res = Invoke-ScriptAnalyzer -Path $f -Severity Warning
            if ($res) { $issues += $res }
        } catch {
            Write-Error "Analyzer failed for $($f): $($_)"
        }
    }
}
if ($issues) {
    $issues | Select-Object Severity, ScriptName, Line, RuleName, Message | Format-Table -AutoSize
} else {
    Write-Output 'No issues found by PSScriptAnalyzer'
}
exit 0
