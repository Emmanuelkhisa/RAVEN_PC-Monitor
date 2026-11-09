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

$installPath = [System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles "Microsoft Health\Remote PC Monitor"))
try {
    $copyResult = Copy-PcMonitorInstallation -SourcePath $PSScriptRoot -DestinationPath $installPath
    if ($copyResult.Copied) {
        Write-Host "[STEP] Installing project files to the fixed application directory..." -ForegroundColor Cyan
        Write-Host "  [OK] Source: $PSScriptRoot" -ForegroundColor Green
        Write-Host "  [OK] Destination: $installPath" -ForegroundColor Green
        if ($copyResult.ConfigCreated) {
            Write-Host "  [OK] Initialized installation config without overwriting existing target settings." -ForegroundColor Green
        }
        if ($copyResult.CredentialsRequired) {
            Write-Host "[WARN] Fresh Telegram credentials are required on this Windows installation." -ForegroundColor Yellow
        }

        $installedSetupPath = Join-Path $installPath "setup_tasks.ps1"
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$installedSetupPath`"",
            "-Elevated"
        ) -Wait -PassThru -ErrorAction Stop
        exit $process.ExitCode
    }
} catch {
    Write-Host "[ERROR] Failed to stage the application in $installPath : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

try {
    Set-PcMonitorConfigFilePermissions -BasePath $PSScriptRoot
    $config = Get-PcMonitorConfig -BasePath $PSScriptRoot
    if ($config.PSObject.Properties.Name -contains "installPath") {
        $config.installPath = $installPath
    } else {
        $config | Add-Member -NotePropertyName "installPath" -NotePropertyValue $installPath
    }
    Save-PcMonitorConfig -Config $config -BasePath $PSScriptRoot | Out-Null
    Set-PcMonitorRuntimeDataPermissions -BasePath $PSScriptRoot
    Initialize-PcMonitorDataPaths -BasePath $PSScriptRoot | Out-Null
    $botInfo = Test-PcMonitorTelegramConfiguration -BasePath $PSScriptRoot
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Installation path: $([System.IO.Path]::GetFullPath((Join-Path $env:ProgramFiles 'Microsoft Health\Remote PC Monitor')))" -ForegroundColor Yellow
    Write-Host "Edit config.json there with a valid botToken and chatID, then run setup_tasks.ps1 again." -ForegroundColor Yellow
    exit 1
}

Write-Host "[INFO] Installation Path: $installPath" -ForegroundColor Green
Write-Host "[INFO] Telegram Bot: @$($botInfo.username)" -ForegroundColor Green
Write-Host ""

$configPath = Get-PcMonitorConfigPath -BasePath $PSScriptRoot
try {
    $currentConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace([string]$currentConfig.botToken) -and
        [string]::IsNullOrWhiteSpace([string]$currentConfig.botTokenProtected)) {
        Write-Host "[ERROR] Telegram credentials are not configured." -ForegroundColor Red
        Write-Host "Edit $configPath and set botToken and chatID, then rerun this installer." -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "[ERROR] Could not read $configPath : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

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
    Write-Host ""

    Write-Host "[STEP] Removing old Watchdog task if present..." -ForegroundColor Cyan
    if (-not (Test-PcMonitorAdministrator)) {
        Write-Host "  [WARN] Cannot remove stale Watchdog task without administrator privileges." -ForegroundColor Yellow
    } else {
        & schtasks /query /tn "\PC Monitor\Watchdog" 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            & schtasks /delete /tn "\PC Monitor\Watchdog" /f 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [OK] Removed old Watchdog task" -ForegroundColor Green
            }
        }
    }
    Write-Host ""

    Write-Host "[STEP] Securing bot credentials with DPAPI..." -ForegroundColor Cyan
    try {
        $currentConfig = Get-Content -LiteralPath (Get-PcMonitorConfigPath -BasePath $PSScriptRoot) -Raw -Encoding UTF8 | ConvertFrom-Json
        $alreadyProtected = ($currentConfig.PSObject.Properties.Name -contains "botTokenProtected") -and -not [string]::IsNullOrWhiteSpace($currentConfig.botTokenProtected)
        if (-not $alreadyProtected) {
            $plainToken = $currentConfig.botToken
            $protectedToken = Protect-PcMonitorSecret -Plaintext $plainToken
            if ($currentConfig.PSObject.Properties.Name -contains "botTokenProtected") {
                $currentConfig.botTokenProtected = $protectedToken
            } else {
                $currentConfig | Add-Member -NotePropertyName "botTokenProtected" -NotePropertyValue $protectedToken
            }
            $currentConfig.botToken = ""
            $currentConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Get-PcMonitorConfigPath -BasePath $PSScriptRoot) -Encoding UTF8
            Write-Host "  [OK] Bot token encrypted (LocalMachine DPAPI)" -ForegroundColor Green
        } else {
            Write-Host "  [OK] Bot token already encrypted" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Could not encrypt bot token: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "         The bot will continue using the plaintext token." -ForegroundColor Yellow
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
Write-Host "Installation directory: $installPath" -ForegroundColor White
Write-Host "Open Task Scheduler with: taskschd.msc" -ForegroundColor White
Write-Host ""
