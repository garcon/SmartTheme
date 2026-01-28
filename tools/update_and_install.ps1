Set-StrictMode -Version Latest

param(
    [switch]$SkipGit
)

$repo = (Get-Location).Path
$scriptPath = Join-Path $repo 'SmartTheme.ps1'
$checksumFile = Join-Path $repo 'SmartTheme.ps1.sha256'

if (-not (Test-Path $scriptPath)) {
    Write-Error "SmartTheme.ps1 not found in $repo"
    exit 1
}

$hash = (Get-FileHash -Path $scriptPath -Algorithm SHA256 -ErrorAction Stop).Hash
Set-Content -Path $checksumFile -Value $hash -Encoding Ascii
Write-Output "Updated checksum: $hash"

$dest = Join-Path $env:LOCALAPPDATA 'SmartTheme'
if (-not (Test-Path $dest)) { New-Item -Path $dest -ItemType Directory | Out-Null; Write-Output "Created $dest" }

Copy-Item -Path $scriptPath -Destination $dest -Force
Copy-Item -Path $checksumFile -Destination $dest -Force
if (Test-Path (Join-Path $repo 'theme.cmd')) { Copy-Item -Path (Join-Path $repo 'theme.cmd') -Destination $dest -Force }

Write-Output "Files copied to $dest"

# Run theme if available, otherwise run the installed script directly
$ran = $false
if (Get-Command theme -ErrorAction SilentlyContinue) {
    Write-Output "Running 'theme' from PATH..."
    try { theme } catch { Write-Warning "Running 'theme' failed: $_" }
    $ran = $true
}

if (-not $ran) {
    Write-Output "Running installed script directly..."
    & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dest 'SmartTheme.ps1')
}

# Commit & push checksum if changed (skippable via -SkipGit)
git add SmartTheme.ps1.sha256
$st = (git status --porcelain)
if ($st) {
    if (-not $SkipGit) {
        git commit -m "chore: update SmartTheme.ps1.sha256 to match current script"
        git push origin main
    } else {
        Write-Output "Skipping git commit/push (SkipGit set)."
    }
} else {
    Write-Output "No checksum changes to commit."
}
