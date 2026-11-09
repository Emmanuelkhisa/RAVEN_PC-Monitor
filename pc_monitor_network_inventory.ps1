function Test-PcMonitorNeighborReachability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$IPAddress,
        [ValidateRange(100, 5000)]
        [int]$TimeoutMilliseconds = 800,
        [ValidateRange(1, 64)]
        [int]$MaxConcurrent = 32
    )

    $results = @{}
    $pending = New-Object System.Collections.ArrayList
    $uniqueAddresses = @($IPAddress | Where-Object { $_ } | Select-Object -Unique)

    foreach ($addressText in $uniqueAddresses) {
        $address = $null
        $ping = $null
        if (-not [System.Net.IPAddress]::TryParse($addressText, [ref]$address)) {
            $results[$addressText] = [pscustomobject]@{
                Status = "Invalid address"
                RoundtripTime = $null
            }
            continue
        }

        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $task = $ping.SendPingAsync($address, $TimeoutMilliseconds)
            [void]$pending.Add([pscustomobject]@{
                IPAddress = $addressText
                Ping = $ping
                Task = $task
            })
        } catch {
            if ($ping) {
                $ping.Dispose()
            }
            $results[$addressText] = [pscustomobject]@{
                Status = "Ping error"
                RoundtripTime = $null
            }
        }

        if ($pending.Count -ge $MaxConcurrent) {
            Complete-PcMonitorNeighborPingBatch -Batch @($pending) -Results $results -WaitMilliseconds ($TimeoutMilliseconds + 1000)
            $pending.Clear()
        }
    }

    if ($pending.Count -gt 0) {
        Complete-PcMonitorNeighborPingBatch -Batch @($pending) -Results $results -WaitMilliseconds ($TimeoutMilliseconds + 1000)
    }

    return $results
}

function Complete-PcMonitorNeighborPingBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Batch,
        [Parameter(Mandatory = $true)]
        [hashtable]$Results,
        [Parameter(Mandatory = $true)]
        [int]$WaitMilliseconds
    )

    $tasks = [System.Threading.Tasks.Task[]]@($Batch | ForEach-Object { $_.Task })
    [void][System.Threading.Tasks.Task]::WaitAll($tasks, $WaitMilliseconds)

    foreach ($entry in $Batch) {
        try {
            if (-not $entry.Task.IsCompleted) {
                $Results[$entry.IPAddress] = [pscustomobject]@{
                    Status = "Timed out"
                    RoundtripTime = $null
                }
                continue
            }

            if ($entry.Task.IsFaulted -or $entry.Task.IsCanceled) {
                $Results[$entry.IPAddress] = [pscustomobject]@{
                    Status = "Ping error"
                    RoundtripTime = $null
                }
                continue
            }

            $reply = $entry.Task.GetAwaiter().GetResult()
            $status = if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                "Reachable"
            } elseif ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::TimedOut) {
                "No ICMP reply"
            } else {
                "Unresponsive ($($reply.Status))"
            }
            $roundtripTime = if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                [long]$reply.RoundtripTime
            } else {
                $null
            }

            $Results[$entry.IPAddress] = [pscustomobject]@{
                Status = $status
                RoundtripTime = $roundtripTime
            }
        } catch {
            $Results[$entry.IPAddress] = [pscustomobject]@{
                Status = "Ping error"
                RoundtripTime = $null
            }
        } finally {
            $entry.Ping.Dispose()
        }
    }
}

