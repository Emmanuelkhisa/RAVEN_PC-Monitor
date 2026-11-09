. (Join-Path $PSScriptRoot "pc_monitor_common.ps1")
. (Join-Path $PSScriptRoot "pc_monitor_network_inventory.ps1")

try {
    $config = Get-PcMonitorConfig -BasePath $PSScriptRoot
    Initialize-PcMonitorDataPaths -BasePath $PSScriptRoot | Out-Null
} catch {
    Write-Error $_
    exit 1
}

$script:BotInstanceMutex = $null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ("NativeMethods" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class NativeMethods
{
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
}
"@
}

function Send-BotMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Send-PcMonitorTelegramMessage -Message $Message -Config $config
}

function Write-BotActivity {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,
        [string]$Detail = ""
    )

    Write-PcMonitorActivity -Category "bot" -Action $Action -Detail $Detail -BasePath $PSScriptRoot
}

function Acquire-BotInstanceLock {
    $mutexName = "Global\RemotePcMonitorBotListener"
    $createdNew = $false
    $script:BotInstanceMutex = New-Object System.Threading.Mutex($true, $mutexName, [ref]$createdNew)

    if (-not $createdNew) {
        throw "Another bot listener instance is already running."
    }
}

function Release-BotInstanceLock {
    if ($script:BotInstanceMutex) {
        try {
            $script:BotInstanceMutex.ReleaseMutex()
        } catch {
        }

        $script:BotInstanceMutex.Dispose()
        $script:BotInstanceMutex = $null
    }
}

function Reset-TelegramWebhook {
    try {
        [void](Invoke-RestMethod -Uri "https://api.telegram.org/bot$($config.botToken)/deleteWebhook?drop_pending_updates=false" -Method Post -ErrorAction Stop)
        Write-BotActivity -Action "webhook-reset"
    } catch {
        Write-BotActivity -Action "webhook-reset-failed" -Detail $_.Exception.Message
    }
}

function Get-CommandArgument {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    if ($Text -match "^\S+\s+(.+)$") {
        return $Matches[1].Trim()
    }

    return ""
}

function Get-SystemStatus {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
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

    $activeWindow = Get-ActiveWindowTitle
    $primaryIP = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.InterfaceAlias -notmatch "Loopback" } |
        Select-Object -First 1 -ExpandProperty IPAddress)

    $tempLine = ""
    try {
        $temps = Get-PcMonitorTemperatureCelsius
        if ($temps) {
            $deg      = [char]176
            $tempLine = "`nTemperature: $(($temps | ForEach-Object { "$_${deg}C" }) -join ' / ')"
        }
    } catch {}

    return @"
[COMMAND CENTRE STATUS]

PC: $env:COMPUTERNAME
User: $env:USERNAME
OS: $($os.Caption)
Uptime: $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m
IP: $(if ($primaryIP) { $primaryIP } else { "Unknown" })
Active Window: $activeWindow

CPU: $($cpu.Name)
Load: $([math]::Round($cpu.LoadPercentage, 1))%
Memory: $memUsed GB / $memTotal GB ($memPercent%)
Disk C: $diskUsed GB / $diskTotal GB ($diskPercent%)$tempLine
"@
}

function Get-TopProcesses {
    $processes = Get-Process |
        Sort-Object @{ Expression = {
            if ($null -eq $_.CPU) { return 0 }
            if ($_.CPU -is [TimeSpan]) { return $_.CPU.TotalSeconds }
            return [double]$_.CPU
        } } -Descending |
        Select-Object -First 10

    $output = "[TOP 10 PROCESSES BY CPU]`n`n"
    foreach ($proc in $processes) {
        if ($proc.CPU -is [TimeSpan]) {
            $cpu = [math]::Round($proc.CPU.TotalSeconds, 2)
        } elseif ($null -ne $proc.CPU) {
            $cpu = [math]::Round([double]$proc.CPU, 2)
        } else {
            $cpu = 0
        }

        $mem = [math]::Round($proc.WorkingSet64 / 1MB, 2)
        $output += "$($proc.Name) - CPU: $cpu s, RAM: $mem MB`n"
    }

    return $output.TrimEnd()
}

