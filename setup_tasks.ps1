param(
    [switch]$Elevated
)

. (Join-Path $PSScriptRoot "pc_monitor_common.ps1")

Write-PcMonitorBanner

if (-not (Test-PcMonitorAdministrator)) {
    Write-Host "[INFO] Requesting Administrator privileges..." -ForegroundColor Yellow
    $argumentList = @(
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-Elevated"
    )

    try {
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList $argumentList -Verb RunAs -Wait -PassThru
        exit $process.ExitCode
    } catch {
        Write-Host "[ERROR] Administrator elevation was cancelled or failed." -ForegroundColor Red
        exit 1
    }
}

Write-Host "[INFO] Administrator session detected." -ForegroundColor Green
Write-Host ""

try {
    $config = Get-PcMonitorConfig -BasePath $PSScriptRoot
    Initialize-PcMonitorDataPaths -BasePath $PSScriptRoot | Out-Null
    $installPath = Get-PcMonitorInstallPath -BasePath $PSScriptRoot -Persist
    $botInfo = Test-PcMonitorTelegramConfiguration -BasePath $PSScriptRoot
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Create config.json from config.example.json and fill in your bot details." -ForegroundColor Yellow
    exit 1
}

Write-Host "[INFO] Installation Path: $installPath" -ForegroundColor Green
Write-Host "[INFO] Telegram Bot: @$($botInfo.username)" -ForegroundColor Green
Write-Host ""

$missingScripts = @(Test-PcMonitorRequiredScripts -InstallPath $installPath)
if ($missingScripts.Count -gt 0) {
    Write-Host "[ERROR] The following scripts are missing:" -ForegroundColor Red
    foreach ($script in $missingScripts) {
        Write-Host "  - $script" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Please ensure all required scripts exist in: $installPath" -ForegroundColor Yellow
    exit 1
}

try {
    Write-Host "[STEP] Installing requirements..." -ForegroundColor Cyan
    $ffmpegPath = Install-PcMonitorFfmpeg -BasePath $PSScriptRoot
    Write-Host "  [OK] ffmpeg: $ffmpegPath" -ForegroundColor Green
    Write-Host ""

    Write-Host "[STEP] Enabling Windows auditing..." -ForegroundColor Cyan
    Enable-PcMonitorAuditing
    Write-Host "  [OK] Audit policies configured" -ForegroundColor Green
    Write-Host ""

    Write-Host "[STEP] Refreshing task definitions..." -ForegroundColor Cyan
    $updatedFiles = Sync-PcMonitorTaskXml -BasePath $PSScriptRoot -InstallPath $installPath
    foreach ($file in $updatedFiles) {
        Write-Host "  [OK] $file" -ForegroundColor Green
    }
    Write-Host ""

    Write-Host "[STEP] Stopping existing Raven monitor processes..." -ForegroundColor Cyan
    Stop-PcMonitorProcesses
    Write-Host "  [OK] Existing monitor listeners cleared" -ForegroundColor Green
    Write-Host ""

    Write-Host "[STEP] Installing scheduled tasks..." -ForegroundColor Cyan
    $installedTasks = Install-PcMonitorTasks -BasePath $PSScriptRoot
    foreach ($taskName in $installedTasks) {
        Write-Host "  [OK] $taskName" -ForegroundColor Green
    }
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Raven Setup Complete" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Raven is installed and ready." -ForegroundColor White
Write-Host "Open Task Scheduler with: taskschd.msc" -ForegroundColor White
Write-Host ""
