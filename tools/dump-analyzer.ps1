Import-Module PSScriptAnalyzer -ErrorAction Stop
$results = Invoke-ScriptAnalyzer -Path . -Recurse -Severity Warning -IncludeRule 'PSAvoidUsingEmptyCatchBlock','PSUseApprovedVerbs','PSReviewUnusedParameter','PSUseBOMForUnicodeEncodedFile','PSAvoidOverwritingBuiltInCmdlets' -ErrorAction SilentlyContinue
$results | Select-Object Severity,RuleName,ScriptPath,Line,Message | Format-Table -AutoSize
$results | Out-File analyzer-details.txt -Width 4096
if ($results -and $results.Count -gt 0) { exit 2 } else { Write-Output 'No findings'; exit 0 }