function Get-Screenshot {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

    try {
        $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
        $screenshotPath = Join-Path $env:TEMP "screenshot_$(Get-Date -Format 'yyyyMMdd_HHmmss').png"
        $bitmap.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
        return $screenshotPath
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-ActiveWindowTitle {
    $handle = [NativeMethods]::GetForegroundWindow()
    if ($handle -eq [IntPtr]::Zero) {
        return "Unknown"
    }

    $builder = New-Object System.Text.StringBuilder 512
    [void][NativeMethods]::GetWindowText($handle, $builder, $builder.Capacity)
    if ([string]::IsNullOrWhiteSpace($builder.ToString())) {
        return "Unknown"
    }

    return $builder.ToString()
}

function Get-ClipboardSnapshot {
    try {
        $text = Get-Clipboard -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($text)) {
            return "[CLIPBOARD] Empty"
        }

        if ($text.Length -gt 500) {
            $text = $text.Substring(0, 500) + "..."
        }

        return "[CLIPBOARD]`n`n$text"
    } catch {
        return "[CLIPBOARD] Clipboard unavailable in this session."
    }
}

function Set-RemoteClipboard {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    Set-Clipboard -Value $Text
}

function Type-RemoteText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    [System.Windows.Forms.SendKeys]::SendWait($Text)
}

function Get-DirectoryListing {
    param(
        [string]$InputPath = "downloads"
    )

    $resolvedPath = Resolve-PcMonitorPath -InputPath $InputPath -BasePath $PSScriptRoot
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        throw "Path not found: $resolvedPath"
    }

    $items = Get-ChildItem -LiteralPath $resolvedPath -Force |
        Sort-Object -Property @{ Expression = { $_.PSIsContainer }; Descending = $true }, @{ Expression = { $_.LastWriteTime }; Descending = $true } |
        Select-Object -First 20

    $output = "[FILES] $resolvedPath`n`n"
    foreach ($item in $items) {
        $label = if ($item.PSIsContainer) { "[DIR]" } else { "[FILE]" }
        $size = if ($item.PSIsContainer) { "-" } else { "{0:N2} MB" -f ($item.Length / 1MB) }
        $output += "$label $($item.Name) | $size | $($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))`n"
    }

    return $output.TrimEnd()
}

function Find-RemoteFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [string]$RootPath = "downloads"
    )

    $resolvedRoot = Resolve-PcMonitorPath -InputPath $RootPath -BasePath $PSScriptRoot
    if (-not (Test-Path -LiteralPath $resolvedRoot)) {
        throw "Search root not found: $resolvedRoot"
    }

    $matches = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*$Pattern*" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 10)

    if ($matches.Count -eq 0) {
        return "[SEARCH] No files matched '$Pattern' in $resolvedRoot"
    }

    $output = "[SEARCH] Matches for '$Pattern' in $resolvedRoot`n`n"
    foreach ($match in $matches) {
        $output += "$($match.FullName)`n"
    }

    return $output.TrimEnd()
}

function Get-InboxListing {
    param(
        [int]$Count = 10
    )

    $inboxPath = Get-PcMonitorDataPath -BasePath $PSScriptRoot -ChildPath "incoming"
    $items = @(Get-ChildItem -LiteralPath $inboxPath -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Count)

    if ($items.Count -eq 0) {
        return "[INBOX] No uploaded files yet."
    }

    $output = "[INBOX] Recent uploaded files`n`n"
    foreach ($item in $items) {
        $output += "$($item.Name) | {0:N2} MB | $($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))`n" -f ($item.Length / 1MB)
    }

    return $output.TrimEnd()
}

function Get-RecentFileChanges {
    param(
        [int]$Count = 10
    )

    $paths = Get-PcMonitorKnownLocations
    $items = foreach ($path in $paths.Values) {
        if (Test-Path -LiteralPath $path) {
            Get-ChildItem -LiteralPath $path -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 5
        }
    }

    $recent = @($items | Sort-Object LastWriteTime -Descending | Select-Object -First $Count)
    if ($recent.Count -eq 0) {
        return "[RECENT CHANGES] No recent files found."
    }

    $output = "[RECENT CHANGES]`n`n"
    foreach ($item in $recent) {
        $output += "$($item.FullName) | $($item.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))`n"
    }

    return $output.TrimEnd()
}

