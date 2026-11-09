. (Join-Path $PSScriptRoot "pc_monitor_common.ps1")

try {
    $config = Get-PcMonitorConfig -BasePath $PSScriptRoot
    Initialize-PcMonitorDataPaths -BasePath $PSScriptRoot | Out-Null
} catch {
    Write-Error $_
    exit 1
}

$cpuThreshold    = if ($config.PSObject.Properties.Name -contains "cpuThreshold"    -and $config.cpuThreshold)    { [int]$config.cpuThreshold }    else { 90 }
$memoryThreshold = if ($config.PSObject.Properties.Name -contains "memoryThreshold" -and $config.memoryThreshold) { [int]$config.memoryThreshold } else { 90 }
$diskThreshold   = if ($config.PSObject.Properties.Name -contains "diskThreshold"   -and $config.diskThreshold)   { [int]$config.diskThreshold }   else { 90 }
$tempThreshold   = if ($config.PSObject.Properties.Name -contains "tempThreshold"   -and $config.tempThreshold)   { [int]$config.tempThreshold }   else { 85 }
$cooldownMinutes = if ($config.PSObject.Properties.Name -contains "alertCooldownMinutes" -and $config.alertCooldownMinutes) { [int]$config.alertCooldownMinutes } else { 30 }

$time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$pc   = $env:COMPUTERNAME
$alerts    = [System.Collections.Generic.List[string]]::new()
$firedKeys = [System.Collections.Generic.List[string]]::new()

try {
    $cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    if ($cpuLoad -ge $cpuThreshold -and -not (Test-PcMonitorAlertCooldown -AlertKey "cpu" -CooldownMinutes $cooldownMinutes -BasePath $PSScriptRoot)) {
        $topProcess = Get-Process | Sort-Object CPU -Descending | Select-Object -First 1
        $alerts.Add("[WARNING] HIGH CPU USAGE`n`nCurrent: $cpuLoad%`nThreshold: $cpuThreshold%`nTop Process: $($topProcess.Name) ($([math]::Round($topProcess.CPU, 2))s)")
        $firedKeys.Add("cpu")
    }
} catch {
    Write-Warning "Failed to get CPU usage: $($_.Exception.Message)"
}

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $memTotal = $os.TotalVisibleMemorySize
    $memFree  = $os.FreePhysicalMemory
    $memUsedPercent = [math]::Round((($memTotal - $memFree) / $memTotal) * 100, 1)

    if ($memUsedPercent -ge $memoryThreshold -and -not (Test-PcMonitorAlertCooldown -AlertKey "memory" -CooldownMinutes $cooldownMinutes -BasePath $PSScriptRoot)) {
        $topProcess    = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 1
        $topProcessMem = [math]::Round($topProcess.WorkingSet64 / 1MB, 2)
        $alerts.Add("[WARNING] HIGH MEMORY USAGE`n`nCurrent: $memUsedPercent%`nThreshold: $memoryThreshold%`nTop Process: $($topProcess.Name) ($topProcessMem MB)")
        $firedKeys.Add("memory")
    }
} catch {
    Write-Warning "Failed to get memory usage: $($_.Exception.Message)"
}

try {
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
    foreach ($disk in $disks) {
        if ($disk.Size -le 0) { continue }
        $diskUsedPercent = [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 1)
        $diskFreeGB      = [math]::Round($disk.FreeSpace / 1GB, 2)
        $diskKey         = "disk_$($disk.DeviceID -replace ':','')"

        if ($diskUsedPercent -ge $diskThreshold -and -not (Test-PcMonitorAlertCooldown -AlertKey $diskKey -CooldownMinutes $cooldownMinutes -BasePath $PSScriptRoot)) {
            $alerts.Add("[WARNING] LOW DISK SPACE`n`nDrive: $($disk.DeviceID)`nUsed: $diskUsedPercent%`nFree: $diskFreeGB GB`nThreshold: $diskThreshold%")
            $firedKeys.Add($diskKey)
        }
    }
} catch {
    Write-Warning "Failed to get disk space: $($_.Exception.Message)"
}

try {
    $temps = Get-PcMonitorTemperatureCelsius
    if ($temps) {
        $maxTemp = ($temps | Measure-Object -Maximum).Maximum
        if ($maxTemp -ge $tempThreshold -and -not (Test-PcMonitorAlertCooldown -AlertKey "temperature" -CooldownMinutes $cooldownMinutes -BasePath $PSScriptRoot)) {
            $deg = [char]176
            $alerts.Add("[WARNING] HIGH TEMPERATURE`n`nMax: $maxTemp${deg}C`nThreshold: $tempThreshold${deg}C`nAll zones: $(($temps | ForEach-Object { "$_${deg}C" }) -join ' / ')")
            $firedKeys.Add("temperature")
        }
    }
} catch {}

try {
    if (-not (Test-PcMonitorAlertCooldown -AlertKey "network" -CooldownMinutes $cooldownMinutes -BasePath $PSScriptRoot)) {
        $pingResult = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction Stop
        if (-not $pingResult) {
            $alerts.Add("[WARNING] NETWORK CONNECTIVITY ISSUE`n`nPC: $pc`nCannot reach internet`nTime: $time")
            $firedKeys.Add("network")
        }
    }
} catch {
    if (-not (Test-PcMonitorAlertCooldown -AlertKey "network" -CooldownMinutes $cooldownMinutes -BasePath $PSScriptRoot)) {
        $alerts.Add("[WARNING] NETWORK CONNECTIVITY ISSUE`n`nPC: $pc`nNetwork test failed`nTime: $time")
        $firedKeys.Add("network")
    }
}

if ($alerts.Count -gt 0) {
    $message = "[PERFORMANCE ALERT]`n`nPC: $pc`nTime: $time`n`n" + ($alerts -join "`n`n---`n`n")

    try {
        Send-PcMonitorTelegramMessage -Message $message -Config $config
        Write-PcMonitorActivity -Category "performance" -Action "performance-alert" -Detail "Alerts: $($alerts.Count)" -BasePath $PSScriptRoot
        foreach ($key in $firedKeys) {
            Update-PcMonitorAlertCooldown -AlertKey $key -BasePath $PSScriptRoot
        }
        Write-Host "Performance alert sent at $time"
        exit 0
    } catch {
        Write-Error "Failed to send performance alert: $($_.Exception.Message)"
        exit 1
    }
}

Write-Host "All performance metrics within normal range at $time"
exit 0
