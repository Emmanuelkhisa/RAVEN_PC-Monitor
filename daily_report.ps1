param(
    [ValidateSet("daily", "weekly")]
    [string]$ReportType = "daily"
)

. (Join-Path $PSScriptRoot "pc_monitor_common.ps1")

try {
    $config = Get-PcMonitorConfig -BasePath $PSScriptRoot
    Initialize-PcMonitorDataPaths -BasePath $PSScriptRoot | Out-Null
} catch {
    Write-Error $_
    exit 1
}

$endTime = Get-Date
if ($ReportType -eq "weekly") {
    $startTime = $endTime.AddDays(-7)
    $reportTitle = "WEEKLY REPORT"
} else {
    $startTime = $endTime.AddDays(-1)
    $reportTitle = "DAILY REPORT"
}

$pc = $env:COMPUTERNAME
$time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$os = Get-CimInstance Win32_OperatingSystem
$uptime = (Get-Date) - $os.LastBootUpTime

$memTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$memFree = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$memUsed = [math]::Round($memTotal - $memFree, 2)
$memPercent = [math]::Round(($memUsed / $memTotal) * 100, 1)

$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$diskTotal = [math]::Round($disk.Size / 1GB, 2)
$diskFree = [math]::Round($disk.FreeSpace / 1GB, 2)
$diskUsed = [math]::Round($diskTotal - $diskFree, 2)
$diskPercent = [math]::Round(($diskUsed / $diskTotal) * 100, 1)

try {
    $successfulLogins = (Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        ID        = 4624
        StartTime = $startTime
    } -ErrorAction SilentlyContinue | Where-Object {
        $xml = [xml]$_.ToXml()
        $logonType = $xml.Event.EventData.Data | Where-Object { $_.Name -eq 'LogonType' } | Select-Object -ExpandProperty '#text'
        $logonType -in @("2", "7", "10", "11")
    }).Count

    $failedLogins = (Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        ID        = 4625
        StartTime = $startTime
    } -ErrorAction SilentlyContinue).Count

    $logClears = (Get-WinEvent -FilterHashtable @{
        LogName   = 'Security'
        ID        = 1102
        StartTime = $startTime
    } -ErrorAction SilentlyContinue).Count
} catch {
    $successfulLogins = "N/A"
    $failedLogins = "N/A"
    $logClears = "N/A"
}

try {
    $systemStartups = (Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        ID        = 6005
        StartTime = $startTime
    } -ErrorAction SilentlyContinue).Count

    $systemShutdowns = (Get-WinEvent -FilterHashtable @{
        LogName   = 'System'
        ID        = 6006
        StartTime = $startTime
    } -ErrorAction SilentlyContinue).Count

    $criticalErrors = (Get-WinEvent -FilterHashtable @{
        LogName   = 'System', 'Application'
        Level     = 1, 2
        StartTime = $startTime
    } -ErrorAction SilentlyContinue).Count
} catch {
    $systemStartups = "N/A"
    $systemShutdowns = "N/A"
    $criticalErrors = "N/A"
}

$topProcesses = Get-Process |
    Sort-Object @{ Expression = {
        if ($null -eq $_.CPU) {
            return 0
        }
        if ($_.CPU -is [TimeSpan]) {
            return $_.CPU.TotalSeconds
        }
        return [double]$_.CPU
    } } -Descending |
    Select-Object -First 5
$processList = ""
foreach ($proc in $topProcesses) {
    if ($proc.CPU -is [TimeSpan]) {
        $cpu = [math]::Round($proc.CPU.TotalSeconds, 2)
    } elseif ($null -ne $proc.CPU) {
        $cpu = [math]::Round([double]$proc.CPU, 2)
    } else {
        $cpu = 0
    }
    $processList += "`n  - $($proc.Name): $cpu s"
}

$activityEntries = @(Get-PcMonitorRecentActivity -BasePath $PSScriptRoot -Count 8)
$activitySummary = if ($activityEntries.Count -gt 0) {
    ($activityEntries | ForEach-Object {
        "  - $($_.Timestamp) | $($_.Category) | $($_.Action)"
    }) -join "`n"
} else {
    "  - No activity logged yet"
}

$report = @"
[$reportTitle]

PC: $pc
Report Time: $time
Period: $(Get-Date $startTime -Format 'yyyy-MM-dd HH:mm') to $(Get-Date $endTime -Format 'yyyy-MM-dd HH:mm')

=== SYSTEM STATUS ===
OS: $($os.Caption)
Uptime: $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m
Memory: $memUsed GB / $memTotal GB ($memPercent%)
Disk C: $diskUsed GB / $diskTotal GB ($diskPercent%)

=== SECURITY EVENTS ===
Successful Logins: $successfulLogins
Failed Login Attempts: $failedLogins
Log Clears: $logClears

=== SYSTEM EVENTS ===
Startups: $systemStartups
Shutdowns: $systemShutdowns
Critical Errors: $criticalErrors

=== TOP PROCESSES (CPU) ===$processList

=== COMMAND CENTRE ACTIVITY ===
$activitySummary
"@

try {
    Send-PcMonitorTelegramMessage -Message $report -Config $config
    Write-PcMonitorActivity -Category "report" -Action "$ReportType-report" -Detail "Report sent" -BasePath $PSScriptRoot
    Write-Host "$ReportType report sent successfully at $time"
    exit 0
} catch {
    Write-Error "Failed to send $ReportType report: $($_.Exception.Message)"
    exit 1
}
