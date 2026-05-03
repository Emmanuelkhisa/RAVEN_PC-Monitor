. (Join-Path $PSScriptRoot "pc_monitor_common.ps1")

Write-PcMonitorBanner
Write-Host "[INFO] install_tasks.ps1 now forwards to setup_tasks.ps1." -ForegroundColor Yellow
Write-Host ""

if (-not (Test-PcMonitorAdministrator)) {
    Write-Host "[ERROR] This script requires Administrator privileges." -ForegroundColor Red
    Write-Host "Run setup_tasks.ps1 instead for the one-command guided install." -ForegroundColor Yellow
    exit 1
}

& powershell.exe -ExecutionPolicy Bypass -File "$PSScriptRoot\setup_tasks.ps1" -Elevated
exit $LASTEXITCODE