function Get-HistoryReport {
    param(
        [int]$Count = 12
    )

    $entries = @(Get-PcMonitorRecentActivity -BasePath $PSScriptRoot -Count $Count)
    if ($entries.Count -eq 0) {
        return "[HISTORY] No activity logged yet."
    }

    $output = "[HISTORY]`n`n"
    foreach ($entry in $entries) {
        $output += "$($entry.Timestamp) | $($entry.Category) | $($entry.Action) | $($entry.Detail)`n"
    }

    return $output.TrimEnd()
}

function Send-RemoteFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath
    )

    $resolvedPath = Resolve-PcMonitorPath -InputPath $InputPath -BasePath $PSScriptRoot
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        throw "File not found: $resolvedPath"
    }

    Send-PcMonitorTelegramDocument -FilePath $resolvedPath -Config $config -Caption $resolvedPath
    Write-BotActivity -Action "pull-file" -Detail $resolvedPath
}

function Open-RemoteTarget {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    Start-Process $Target | Out-Null
    Write-BotActivity -Action "open-target" -Detail $Target
}

function Invoke-RoutineSnapshot {
    Write-BotActivity -Action "routine-snapshot"
    Send-BotMessage -Message (Get-SystemStatus)
    Send-BotMessage -Message (Get-ClipboardSnapshot)

    $screenshotPath = $null
    try {
        $screenshotPath = Get-Screenshot
        Send-PcMonitorTelegramPhoto -PhotoPath $screenshotPath -Config $config -Caption "Routine snapshot: $(Get-ActiveWindowTitle)"
    } finally {
        if ($screenshotPath -and (Test-Path -LiteralPath $screenshotPath)) {
            Remove-Item -LiteralPath $screenshotPath -Force
        }
    }
}

function Invoke-RoutineWorkspace {
    Write-BotActivity -Action "routine-workspace"
    Send-BotMessage -Message (Get-SystemStatus)
    Send-BotMessage -Message (Get-TopProcesses)
    Send-BotMessage -Message (Get-RecentFileChanges -Count 8)
}

function Get-FfmpegPath {
    return Get-PcMonitorFfmpegPath -Config $config
}

function Test-MediaDeviceAvailability {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("video", "audio")]
        [string]$DeviceType,
        [Parameter(Mandatory = $true)]
        [string]$ConfiguredName
    )

    $devices = Get-PcMonitorDirectShowDevices -Config $config
    $available = if ($DeviceType -eq "video") { @($devices.Video) } else { @($devices.Audio) }
    $match = $available | Where-Object { $_ -ieq $ConfiguredName } | Select-Object -First 1

    if ($match) {
        return $match
    }

    $availableList = if ($available.Count -gt 0) { $available -join ", " } else { "None detected" }
    throw "Configured $DeviceType device '$ConfiguredName' was not found. Available $DeviceType devices: $availableList"
}

