$repo=(Get-FileHash -Path .\SmartTheme.ps1 -Algorithm SHA256).Hash
$inst=Join-Path $env:LOCALAPPDATA 'SmartTheme\SmartTheme.ps1'
$instHash = if (Test-Path $inst) { (Get-FileHash -Path $inst -Algorithm SHA256).Hash } else { 'MISSING' }
$shaFile=Join-Path $env:LOCALAPPDATA 'SmartTheme\SmartTheme.ps1.sha256'
$sha = if (Test-Path $shaFile) { Get-Content $shaFile -Raw } else { 'MISSING' }
[PSCustomObject]@{
    Repo = $repo
    InstalledPath = $inst
    Installed = $instHash
    ShaFilePath = $shaFile
    ShaFile = $sha
}
