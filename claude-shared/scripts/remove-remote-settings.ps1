$path = Join-Path $HOME '.claude\remote-settings.json'
if (Test-Path $path) {
    Remove-Item $path -Force
    Write-Host "Removed $path"
} else {
    Write-Host "Not found: $path"
}