function Get-CameraSnapshot {
    $ffmpegPath = Get-FfmpegPath
    if (-not $ffmpegPath) {
        throw "ffmpeg is not installed on this PC."
    }

    if (-not ($config.PSObject.Properties.Name -contains "cameraDeviceName") -or [string]::IsNullOrWhiteSpace($config.cameraDeviceName)) {
        throw "cameraDeviceName is not configured in config.json."
    }

    $cameraDeviceName = Test-MediaDeviceAvailability -DeviceType video -ConfiguredName $config.cameraDeviceName
    $targetPath = Join-Path $env:TEMP "camera_$(Get-Date -Format 'yyyyMMdd_HHmmss').jpg"
    $stderrPath = Join-Path $env:TEMP "camera_capture_$([guid]::NewGuid().ToString('N')).log"
    try {
        & $ffmpegPath -hide_banner -y -f dshow -i "video=$cameraDeviceName" -frames:v 1 $targetPath 2>$stderrPath | Out-Null
        if (-not (Test-Path -LiteralPath $targetPath)) {
            $ffmpegError = if (Test-Path -LiteralPath $stderrPath) {
                (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue).Trim()
            } else {
                ""
            }

            if ([string]::IsNullOrWhiteSpace($ffmpegError)) {
                throw "Failed to capture camera snapshot."
            }

            throw "Failed to capture camera snapshot. ffmpeg: $ffmpegError"
        }
    } finally {
        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-BotActivity -Action "camera-snapshot" -Detail $cameraDeviceName
    return $targetPath
}

function Record-MicrophoneClip {
    param(
        [int]$Seconds = 60
    )

    if ($Seconds -lt 3) {
        $Seconds = 3
    }
    if ($Seconds -gt 60) {
        $Seconds = 60
    }

    $ffmpegPath = Get-FfmpegPath
    if (-not $ffmpegPath) {
        throw "ffmpeg is not installed on this PC."
    }

    if (-not ($config.PSObject.Properties.Name -contains "microphoneDeviceName") -or [string]::IsNullOrWhiteSpace($config.microphoneDeviceName)) {
        throw "microphoneDeviceName is not configured in config.json."
    }

    $microphoneDeviceName = Test-MediaDeviceAvailability -DeviceType audio -ConfiguredName $config.microphoneDeviceName
    $targetPath = Join-Path $env:TEMP "mic_$(Get-Date -Format 'yyyyMMdd_HHmmss').wav"
    $stderrPath = Join-Path $env:TEMP "mic_capture_$([guid]::NewGuid().ToString('N')).log"
    try {
        & $ffmpegPath -hide_banner -y -f dshow -i "audio=$microphoneDeviceName" -t $Seconds $targetPath 2>$stderrPath | Out-Null
        if (-not (Test-Path -LiteralPath $targetPath)) {
            $ffmpegError = if (Test-Path -LiteralPath $stderrPath) {
                (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue).Trim()
            } else {
                ""
            }

            if ([string]::IsNullOrWhiteSpace($ffmpegError)) {
                throw "Failed to record microphone clip."
            }

            throw "Failed to record microphone clip. ffmpeg: $ffmpegError"
        }
    } finally {
        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-BotActivity -Action "microphone-recording" -Detail "$Seconds seconds"
    return $targetPath
}

function Format-CommandOutput {
    param(
        [string]$Output,
        [int]$MaxLength = 3500
    )

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return "[NO OUTPUT]"
    }

    $trimmed = $Output.Trim()
    if ($trimmed.Length -le $MaxLength) {
        return $trimmed
    }

    return $trimmed.Substring(0, $MaxLength) + "`n...[truncated]"
}

function Invoke-RemotePowerShell {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $output = powershell -NoProfile -ExecutionPolicy Bypass -Command $Command 2>&1 | Out-String
    Write-BotActivity -Action "powershell-command" -Detail $Command
    return "[POWERSHELL]`n`n$(Format-CommandOutput -Output $output)"
}

function Invoke-RemoteCmd {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $output = cmd.exe /c $Command 2>&1 | Out-String
    Write-BotActivity -Action "cmd-command" -Detail $Command
    return "[CMD]`n`n$(Format-CommandOutput -Output $output)"
}

function Handle-IncomingDocument {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Message
    )

    $destination = $null
    $caption = [string]$Message.caption

    if ($caption -match "^/save\s+(.+)$") {
        $destination = Resolve-PcMonitorPath -InputPath $Matches[1] -BasePath $PSScriptRoot
    }

    $savedPath = Save-PcMonitorTelegramDocument -Document $Message.document -Config $config -DestinationDirectory $destination -BasePath $PSScriptRoot
    Write-BotActivity -Action "receive-file" -Detail $savedPath
    Send-BotMessage -Message "[RECEIVED] Saved to $savedPath"
}

function Lock-PC {
    rundll32.exe user32.dll,LockWorkStation
    Write-BotActivity -Action "lock-pc"
}

function Shutdown-PC {
    Write-BotActivity -Action "shutdown-pc"
    Stop-Computer -Force
}

function Restart-PC {
    Write-BotActivity -Action "restart-pc"
    Restart-Computer -Force
}

function Suspend-PC {
    Write-BotActivity -Action "sleep-pc"
    rundll32.exe powrprof.dll,SetSuspendState 0,1,0
}

