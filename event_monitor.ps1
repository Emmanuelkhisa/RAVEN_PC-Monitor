param(
    [string]$EventRecordID,
    [string]$LogName
)

. (Join-Path $PSScriptRoot "pc_monitor_common.ps1")

try {
    $config = Get-PcMonitorConfig -BasePath $PSScriptRoot
    Initialize-PcMonitorDataPaths -BasePath $PSScriptRoot | Out-Null
} catch {
    Write-Error $_
    exit 1
}

function Get-EventDetails {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Eventing.Reader.EventRecord]$Event
    )

    $eventXml = [xml]$Event.ToXml()
    $eventData = @{}

    foreach ($data in $eventXml.Event.EventData.Data) {
        $eventData[$data.Name] = $data.'#text'
    }

    return $eventData
}

function Get-TargetEvent {
    if ($EventRecordID -match '^\d+$' -and -not [string]::IsNullOrWhiteSpace($LogName)) {
        try {
            return Get-WinEvent -FilterHashtable @{
                LogName  = $LogName
                RecordID = [long]$EventRecordID
            } -MaxEvents 1 -ErrorAction Stop
        } catch {
            Write-Warning "Could not retrieve event $EventRecordID from $LogName"
        }
    }

    try {
        $recentEvents = @(Get-WinEvent -FilterHashtable @{
            LogName   = 'Security'
            ID        = 4624, 4625, 4800, 4801, 1102
            StartTime = (Get-Date).AddSeconds(-30)
        } -MaxEvents 20 -ErrorAction Stop)

        foreach ($candidate in $recentEvents) {
            if ($candidate.Id -ne 4624) {
                return $candidate
            }

            $candidateData = Get-EventDetails -Event $candidate
            if ($candidateData.LogonType -in @("2", "7", "10", "11")) {
                return $candidate
            }
        }

        return $null
    } catch {
        return $null
    }
}

$event = Get-TargetEvent
if (-not $event) {
    Write-Warning "No event to process"
    exit 0
}

$time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$pc = $env:COMPUTERNAME
$message = ""

switch ($event.Id) {
    4624 {
        $eventData = Get-EventDetails -Event $event
        $logonType = $eventData.LogonType

        if ($logonType -in @("2", "7", "10", "11")) {
            $message = @"
[ALERT] PC LOGIN DETECTED

User: $($eventData.TargetUserName)
PC: $pc
Domain: $($eventData.TargetDomainName)
Logon Type: $(switch ($logonType) {
    "2" { "Interactive (Console)" }
    "7" { "Unlock" }
    "10" { "Remote Desktop" }
    "11" { "Cached Credentials" }
    default { $logonType }
})
Time: $time
"@
        }
    }
    4625 {
        $eventData = Get-EventDetails -Event $event
        $status = $eventData.Status

        $message = @"
[WARNING] FAILED LOGIN ATTEMPT

User: $($eventData.TargetUserName)
PC: $pc
Domain: $($eventData.TargetDomainName)
Workstation: $($eventData.WorkstationName)
Failure Reason: $(switch ($status) {
    "0xC000006D" { "Bad username or password" }
    "0xC000006E" { "Account restriction" }
    "0xC0000064" { "User does not exist" }
    "0xC000006F" { "Logon outside allowed time" }
    "0xC0000070" { "Workstation restriction" }
    "0xC0000071" { "Password expired" }
    "0xC0000072" { "Account disabled" }
    "0xC0000193" { "Account expired" }
    "0xC0000224" { "Password change required" }
    "0xC0000234" { "Account locked out" }
    default { $status }
})
Time: $time
"@
    }
    4688 {
        $eventData = Get-EventDetails -Event $event
        $excludeProcesses = @(
            "conhost.exe", "svchost.exe", "RuntimeBroker.exe",
            "backgroundTaskHost.exe", "taskhostw.exe", "WmiPrvSE.exe"
        )
        $processFileName = Split-Path $eventData.NewProcessName -Leaf

        if ($processFileName -notin $excludeProcesses) {
            $message = @"
[INFO] APPLICATION LAUNCHED

Process: $processFileName
Full Path: $($eventData.NewProcessName)
User: $($eventData.SubjectUserName)
Parent: $(Split-Path $eventData.ParentProcessName -Leaf)
PC: $pc
Time: $time
"@
        }
    }
    4663 {
        $eventData = Get-EventDetails -Event $event
        $message = @"
[INFO] FILE ACCESS DETECTED

File: $($eventData.ObjectName)
User: $($eventData.SubjectUserName)
Access Type: $($eventData.AccessMask)
PC: $pc
Time: $time
"@
    }
    1102 {
        $eventData = Get-EventDetails -Event $event
        $message = @"
[CRITICAL] EVENT LOG CLEARED

User: $($eventData.SubjectUserName)
Domain: $($eventData.SubjectDomainName)
PC: $pc
Time: $time

WARNING: Someone attempted to clear event logs.
"@
    }
    2003 { $message = "[INFO] USB DEVICE CONNECTED`n`nPC: $pc`nTime: $time" }
    2100 { $message = "[INFO] USB DEVICE CONNECTED`n`nPC: $pc`nTime: $time" }
    4800 { $message = "[INFO] WORKSTATION LOCKED`n`nPC: $pc`nUser: $($env:USERNAME)`nTime: $time" }
    4801 { $message = "[INFO] WORKSTATION UNLOCKED`n`nPC: $pc`nUser: $($env:USERNAME)`nTime: $time" }
    6005 { $message = "[INFO] SYSTEM STARTUP`n`nPC: $pc`nTime: $time" }
    6006 { $message = "[INFO] SYSTEM SHUTDOWN`n`nPC: $pc`nTime: $time" }
    default {
        Write-Warning "Unhandled Event ID: $($event.Id)"
    }
}

if (-not [string]::IsNullOrWhiteSpace($message)) {
    try {
        Send-PcMonitorTelegramMessage -Message $message -Config $config
        Write-PcMonitorActivity -Category "event" -Action "event-alert" -Detail "Event ID $($event.Id)" -BasePath $PSScriptRoot
        Write-Host "Alert sent successfully for Event ID $($event.Id) at $time"
        exit 0
    } catch {
        Write-Error "Failed to send alert: $($_.Exception.Message)"
        exit 1
    }
}

Write-Host "No alert generated for Event ID $($event.Id)"
exit 0