function New-PcMonitorNetworkInventoryReport {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot,
        [switch]$PingNeighbors,
        [ValidateRange(100, 5000)]
        [int]$PingTimeoutMilliseconds = 800
    )

    Initialize-PcMonitorDataPaths -BasePath $BasePath | Out-Null

    $inventoryTime = Get-Date
    $inventoryTimeUtc = $inventoryTime.ToUniversalTime().ToString("o")
    $interfaces = @(Get-NetIPConfiguration -All -ErrorAction Stop)
    $adapters = @(Get-NetAdapter -ErrorAction Stop)
    $interfaceByIndex = @{}

    foreach ($interface in $interfaces) {
        $interfaceByIndex[[int]$interface.InterfaceIndex] = $interface
    }

    $interfaceRows = @(
        foreach ($interface in $interfaces) {
            $adapter = $adapters | Where-Object { $_.ifIndex -eq $interface.InterfaceIndex } | Select-Object -First 1
            $addressObjects = @($interface.IPv4Address) + @($interface.IPv6Address)
            $addresses = @(
                $addressObjects |
                    Where-Object { $null -ne $_ -and $_.IPAddress } |
                    ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }
            )
            $gateways = @(
                @($interface.IPv4DefaultGateway) + @($interface.IPv6DefaultGateway) |
                    Where-Object { $null -ne $_ -and $_.NextHop } |
                    ForEach-Object { [string]$_.NextHop }
            )
            $dnsServers = @($interface.DnsServer.ServerAddresses | Where-Object { $_ })

            [pscustomobject]@{
                InterfaceIndex = [int]$interface.InterfaceIndex
                Alias          = [string]$interface.InterfaceAlias
                Description    = if ($adapter) { [string]$adapter.InterfaceDescription } else { "" }
                Status         = if ($adapter) { [string]$adapter.Status } else { "Unknown" }
                MacAddress     = if ($adapter) { [string]$adapter.MacAddress } else { "" }
                Addresses      = $addresses
                Gateways       = $gateways
                DnsServers     = $dnsServers
            }
        }
    )

    $routes = @(
        Get-NetRoute -PolicyStore ActiveStore -ErrorAction Stop |
            Sort-Object InterfaceIndex, DestinationPrefix, RouteMetric
    )
    $routeRows = @(
        foreach ($route in $routes) {
            $interfaceIndex = [int]$route.InterfaceIndex
            $interfaceAlias = if ($interfaceByIndex.ContainsKey($interfaceIndex)) {
                [string]$interfaceByIndex[$interfaceIndex].InterfaceAlias
            } else {
                "Interface $interfaceIndex"
            }

            [pscustomobject]@{
                Destination = [string]$route.DestinationPrefix
                NextHop     = [string]$route.NextHop
                Interface   = $interfaceAlias
                Metric      = [string]$route.RouteMetric
                Protocol    = [string]$route.Protocol
                State       = [string]$route.State
            }
        }
    )

    $localAddresses = @(
        foreach ($interface in $interfaces) {
            @($interface.IPv4Address) + @($interface.IPv6Address) |
                Where-Object { $null -ne $_ -and $_.IPAddress } |
                ForEach-Object { [string]$_.IPAddress }
        }
    )
    $neighbors = @(Get-NetNeighbor -ErrorAction Stop)
    $currentDevices = @(
        foreach ($neighbor in $neighbors) {
            $ipAddress = [string]$neighbor.IPAddress
            if ([string]::IsNullOrWhiteSpace($ipAddress) -or $ipAddress -in $localAddresses) {
                continue
            }

            $interfaceIndex = [int]$neighbor.InterfaceIndex
            $interfaceAlias = if ($interfaceByIndex.ContainsKey($interfaceIndex)) {
                [string]$interfaceByIndex[$interfaceIndex].InterfaceAlias
            } else {
                "Interface $interfaceIndex"
            }
            $macAddress = ([string]$neighbor.LinkLayerAddress).Trim().ToUpperInvariant()
            $key = "$interfaceIndex|$ipAddress"

            [pscustomobject]@{
                Key             = $key
                IPAddress       = $ipAddress
                MacAddress      = $macAddress
                InterfaceIndex  = $interfaceIndex
                InterfaceAlias  = $interfaceAlias
                CacheState      = [string]$neighbor.State
            }
        }
    )

    $pingResults = @{}
    if ($PingNeighbors -and $currentDevices.Count -gt 0) {
        $pingResults = Test-PcMonitorNeighborReachability `
            -IPAddress @($currentDevices | ForEach-Object { $_.IPAddress }) `
            -TimeoutMilliseconds $PingTimeoutMilliseconds
    }

    $statePath = Get-PcMonitorDataPath -BasePath $BasePath -ChildPath "network_inventory_state.json"
    $knownByKey = @{}
    if (Test-Path -LiteralPath $statePath) {
        try {
            $previousState = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Failed to read network inventory history: $($_.Exception.Message)"
        }

        if ($previousState.Version -ne 1) {
            throw "Unsupported network inventory history version in $statePath."
        }

        foreach ($device in @($previousState.Devices)) {
            if ($null -ne $device -and -not [string]::IsNullOrWhiteSpace([string]$device.Key)) {
                $knownByKey[[string]$device.Key] = $device
            }
        }
    }

    $currentKeys = @{}
    foreach ($device in $currentDevices) {
        $currentKeys[$device.Key] = $true
        $firstSeenUtc = $inventoryTimeUtc
        $previousDevice = $null
        if ($knownByKey.ContainsKey($device.Key)) {
            $previousDevice = $knownByKey[$device.Key]
            if ($previousDevice.FirstSeenUtc) {
                $firstSeenUtc = [string]$previousDevice.FirstSeenUtc
            }
        }

        if ($PingNeighbors) {
            $pingResult = $pingResults[$device.IPAddress]
            $pingStatus = if ($pingResult) { [string]$pingResult.Status } else { "Ping not completed" }
            $pingLatency = if ($pingResult) { $pingResult.RoundtripTime } else { $null }
            $pingCheckedUtc = $inventoryTimeUtc
        } elseif ($previousDevice) {
            $pingStatus = [string]$previousDevice.PingStatus
            $pingLatency = $previousDevice.PingLatencyMs
            $pingCheckedUtc = [string]$previousDevice.PingCheckedUtc
        } else {
            $pingStatus = "Not checked"
            $pingLatency = $null
            $pingCheckedUtc = ""
        }

        $knownByKey[$device.Key] = [pscustomobject]@{
            Key                    = $device.Key
            IPAddress              = $device.IPAddress
            MacAddress             = $device.MacAddress
            InterfaceIndex         = $device.InterfaceIndex
            InterfaceAlias         = $device.InterfaceAlias
            CacheState             = $device.CacheState
            FirstSeenUtc            = $firstSeenUtc
            LastSeenUtc             = $inventoryTimeUtc
            PresentInLatestCache    = $true
            PingStatus              = $pingStatus
            PingLatencyMs           = $pingLatency
            PingCheckedUtc          = $pingCheckedUtc
        }
    }

    foreach ($key in @($knownByKey.Keys)) {
        if (-not $currentKeys.ContainsKey($key)) {
            $device = $knownByKey[$key]
            $knownByKey[$key] = [pscustomobject]@{
                Key                 = [string]$device.Key
                IPAddress           = [string]$device.IPAddress
                MacAddress          = [string]$device.MacAddress
                InterfaceIndex      = [int]$device.InterfaceIndex
                InterfaceAlias      = [string]$device.InterfaceAlias
                CacheState          = "Not present in latest cache"
                FirstSeenUtc         = [string]$device.FirstSeenUtc
                LastSeenUtc          = [string]$device.LastSeenUtc
                PresentInLatestCache = $false
                PingStatus           = [string]$device.PingStatus
                PingLatencyMs        = $device.PingLatencyMs
                PingCheckedUtc       = [string]$device.PingCheckedUtc
            }
        }
    }

    $knownDevices = @($knownByKey.Values | Sort-Object `
        @{ Expression = { if ($_.PresentInLatestCache) { 0 } else { 1 } } }, IPAddress)
    $state = [pscustomobject]@{
        Version         = 1
        LastInventoryUtc = $inventoryTimeUtc
        Devices         = $knownDevices
    }
    try {
        $state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding UTF8
    } catch {
        throw "Failed to save network inventory history: $($_.Exception.Message)"
    }

    $reportLines = [System.Collections.Generic.List[string]]::new()
    $reportLines.Add("REMOTE PC MONITOR - NETWORK INVENTORY")
    $reportLines.Add("Computer: $env:COMPUTERNAME")
    $reportLines.Add("Generated: $($inventoryTime.ToString('yyyy-MM-dd HH:mm:ss zzz'))")
    $reportLines.Add("")
    $reportLines.Add("Collection method: local Windows interface, active route, and neighbor-cache tables.")
    $reportLines.Add("Neighbor addresses are pinged only when this report is explicitly requested; no subnet sweep or port checks are performed.")
    $reportLines.Add("An ICMP reply means reachable. No reply does not prove offline; host or network firewalls may block ping.")
    $reportLines.Add("")
    $reportLines.Add("=== INTERFACES, ADDRESSES, GATEWAYS, AND DNS ===")

    foreach ($interface in $interfaceRows) {
        $reportLines.Add("")
        $reportLines.Add("[$($interface.Alias)] (index $($interface.InterfaceIndex), $($interface.Status))")
        if ($interface.Description) {
            $reportLines.Add("  Adapter: $($interface.Description)")
        }
        if ($interface.MacAddress) {
            $reportLines.Add("  MAC: $($interface.MacAddress)")
        }
        $reportLines.Add("  IP addresses: $(if ($interface.Addresses.Count) { $interface.Addresses -join ', ' } else { 'none' })")
        $reportLines.Add("  Gateways: $(if ($interface.Gateways.Count) { $interface.Gateways -join ', ' } else { 'none' })")
        $reportLines.Add("  DNS servers: $(if ($interface.DnsServers.Count) { $interface.DnsServers -join ', ' } else { 'none' })")
    }

    $reportLines.Add("")
    $reportLines.Add("=== ACTIVE ROUTING TABLE ($($routeRows.Count) entries) ===")
    $reportLines.Add("Destination | Next hop | Interface | Metric | Protocol | State")
    foreach ($route in $routeRows) {
        $reportLines.Add("$($route.Destination) | $($route.NextHop) | $($route.Interface) | $($route.Metric) | $($route.Protocol) | $($route.State)")
    }

    $currentCount = @($knownDevices | Where-Object { $_.PresentInLatestCache }).Count
    $reportLines.Add("")
    $reportLines.Add("=== NEIGHBORS IN WINDOWS CACHE ($currentCount current; $($knownDevices.Count) tracked) ===")
    $reportLines.Add("IP address | MAC address | Interface | Cache state | Ping result | RTT ms | Ping checked (UTC) | First in cache (UTC) | Last in cache (UTC)")
    foreach ($device in $knownDevices) {
        $firstSeen = ([datetime]$device.FirstSeenUtc).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
        $lastSeen = ([datetime]$device.LastSeenUtc).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
        $macAddress = if ($device.MacAddress) { $device.MacAddress } else { "unresolved" }
        $pingStatus = if ($device.PingStatus) { [string]$device.PingStatus } else { "Not checked" }
        $pingLatency = if ($null -ne $device.PingLatencyMs) { [string]$device.PingLatencyMs } else { "-" }
        $pingChecked = if ($device.PingCheckedUtc) {
            ([datetime]$device.PingCheckedUtc).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
        } else {
            "-"
        }
        $reportLines.Add("$($device.IPAddress) | $macAddress | $($device.InterfaceAlias) | $($device.CacheState) | $pingStatus | $pingLatency | $pingChecked | $firstSeen | $lastSeen")
    }
    if ($knownDevices.Count -eq 0) {
        $reportLines.Add("No neighbor entries were present in the Windows cache.")
    }

    return [pscustomobject]@{
        Content          = $reportLines -join "`r`n"
        CurrentDeviceCount = $currentCount
        TrackedDeviceCount = $knownDevices.Count
        RouteCount        = $routeRows.Count
        InterfaceCount    = $interfaceRows.Count
        GeneratedAt       = $inventoryTime
    }
}