function Send-InlineConfirmation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [Parameter(Mandatory = $true)]
        [string]$ConfirmData
    )

    $url  = "https://api.telegram.org/bot$($config.botToken)/sendMessage"
    $body = [ordered]@{
        chat_id      = "$($config.chatID)"
        text         = $Prompt
        reply_markup = @{
            inline_keyboard = @(
                @(
                    @{ text = "Yes, proceed"; callback_data = $ConfirmData },
                    @{ text = "Cancel";       callback_data = "cancel" }
                )
            )
        }
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json; charset=utf-8" -ErrorAction Stop | Out-Null
}

function Confirm-CallbackQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CallbackQueryId,
        [string]$Text = ""
    )

    $url  = "https://api.telegram.org/bot$($config.botToken)/answerCallbackQuery"
    $body = @{ callback_query_id = $CallbackQueryId }
    if ($Text) { $body.text = $Text }
    Invoke-RestMethod -Uri $url -Method Post -Body ($body | ConvertTo-Json) -ContentType "application/json; charset=utf-8" -ErrorAction SilentlyContinue | Out-Null
}

function Kill-RemoteProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    $killed = [System.Collections.Generic.List[string]]::new()
    $failed = [System.Collections.Generic.List[string]]::new()

    if ($Target -match '^\d+$') {
        $pid = [int]$Target
        try {
            Stop-Process -Id $pid -Force -ErrorAction Stop
            $killed.Add("PID $pid")
        } catch {
            $failed.Add("PID $pid`: $($_.Exception.Message)")
        }
    } else {
        $procs = @(Get-Process -Name $Target -ErrorAction SilentlyContinue)
        if ($procs.Count -eq 0) {
            return "[ERROR] No process found matching: $Target"
        }
        foreach ($p in $procs) {
            try {
                Stop-Process -Id $p.Id -Force -ErrorAction Stop
                $killed.Add("$($p.Name) (PID $($p.Id))")
            } catch {
                $failed.Add("$($p.Name) (PID $($p.Id))`: $($_.Exception.Message)")
            }
        }
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    if ($killed.Count -gt 0) { $parts.Add("[KILLED]`n" + ($killed -join "`n")) }
    if ($failed.Count -gt 0) { $parts.Add("[FAILED]`n" + ($failed -join "`n")) }
    Write-BotActivity -Action "kill-process" -Detail $Target
    return ($parts -join "`n`n").Trim()
}

function Get-TasksStatus {
    $taskDefs = Get-PcMonitorTaskDefinitions
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("[SCHEDULED TASKS]")
    $lines.Add("")

    foreach ($td in $taskDefs) {
        $shortName = Split-Path $td.TaskName -Leaf
        try {
            $taskPath = "\PC Monitor\"
            $info    = Get-ScheduledTaskInfo -TaskPath $taskPath -TaskName $shortName -ErrorAction Stop
            $taskObj = Get-ScheduledTask -TaskPath $taskPath -TaskName $shortName -ErrorAction Stop
            $state   = $taskObj.State
            $lastRun = if ($info.LastRunTime -and $info.LastRunTime -gt [datetime]"2000-01-01") {
                $info.LastRunTime.ToString("MM-dd HH:mm")
            } else { "Never" }
            $code   = $info.LastTaskResult
            $result = if ($code -eq 0) { "OK" } elseif ($code -eq 267009) { "Running" } else { "Err 0x{0:X8}" -f $code }
            $lines.Add("$shortName | $state | $lastRun | $result")
        } catch {
            $lines.Add("$shortName | Not installed")
        }
    }

    Write-BotActivity -Action "tasks-status"
    return ($lines -join "`n")
}

