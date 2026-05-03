. (Join-Path $PSScriptRoot "pc_monitor_common.ps1")

try {
    $config = Get-PcMonitorConfig -BasePath $PSScriptRoot
    Initialize-PcMonitorDataPaths -BasePath $PSScriptRoot | Out-Null
} catch {
    Write-Error $_
    exit 1
}

$stateFile = Join-Path $PSScriptRoot "network_state.json"
$time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$pc = $env:COMPUTERNAME

$currentAdapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Select-Object Name, InterfaceDescription, MacAddress)
$currentIPs = @(Get-NetIPAddress -ErrorAction Stop | Where-Object { $_.AddressFamily -eq 'IPv4' -and $_.IPAddress -ne '127.0.0.1' } | Select-Object IPAddress, InterfaceAlias)
$vpnConnections = @(Get-VpnConnection -ErrorAction SilentlyContinue)
$activeVPN = @($vpnConnections | Where-Object { $_.ConnectionStatus -eq 'Connected' })

$currentState = @{
    Adapters  = $currentAdapters
    IPs       = $currentIPs
    VPN       = $activeVPN
    Timestamp = Get-Date
}

if (Test-Path -LiteralPath $stateFile) {
    try {
        $previousState = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $alerts = @()

        $previousAdapterNames = @($previousState.Adapters | ForEach-Object { $_.Name })
        $newAdapters = @($currentAdapters | Where-Object { $_.Name -notin $previousAdapterNames })
        foreach ($adapter in $newAdapters) {
            $alerts += @"
[INFO] NEW NETWORK ADAPTER CONNECTED

Name: $($adapter.Name)
Description: $($adapter.InterfaceDescription)
MAC Address: $($adapter.MacAddress)
"@
        }

        $previousIPs = @($previousState.IPs | ForEach-Object { $_.IPAddress })
        $newIPs = @($currentIPs | Where-Object { $_.IPAddress -notin $previousIPs })
        foreach ($ip in $newIPs) {
            $alerts += @"
[INFO] NEW IP ADDRESS ASSIGNED

IP: $($ip.IPAddress)
Interface: $($ip.InterfaceAlias)
"@
        }

        $previousVpnNames = @($previousState.VPN | ForEach-Object { $_.Name })
        $activeVpnNames = @($activeVPN | ForEach-Object { $_.Name })

        foreach ($vpn in $activeVPN) {
            if ($vpn.Name -notin $previousVpnNames) {
                $alerts += @"
[INFO] VPN CONNECTED

Name: $($vpn.Name)
Server: $($vpn.ServerAddress)
"@
            }
        }

        foreach ($vpnName in $previousVpnNames) {
            if ($vpnName -notin $activeVpnNames) {
                $alerts += @"
[INFO] VPN DISCONNECTED

Previous: $vpnName
"@
            }
        }

        if ($alerts.Count -gt 0) {
            $message = @"
[NETWORK ACTIVITY]

PC: $pc
Time: $time

$($alerts -join "`n`n---`n`n")
"@
            Send-PcMonitorTelegramMessage -Message $message -Config $config
            Write-PcMonitorActivity -Category "network" -Action "network-alert" -Detail "Alerts: $($alerts.Count)" -BasePath $PSScriptRoot
        }
    } catch {
        Write-Warning "Failed to compare network states: $($_.Exception.Message)"
    }
}

try {
    $currentState | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $stateFile -Encoding UTF8
} catch {
    Write-Warning "Failed to save network state: $($_.Exception.Message)"
}

Write-Host "Network monitoring completed at $time"
exit 0
