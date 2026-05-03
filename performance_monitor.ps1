. (Join-Path $PSScriptRoot "pc_monitor_common.ps1")

try {
    $config = Get-PcMonitorConfig -BasePath $PSScriptRoot
    Initialize-PcMonitorDataPaths -BasePath $PSScriptRoot | Out-Null
} catch {
    Write-Error $_
    exit 1
}

$cpuThreshold = if ($config.cpuThreshold) { [int]$config.cpuThreshold } else { 90 }
$memoryThreshold = if ($config.memoryThreshold) { [int]$config.memoryThreshold } else { 90 }
$diskThreshold = if ($config.diskThreshold) { [int]$config.diskThreshold } else { 90 }

$time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$pc = $env:COMPUTERNAME
$alerts = @()

try {
    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    if ($cpuLoad -ge $cpuThreshold) {
        $topProcess = Get-Process | Sort-Object CPU -Descending | Select-Object -First 1
        $alerts += @"
[WARNING] HIGH CPU USAGE

Current: $cpuLoad%
Threshold: $cpuThreshold%
Top Process: $($topProcess.Name) ($([math]::Round($topProcess.CPU, 2))s)
"@
    }
} catch {
    Write-Warning "Failed to get CPU usage: $($_.Exception.Message)"
}

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $memTotal = $os.TotalVisibleMemorySize
    $memFree = $os.FreePhysicalMemory
    $memUsedPercent = [math]::Round((($memTotal - $memFree) / $memTotal) * 100, 1)

    if ($memUsedPercent -ge $memoryThreshold) {
        $topProcess = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 1
        $topProcessMem = [math]::Round($topProcess.WorkingSet64 / 1MB, 2)

        $alerts += @"
[WARNING] HIGH MEMORY USAGE

Current: $memUsedPercent%
Threshold: $memoryThreshold%
Top Process: $($topProcess.Name) ($topProcessMem MB)
"@
    }
} catch {
    Write-Warning "Failed to get memory usage: $($_.Exception.Message)"
}

try {
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($disk in $disks) {
        if ($disk.Size -le 0) {
            continue
        }

        $diskUsedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)
        $diskFreeGB = [math]::Round($disk.FreeSpace / 1GB, 2)

        if ($diskUsedPercent -ge $diskThreshold) {
            $alerts += @"
[WARNING] LOW DISK SPACE

Drive: $($disk.DeviceID)
Used: $diskUsedPercent%
Free: $diskFreeGB GB
Threshold: $diskThreshold%
"@
        }
    }
} catch {
    Write-Warning "Failed to get disk space: $($_.Exception.Message)"
}

try {
    $pingResult = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction Stop
    if (-not $pingResult) {
        $alerts += "[WARNING] NETWORK CONNECTIVITY ISSUE`n`nPC: $pc`nCannot reach internet`nTime: $time"
    }
} catch {
    $alerts += "[WARNING] NETWORK CONNECTIVITY ISSUE`n`nPC: $pc`nNetwork test failed`nTime: $time"
}

if ($alerts.Count -gt 0) {
    $message = @"
[PERFORMANCE ALERT]

PC: $pc
Time: $time

$($alerts -join "`n`n---`n`n")
"@

    try {
        Send-PcMonitorTelegramMessage -Message $message -Config $config
        Write-PcMonitorActivity -Category "performance" -Action "performance-alert" -Detail "Alerts: $($alerts.Count)" -BasePath $PSScriptRoot
        Write-Host "Performance alert sent at $time"
        exit 0
    } catch {
        Write-Error "Failed to send performance alert: $($_.Exception.Message)"
        exit 1
    }
}

Write-Host "All performance metrics within normal range at $time"
exit 0
