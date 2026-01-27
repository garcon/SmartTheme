# Run Pester tests and PSScriptAnalyzer locally

# Install modules if missing (non-interactive)
# Use legacy Pester 3.4 for compatibility with existing tests
Install-Module -Name Pester -RequiredVersion 3.4.0 -Force -Scope CurrentUser -AllowClobber -ErrorAction SilentlyContinue
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -AllowClobber -ErrorAction SilentlyContinue

# Run Pester (explicit legacy version)
Import-Module Pester -RequiredVersion 3.4.0
Invoke-Pester -Script .\tests

# Run PSScriptAnalyzer and fail on findings
Import-Module PSScriptAnalyzer
$results = Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning
if ($results -and $results.Count -gt 0) {
    $results | Select-Object Severity, RuleName, ScriptPath, Line, Message | Format-Table -AutoSize
    Write-Error 'PSScriptAnalyzer detected issues (see above)'
    exit 2
} else {
    Write-Output 'PSScriptAnalyzer: no findings'
    exit 0
}