function Register-UsbMonitor {
    try {
        $query     = "SELECT * FROM __InstanceCreationEvent WITHIN 3 WHERE TargetInstance ISA 'Win32_LogicalDisk' AND TargetInstance.DriveType = 2"
        $configJson = $config | ConvertTo-Json -Compress
        Register-WmiEvent -Query $query -SourceIdentifier "PcMonitorUsbWatch" -Action {
            try {
                $cfg    = $Event.MessageData | ConvertFrom-Json
                $disk   = $EventArgs.NewEvent.TargetInstance
                $letter = if ($disk.DeviceID) { $disk.DeviceID } else { "?" }
                $label  = if ($disk.VolumeName) { $disk.VolumeName } else { "No Label" }
                $sizeGB = [math]::Round([double]$disk.Size / 1GB, 2)
                $msg    = "[ALERT] USB REMOVABLE DRIVE CONNECTED`n`nDrive: $letter ($label)`nSize: $sizeGB GB`nPC: $env:COMPUTERNAME`nTime: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                $url    = "https://api.telegram.org/bot$($cfg.botToken)/sendMessage"
                $body   = @{ chat_id = "$($cfg.chatID)"; text = $msg } | ConvertTo-Json
                Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json; charset=utf-8" | Out-Null
            } catch {}
        } -MessageData $configJson | Out-Null
        Write-BotActivity -Action "usb-monitor-registered"
    } catch {
        Write-Warning "USB monitoring unavailable: $($_.Exception.Message)"
    }
}

function Get-HelpText {
    return @"
PC Monitor Command Centre v3

Observe
/status
/inventory
/screenshot
/camera
/recordmic 60
/active
/clipboard
/processes

Move Data
/ls downloads
/find invoice downloads
/pull downloads\file.txt
/inbox 10
Send a Telegram document to save it to the PC inbox.
Caption it with /save documents to place it elsewhere.

Control
/kill chrome.exe  or  /kill 1234
/open notepad
/setclipboard hello world
/type hello world
/run Get-Service  (PowerShell)
/ps Get-Process | Select-Object -First 5
/cmd dir
/lock
/sleep
/shutdown
/restart

Automate
/routine snapshot
/routine workspace

Review
/history 12
/recent 10
/tasks
"@
}

$lastUpdateId = 0

Write-Host "[INFO] Bot command listener started. Press Ctrl+C to stop."
Write-Host "[INFO] Waiting for commands from Telegram..."
try {
    Acquire-BotInstanceLock
    Reset-TelegramWebhook
    Register-UsbMonitor
    Write-BotActivity -Action "bot-listener-started"
} catch {
    Write-Error $_
    Write-BotActivity -Action "bot-listener-exit" -Detail $_.Exception.Message
    exit 1
}

