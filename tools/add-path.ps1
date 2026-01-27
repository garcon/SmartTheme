param()

$dir = Join-Path $env:LOCALAPPDATA 'SmartTheme'
$cur = [Environment]::GetEnvironmentVariable('Path','User')
if ($cur -and ($cur.Split(';') -contains $dir)) {
    Write-Output "User PATH already contains: $dir"
    return 0
}

if ([string]::IsNullOrEmpty($cur)) {
    $new = $dir
}
else {
    $new = $cur + ';' + $dir
}

[Environment]::SetEnvironmentVariable('Path', $new, 'User')
Write-Output "Added SmartTheme folder to USER PATH: $dir"
Write-Output "Note: open a new terminal to see the updated PATH."
