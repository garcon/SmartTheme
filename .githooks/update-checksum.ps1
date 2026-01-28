try {
    $script = Join-Path (Get-Location) 'SmartTheme.ps1'
    if (-not (Test-Path $script)) { Write-Error "SmartTheme.ps1 not found"; exit 1 }
    $hash = (Get-FileHash -Path $script -Algorithm SHA256 -ErrorAction Stop).Hash
    $hash | Set-Content -Path (Join-Path (Get-Location) 'SmartTheme.ps1.sha256') -Encoding ASCII
    git add -- 'SmartTheme.ps1.sha256' | Out-Null
    exit 0
} catch {
    Write-Error "Checksum update failed: $_"
    exit 2
}
