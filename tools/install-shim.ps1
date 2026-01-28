Param(
    [string]$ShimName = 'theme.cmd'
)

try {
    $repo = (Get-Location).Path
    $shimSrc = Join-Path $repo $ShimName
    if (-not (Test-Path $shimSrc)) { Write-Error "Shim $ShimName not found in repo"; exit 1 }

    $userBin = Join-Path $env:USERPROFILE 'bin'
    if (-not (Test-Path $userBin)) { New-Item -Path $userBin -ItemType Directory | Out-Null; Write-Host "Created $userBin" }

    $dest = Join-Path $userBin $ShimName
    Copy-Item -Path $shimSrc -Destination $dest -Force
    Write-Host "Copied shim to $dest"

    # Ensure user bin is on PATH
    $path = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not ($path -split ';' | Where-Object { $_ -eq $userBin })) {
        $newPath = "$path;$userBin"
        setx PATH $newPath | Out-Null
        Write-Host "Added $userBin to user PATH (requires new shell to take effect)"
    } else {
        Write-Host "User PATH already contains $userBin"
    }

    Write-Host "Shim installation complete. Open a new shell to use 'theme' command."
    exit 0
} catch {
    Write-Error "Install-shim failed: $_"
    exit 1
}