try {
    while ($true) {
        try {
            $url = "https://api.telegram.org/bot$($config.botToken)/getUpdates?offset=$($lastUpdateId + 1)&timeout=30"
            $updates = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop

            foreach ($update in $updates.result) {
                $lastUpdateId = $update.update_id

                if (($update.PSObject.Properties.Name -contains "callback_query") -and $null -ne $update.callback_query) {
                    $cbq = $update.callback_query
                    if (Test-PcMonitorAuthorizedChat -ChatId "$($cbq.from.id)" -Config $config) {
                        try { Confirm-CallbackQuery -CallbackQueryId $cbq.id } catch {}
                        Write-BotActivity -Action "callback-query" -Detail $cbq.data

                        switch ($cbq.data) {
                            "confirm_shutdown" { Send-BotMessage -Message "[EXECUTED] PC shutting down..."; Start-Sleep -Seconds 2; Shutdown-PC }
                            "confirm_restart"  { Send-BotMessage -Message "[EXECUTED] PC restarting...";   Start-Sleep -Seconds 2; Restart-PC }
                            "confirm_sleep"    { Send-BotMessage -Message "[EXECUTED] PC entering sleep";  Start-Sleep -Seconds 2; Suspend-PC }
                            "cancel"           { Send-BotMessage -Message "[CANCELLED] Action aborted." }
                        }
                    }
                    continue
                }

                $message = $null
                if (($update.PSObject.Properties.Name -contains "message") -and $null -ne $update.message) {
                    $message = $update.message
                } elseif (($update.PSObject.Properties.Name -contains "edited_message") -and $null -ne $update.edited_message) {
                    $message = $update.edited_message
                }

                if ($null -eq $message) {
                    continue
                }

                if (($message.PSObject.Properties.Name -notcontains "chat") -or -not (Test-PcMonitorAuthorizedChat -ChatId "$($message.chat.id)" -Config $config)) {
                    continue
                }

                $hasDocument = ($message.PSObject.Properties.Name -contains "document") -and $null -ne $message.document
                if ($hasDocument) {
                    Handle-IncomingDocument -Message $message
                    continue
                }

                $command = [string]$message.text
                if ([string]::IsNullOrWhiteSpace($command)) {
                    continue
                }

                Write-Host "[CMD] Received: $command"
                Write-BotActivity -Action "command-received" -Detail $command

                switch -Regex ($command) {
                    "^/start$|^/help$" {
                        Send-BotMessage -Message (Get-HelpText)
                    }
                    "^/status$" {
                        Send-BotMessage -Message (Get-SystemStatus)
                    }
                    "^/inventory$" {
                        $reportPath = $null
                        try {
                            $inventory = New-PcMonitorNetworkInventoryReport -BasePath $PSScriptRoot -PingNeighbors
                            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                            $reportPath = Join-Path (Get-PcMonitorDataPath -BasePath $PSScriptRoot -ChildPath "outgoing") "network-inventory-$timestamp.txt"
                            Set-Content -LiteralPath $reportPath -Value $inventory.Content -Encoding UTF8
                            $caption = "Network inventory for $env:COMPUTERNAME. Neighbor-cache entries pinged: $($inventory.CurrentDeviceCount); routes: $($inventory.RouteCount). No ICMP reply does not prove a device is offline."
                            Send-PcMonitorTelegramDocument -FilePath $reportPath -Config $config -Caption $caption
                            Write-BotActivity -Action "network-inventory-report" -Detail "Neighbor entries: $($inventory.CurrentDeviceCount); routes: $($inventory.RouteCount)"
                        } finally {
                            if ($reportPath -and (Test-Path -LiteralPath $reportPath)) {
                                Remove-Item -LiteralPath $reportPath -Force
                            }
                        }
                    }
                    "^/screenshot$" {
                        $screenshotPath = $null
                        try {
                            $screenshotPath = Get-Screenshot
                            Send-PcMonitorTelegramPhoto -PhotoPath $screenshotPath -Config $config -Caption (Get-ActiveWindowTitle)
                            Write-BotActivity -Action "screenshot"
                        } finally {
                            if ($screenshotPath -and (Test-Path -LiteralPath $screenshotPath)) {
                                Remove-Item -LiteralPath $screenshotPath -Force
                            }
                        }
                    }
                    "^/camera$" {
                        $cameraPath = $null
                        try {
                            $cameraPath = Get-CameraSnapshot
                            Send-PcMonitorTelegramDocument -FilePath $cameraPath -Config $config -Caption "Camera snapshot"
                        } finally {
                            if ($cameraPath -and (Test-Path -LiteralPath $cameraPath)) {
                                Remove-Item -LiteralPath $cameraPath -Force
                            }
                        }
                    }
                    "^/recordmic(?:\s+(\d+))?$" {
                        $seconds = if ($Matches[1]) { [int]$Matches[1] } else { 60 }
                        $audioPath = $null
                        try {
                            $audioPath = Record-MicrophoneClip -Seconds $seconds
                            Send-PcMonitorTelegramDocument -FilePath $audioPath -Config $config -Caption "Microphone recording ($seconds s)"
                        } finally {
                            if ($audioPath -and (Test-Path -LiteralPath $audioPath)) {
                                Remove-Item -LiteralPath $audioPath -Force
                            }
                        }
                    }
                    "^/active$" {
                        Send-BotMessage -Message "[ACTIVE WINDOW] $(Get-ActiveWindowTitle)"
                    }
                    "^/clipboard$" {
                        Send-BotMessage -Message (Get-ClipboardSnapshot)
                        Write-BotActivity -Action "read-clipboard"
                    }
                    "^/setclipboard\s+(.+)$" {
                        Set-RemoteClipboard -Text $Matches[1]
                        Write-BotActivity -Action "write-clipboard" -Detail $Matches[1]
                        Send-BotMessage -Message "[UPDATED] Clipboard text set."
                    }
                    "^/type\s+(.+)$" {
                        Type-RemoteText -Text $Matches[1]
                        Write-BotActivity -Action "type-text" -Detail $Matches[1]
                        Send-BotMessage -Message "[EXECUTED] Text sent to active window."
                    }
                    "^/processes$" {
                        Send-BotMessage -Message (Get-TopProcesses)
                    }
                    "^/ls(?:\s+(.+))?$" {
                        $pathArg = if ($Matches[1]) { $Matches[1] } else { "downloads" }
                        Send-BotMessage -Message (Get-DirectoryListing -InputPath $pathArg)
                    }
                    "^/find\s+(\S+)(?:\s+(.+))?$" {
                        $pattern = $Matches[1]
                        $rootArg = if ($Matches[2]) { $Matches[2] } else { "downloads" }
                        Send-BotMessage -Message (Find-RemoteFiles -Pattern $pattern -RootPath $rootArg)
                    }
                    "^/pull\s+(.+)$" {
                        Send-RemoteFile -InputPath $Matches[1]
                    }
                    "^/inbox(?:\s+(\d+))?$" {
                        $count = if ($Matches[1]) { [int]$Matches[1] } else { 10 }
                        Send-BotMessage -Message (Get-InboxListing -Count $count)
                    }
                    "^/open\s+(.+)$" {
                        Open-RemoteTarget -Target $Matches[1]
                        Send-BotMessage -Message "[EXECUTED] Opened $($Matches[1])"
                    }
                    "^/kill\s+(.+)$" {
                        Send-BotMessage -Message (Kill-RemoteProcess -Target $Matches[1].Trim())
                    }
                    "^/run\s+(.+)$" {
                        Send-BotMessage -Message (Invoke-RemotePowerShell -Command $Matches[1])
                    }
                    "^/ps\s+(.+)$" {
                        Send-BotMessage -Message (Invoke-RemotePowerShell -Command $Matches[1])
                    }
                    "^/cmd\s+(.+)$" {
                        Send-BotMessage -Message (Invoke-RemoteCmd -Command $Matches[1])
                    }
                    "^/tasks$" {
                        Send-BotMessage -Message (Get-TasksStatus)
                    }
                    "^/lock$" {
                        Send-BotMessage -Message "[EXECUTED] PC locked"
                        Lock-PC
                    }
                    "^/sleep$" {
                        Send-InlineConfirmation -Prompt "Put the PC to sleep?" -ConfirmData "confirm_sleep"
                        Write-BotActivity -Action "confirm-request" -Detail "/sleep"
                    }
                    "^/shutdown$" {
                        Send-InlineConfirmation -Prompt "Shut down the PC?" -ConfirmData "confirm_shutdown"
                        Write-BotActivity -Action "confirm-request" -Detail "/shutdown"
                    }
                    "^/restart$" {
                        Send-InlineConfirmation -Prompt "Restart the PC?" -ConfirmData "confirm_restart"
                        Write-BotActivity -Action "confirm-request" -Detail "/restart"
                    }
                    "^/routine\s+snapshot$" {
                        Invoke-RoutineSnapshot
                    }
                    "^/routine\s+workspace$" {
                        Invoke-RoutineWorkspace
                    }
                    "^/history(?:\s+(\d+))?$" {
                        $count = if ($Matches[1]) { [int]$Matches[1] } else { 12 }
                        Send-BotMessage -Message (Get-HistoryReport -Count $count)
                    }
                    "^/recent(?:\s+(\d+))?$" {
                        $count = if ($Matches[1]) { [int]$Matches[1] } else { 10 }
                        Send-BotMessage -Message (Get-RecentFileChanges -Count $count)
                    }
                    default {
                        if ($command -match "^/") {
                            Send-BotMessage -Message "[ERROR] Unknown command. Use /help."
                        }
                    }
                }
            }
        } catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -match "\(409\)\s+Conflict") {
                Write-Error $errorMessage
                Write-BotActivity -Action "bot-listener-exit" -Detail "Telegram conflict detected. Another bot listener is likely active."
                break
            }

            Write-Error "Error in main loop: $errorMessage"
            Write-BotActivity -Action "bot-loop-error" -Detail $errorMessage
            Start-Sleep -Seconds 5
        }
    }
} finally {
    Release-BotInstanceLock
}
