# Common helpers for PC Monitor scripts.

Set-StrictMode -Version 3
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Get-PcMonitorConfigPath {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot
    )

    return Join-Path $BasePath "config.json"
}

function Get-PcMonitorConfig {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot
    )

    $configPath = Get-PcMonitorConfigPath -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Configuration file not found: $configPath"
    }

    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "Failed to read configuration: $($_.Exception.Message)"
    }

    if ($config.PSObject.Properties.Name -contains "botTokenProtected" -and -not [string]::IsNullOrWhiteSpace($config.botTokenProtected)) {
        try {
            $decrypted = Unprotect-PcMonitorSecret -ProtectedBase64 $config.botTokenProtected
            if (-not [string]::IsNullOrWhiteSpace($decrypted)) {
                if ($config.PSObject.Properties.Name -contains "botToken") {
                    $config.botToken = $decrypted
                } else {
                    $config | Add-Member -NotePropertyName "botToken" -NotePropertyValue $decrypted
                }
            }
        } catch {
            if ($config.PSObject.Properties.Name -contains "botToken" -and -not [string]::IsNullOrWhiteSpace($config.botToken)) {
                Write-Warning "Falling back to plaintext botToken because botTokenProtected could not be decrypted: $($_.Exception.Message)"
            } else {
                throw "Failed to decrypt botTokenProtected. Run setup_tasks.ps1 to re-encrypt: $($_.Exception.Message)"
            }
        }
    }

    foreach ($requiredProperty in @("botToken", "chatID")) {
        if (-not ($config.PSObject.Properties.Name -contains $requiredProperty) -or [string]::IsNullOrWhiteSpace($config.$requiredProperty)) {
            throw "Missing required configuration value: $requiredProperty"
        }
    }

    return $config
}

function Save-PcMonitorConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Config,
        [string]$BasePath = $PSScriptRoot
    )

    $configPath = Get-PcMonitorConfigPath -BasePath $BasePath

    $toSave = $Config | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    if (($toSave.PSObject.Properties.Name -contains "botTokenProtected") -and -not [string]::IsNullOrWhiteSpace($toSave.botTokenProtected)) {
        if ($toSave.PSObject.Properties.Name -contains "botToken") {
            $toSave.botToken = ""
        }
    }

    $toSave | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
    return $configPath
}

function Write-PcMonitorBanner {
    [CmdletBinding()]
    param()

    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "  RAVEN PC Monitor - Setup Wizard" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host ""

    $banner = @'
           @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%#*+++++**#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%+-------------------+%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*---------------------------#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#=-------------------------------+@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*-----------------------------@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@+---------------=+%@@@@@@@@@*---+%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*-------------------=@@@@@@@@#-------=@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@=---------------------=@@@@@%-----------#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#------------------------------------------%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#-------------------------------------------+@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%--------------------------------------------+@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@=---+%-------------------------=#@@@@@@@@@*=-%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@*-+@@@------------------------+@@@@@@@@@@@@@@%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%---------------*+------#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@%----------=#@@=-------=@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@=-------=@@@#---------%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@------%@@@*----------%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@=---@@@@%-----------=@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@+-#@@@@=------------*@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@=-------------=#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#=------------=%@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
'@

    Write-Host $banner -ForegroundColor DarkGray
    Write-Host "
                                                            _   _   _   _   _  

                                                          ( R | A | V | E | N )
                                                            _   _   _   _   _ 
" -ForegroundColor White
    Write-Host "@by emmanuelkhisa" -ForegroundColor DarkCyan
    Write-Host ""
}

function Test-PcMonitorTelegramConfiguration {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot
    )

    $config = Get-PcMonitorConfig -BasePath $BasePath
    $result = Invoke-RestMethod -Uri "https://api.telegram.org/bot$($config.botToken)/getMe" -Method Get -ErrorAction Stop
    if (-not $result.ok) {
        throw "Telegram bot validation failed."
    }

    return $result.result
}

function Get-PcMonitorDataPath {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot,
        [string]$ChildPath
    )

    $dataPath = Join-Path $BasePath "data"
    if (-not [string]::IsNullOrWhiteSpace($ChildPath)) {
        return Join-Path $dataPath $ChildPath
    }

    return $dataPath
}

function Initialize-PcMonitorDataPaths {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot
    )

    $paths = @(
        (Get-PcMonitorDataPath -BasePath $BasePath),
        (Get-PcMonitorDataPath -BasePath $BasePath -ChildPath "incoming"),
        (Get-PcMonitorDataPath -BasePath $BasePath -ChildPath "outgoing"),
        (Get-PcMonitorDataPath -BasePath $BasePath -ChildPath "logs")
    )

    foreach ($path in $paths) {
        if (-not (Test-Path -LiteralPath $path)) {
            [void](New-Item -ItemType Directory -Path $path -Force)
        }
    }

    return $paths
}

function Get-PcMonitorActionLogPath {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot
    )

    Initialize-PcMonitorDataPaths -BasePath $BasePath | Out-Null
    return Get-PcMonitorDataPath -BasePath $BasePath -ChildPath "logs\activity.log"
}

function Write-PcMonitorActivity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Category,
        [Parameter(Mandatory = $true)]
        [string]$Action,
        [string]$Detail = "",
        [string]$BasePath = $PSScriptRoot
    )

    $entry = [pscustomobject]@{
        Timestamp = (Get-Date).ToString("s")
        Computer  = $env:COMPUTERNAME
        User      = $env:USERNAME
        Category  = $Category
        Action    = $Action
        Detail    = $Detail
    } | ConvertTo-Json -Compress

    Add-Content -LiteralPath (Get-PcMonitorActionLogPath -BasePath $BasePath) -Value $entry -Encoding UTF8
}

function Get-PcMonitorRecentActivity {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot,
        [int]$Count = 10
    )

    $logPath = Get-PcMonitorActionLogPath -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $logPath)) {
        return @()
    }

    $entries = Get-Content -LiteralPath $logPath -Encoding UTF8 |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Last $Count |
        ForEach-Object {
            try {
                $_ | ConvertFrom-Json
            } catch {
            }
        }

    return @($entries | Where-Object { $null -ne $_ } | Sort-Object Timestamp -Descending)
}

function Get-PcMonitorKnownLocations {
    [CmdletBinding()]
    param()

    return [ordered]@{
        desktop   = [Environment]::GetFolderPath("Desktop")
        documents = [Environment]::GetFolderPath("MyDocuments")
        downloads = Join-Path $env:USERPROFILE "Downloads"
        pictures  = [Environment]::GetFolderPath("MyPictures")
        temp      = $env:TEMP
    }
}

function Get-PcMonitorFfmpegPath {
    [CmdletBinding()]
    param(
        [psobject]$Config
    )

    if ($Config -and ($Config.PSObject.Properties.Name -contains "ffmpegPath") -and -not [string]::IsNullOrWhiteSpace($Config.ffmpegPath) -and (Test-Path -LiteralPath $Config.ffmpegPath)) {
        return (Resolve-Path -LiteralPath $Config.ffmpegPath).Path
    }

    $command = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($command -and $command.Source) {
        return $command.Source
    }

    $wingetRoot = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path -LiteralPath $wingetRoot) {
        $wingetMatch = Get-ChildItem -LiteralPath $wingetRoot -Recurse -Filter ffmpeg.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if ($wingetMatch) {
            return $wingetMatch
        }
    }

    return $null
}

function Install-PcMonitorFfmpeg {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot
    )

    $config = Get-PcMonitorConfig -BasePath $BasePath
    $existingPath = Get-PcMonitorFfmpegPath -Config $config
    if ($existingPath) {
        if (($config.PSObject.Properties.Name -contains "ffmpegPath")) {
            $config.ffmpegPath = $existingPath
        } else {
            $config | Add-Member -NotePropertyName "ffmpegPath" -NotePropertyValue $existingPath
        }
        Save-PcMonitorConfig -Config $config -BasePath $BasePath | Out-Null
        return $existingPath
    }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "winget is required to install ffmpeg automatically."
    }

    & $winget.Source install --id Gyan.FFmpeg --exact --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Automatic ffmpeg installation failed with exit code $LASTEXITCODE."
    }

    $updatedConfig = Get-PcMonitorConfig -BasePath $BasePath
    $installedPath = Get-PcMonitorFfmpegPath -Config $updatedConfig
    if (-not $installedPath) {
        throw "ffmpeg was installed but no executable path was detected."
    }

    if (($updatedConfig.PSObject.Properties.Name -contains "ffmpegPath")) {
        $updatedConfig.ffmpegPath = $installedPath
    } else {
        $updatedConfig | Add-Member -NotePropertyName "ffmpegPath" -NotePropertyValue $installedPath
    }

    Save-PcMonitorConfig -Config $updatedConfig -BasePath $BasePath | Out-Null
    return $installedPath
}

function Get-PcMonitorDirectShowDevices {
    [CmdletBinding()]
    param(
        [psobject]$Config
    )

    $ffmpegPath = Get-PcMonitorFfmpegPath -Config $Config
    if (-not $ffmpegPath) {
        throw "ffmpeg is not installed on this PC."
    }

    $stderrPath = Join-Path $env:TEMP "ffmpeg_devices_$([guid]::NewGuid().ToString('N')).log"
    try {
        & $ffmpegPath -hide_banner -list_devices true -f dshow -i dummy 2>$stderrPath | Out-Null
        $deviceOutput = if (Test-Path -LiteralPath $stderrPath) {
            Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue
        } else {
            ""
        }

        $videoDevices = [System.Collections.Generic.List[string]]::new()
        $audioDevices = [System.Collections.Generic.List[string]]::new()
        $currentType = ""

        foreach ($line in ($deviceOutput -split "`r?`n")) {
            if ($line -match "DirectShow video devices") {
                $currentType = "video"
                continue
            }

            if ($line -match "DirectShow audio devices") {
                $currentType = "audio"
                continue
            }

            if ($line -match '"([^"]+)"') {
                $deviceName = $Matches[1]
                if ($currentType -eq "video") {
                    [void]$videoDevices.Add($deviceName)
                } elseif ($currentType -eq "audio") {
                    [void]$audioDevices.Add($deviceName)
                }
            }
        }

        return [pscustomobject]@{
            Video = @($videoDevices | Select-Object -Unique)
            Audio = @($audioDevices | Select-Object -Unique)
            Raw   = $deviceOutput
        }
    } finally {
        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Enable-PcMonitorAuditing {
    [CmdletBinding()]
    param()

    $commands = @(
        @("/set", '/subcategory:"Logon"', "/success:enable", "/failure:enable"),
        @("/set", '/subcategory:"Process Creation"', "/success:enable"),
        @("/set", '/subcategory:"Other Logon/Logoff Events"', "/success:enable", "/failure:enable"),
        @("/set", '/subcategory:"File System"', "/success:enable")
    )

    foreach ($commandArgs in $commands) {
        & auditpol @commandArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to configure auditing with: auditpol $($commandArgs -join ' ')"
        }
    }
}

function Stop-PcMonitorProcesses {
    [CmdletBinding()]
    param()

    $patterns = @(
        "bot_commands.ps1",
        "event_monitor.ps1",
        "performance_monitor.ps1",
        "network_monitor.ps1",
        "daily_report.ps1"
    )

    $processes = Get-CimInstance Win32_Process -Filter "name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $commandLine = [string]$_.CommandLine
            foreach ($pattern in $patterns) {
                if ($commandLine -match [regex]::Escape($pattern)) {
                    return $true
                }
            }
            return $false
        }

    foreach ($process in @($processes)) {
        try {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
        } catch {
        }
    }
}

function Resolve-PcMonitorPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [string]$BasePath = $PSScriptRoot
    )

    $trimmedPath = $InputPath.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedPath)) {
        throw "Path cannot be empty."
    }

    $knownLocations = Get-PcMonitorKnownLocations
    foreach ($alias in $knownLocations.Keys) {
        if ($trimmedPath -ieq $alias) {
            return [System.IO.Path]::GetFullPath($knownLocations[$alias])
        }

        if ($trimmedPath -match ("^(?i){0}[\\/](.+)$" -f [regex]::Escape($alias))) {
            return [System.IO.Path]::GetFullPath((Join-Path $knownLocations[$alias] $Matches[1]))
        }
    }

    if ([System.IO.Path]::IsPathRooted($trimmedPath)) {
        return [System.IO.Path]::GetFullPath($trimmedPath)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $trimmedPath))
}

function Get-PcMonitorInstallPath {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot,
        [switch]$Persist
    )

    $config = Get-PcMonitorConfig -BasePath $BasePath
    $installPath = $config.installPath

    if ([string]::IsNullOrWhiteSpace($installPath)) {
        $installPath = [System.IO.Path]::GetFullPath($BasePath)
        if ($Persist) {
            if ($config.PSObject.Properties.Name -contains "installPath") {
                $config.installPath = $installPath
            } else {
                $config | Add-Member -NotePropertyName "installPath" -NotePropertyValue $installPath
            }
            Save-PcMonitorConfig -Config $config -BasePath $BasePath | Out-Null
        }
    }

    return [System.IO.Path]::GetFullPath($installPath)
}

function Copy-PcMonitorInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $source = [System.IO.Path]::GetFullPath($SourcePath)
    $destination = [System.IO.Path]::GetFullPath($DestinationPath)
    if ($source.TrimEnd('\') -ieq $destination.TrimEnd('\')) {
        return [pscustomobject]@{
            Copied = $false
            ConfigCreated = $false
            CredentialsRequired = $false
        }
    }

    foreach ($requiredPath in @("setup_tasks.ps1", "pc_monitor_common.ps1", "config.example.json", "tasks")) {
        if (-not (Test-Path -LiteralPath (Join-Path $source $requiredPath))) {
            throw "Installation source is incomplete; missing $requiredPath in $source."
        }
    }

    [void](New-Item -ItemType Directory -Path $destination -Force)
    $excludedDirectories = @(".git", ".idea", "data")
    $excludedFiles = @("network_state.json", "bot_commands.log", "setup_install_test.log")

    foreach ($item in Get-ChildItem -LiteralPath $source -Force) {
        if ($item.PSIsContainer) {
            if ($item.Name -in $excludedDirectories) {
                continue
            }

            Copy-Item -LiteralPath $item.FullName -Destination $destination -Recurse -Force -ErrorAction Stop
            continue
        }

        if ($item.Name -in $excludedFiles -or $item.Extension -eq ".log") {
            continue
        }

        if ($item.Name -ieq "config.json") {
            continue
        }

        Copy-Item -LiteralPath $item.FullName -Destination $destination -Force -ErrorAction Stop
    }

    $destinationConfigPath = Join-Path $destination "config.json"
    $configCreated = $false
    $credentialsRequired = $false
    if (-not (Test-Path -LiteralPath $destinationConfigPath)) {
        $sourceConfigPath = Join-Path $source "config.json"
        $canUseSourceConfig = $false
        $sourceConfig = $null

        if (Test-Path -LiteralPath $sourceConfigPath) {
            try {
                $sourceConfig = Get-Content -LiteralPath $sourceConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
                $hasProtectedToken = ($sourceConfig.PSObject.Properties.Name -contains "botTokenProtected") -and
                    -not [string]::IsNullOrWhiteSpace([string]$sourceConfig.botTokenProtected)
                $hasPlainToken = ($sourceConfig.PSObject.Properties.Name -contains "botToken") -and
                    -not [string]::IsNullOrWhiteSpace([string]$sourceConfig.botToken)

                if ($hasProtectedToken -and -not $hasPlainToken) {
                    try {
                        [void](Unprotect-PcMonitorSecret -ProtectedBase64 $sourceConfig.botTokenProtected)
                        $canUseSourceConfig = $true
                    } catch {
                        Write-Warning "The source bot token is protected for a different Windows installation; it cannot be transferred. A fresh config will be created."
                    }
                } elseif ($hasPlainToken) {
                    $canUseSourceConfig = $true
                }
            } catch {
                Write-Warning "The source config.json could not be read; a fresh config will be created. $($_.Exception.Message)"
            }
        }

        if ($canUseSourceConfig) {
            Copy-Item -LiteralPath $sourceConfigPath -Destination $destinationConfigPath -Force -ErrorAction Stop
        } else {
            if ($null -ne $sourceConfig) {
                $freshConfig = $sourceConfig | ConvertTo-Json -Depth 10 | ConvertFrom-Json -ErrorAction Stop
            } else {
                $examplePath = Join-Path $source "config.example.json"
                $freshConfig = Get-Content -LiteralPath $examplePath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            }
            $freshConfig.botToken = ""
            $freshConfig.chatID = ""
            if ($freshConfig.PSObject.Properties.Name -contains "botTokenProtected") {
                $freshConfig.botTokenProtected = ""
            }
            if ($freshConfig.PSObject.Properties.Name -contains "installPath") {
                $freshConfig.installPath = $destination
            } else {
                $freshConfig | Add-Member -NotePropertyName "installPath" -NotePropertyValue $destination
            }
            $freshConfig | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $destinationConfigPath -Encoding UTF8
            $credentialsRequired = $true
        }

        $configCreated = $true
    }

    return [pscustomobject]@{
        Copied = $true
        ConfigCreated = $configCreated
        CredentialsRequired = $credentialsRequired
    }
}

function Set-PcMonitorRuntimeDataPermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $dataPath = Join-Path $BasePath "data"
    if (-not (Test-Path -LiteralPath $dataPath)) {
        [void](New-Item -ItemType Directory -Path $dataPath -Force)
    }

    $acl = Get-Acl -LiteralPath $dataPath -ErrorAction Stop
    $inheritance = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $administratorsSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")

    $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $userSid,
        [System.Security.AccessControl.FileSystemRights]::Modify,
        $inheritance,
        $propagation,
        $allow
    )
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $systemSid,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritance,
        $propagation,
        $allow
    )
    $administratorsRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $administratorsSid,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $inheritance,
        $propagation,
        $allow
    )

    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetAccessRule($userRule)
    $acl.SetAccessRule($systemRule)
    $acl.SetAccessRule($administratorsRule)
    Set-Acl -LiteralPath $dataPath -AclObject $acl -ErrorAction Stop
}

function Set-PcMonitorConfigFilePermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $configPath = Get-PcMonitorConfigPath -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        return
    }

    $acl = Get-Acl -LiteralPath $configPath -ErrorAction Stop
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
    $administratorsSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $userSid,
        [System.Security.AccessControl.FileSystemRights]::Modify,
        $allow
    )
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $systemSid,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $allow
    )
    $administratorsRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $administratorsSid,
        [System.Security.AccessControl.FileSystemRights]::FullControl,
        $allow
    )

    $acl.SetAccessRuleProtection($true, $false)
    $acl.SetAccessRule($userRule)
    $acl.SetAccessRule($systemRule)
    $acl.SetAccessRule($administratorsRule)
    Set-Acl -LiteralPath $configPath -AclObject $acl -ErrorAction Stop
}

function Send-PcMonitorTelegramMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [Parameter(Mandatory = $true)]
        [psobject]$Config
    )

    $url = "https://api.telegram.org/bot$($Config.botToken)/sendMessage"
    $body = @{
        chat_id = "$($Config.chatID)"
        text    = $Message
    } | ConvertTo-Json

    Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json; charset=utf-8" -ErrorAction Stop | Out-Null
}

function Send-PcMonitorTelegramPhoto {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PhotoPath,
        [Parameter(Mandatory = $true)]
        [psobject]$Config,
        [string]$Caption = ""
    )

    if (-not (Test-Path -LiteralPath $PhotoPath)) {
        throw "Photo file not found: $PhotoPath"
    }

    Add-Type -AssemblyName System.Net.Http

    $handler = New-Object System.Net.Http.HttpClientHandler
    $client = New-Object System.Net.Http.HttpClient($handler)

    try {
        $content = New-Object System.Net.Http.MultipartFormDataContent
        $content.Add((New-Object System.Net.Http.StringContent("$($Config.chatID)")), "chat_id")
        if (-not [string]::IsNullOrWhiteSpace($Caption)) {
            $content.Add((New-Object System.Net.Http.StringContent($Caption)), "caption")
        }

        $resolvedPhotoPath = (Resolve-Path -LiteralPath $PhotoPath).Path
        $bytes = [System.IO.File]::ReadAllBytes($resolvedPhotoPath)
        $fileContent = [System.Net.Http.ByteArrayContent]::new($bytes)
        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
        $content.Add($fileContent, "photo", [System.IO.Path]::GetFileName($PhotoPath))

        $response = $client.PostAsync("https://api.telegram.org/bot$($Config.botToken)/sendPhoto", $content).GetAwaiter().GetResult()
        [void]$response.EnsureSuccessStatusCode()
    } finally {
        if ($response) {
            $response.Dispose()
        }
        if ($content) {
            $content.Dispose()
        }
        if ($client) {
            $client.Dispose()
        }
        if ($handler) {
            $handler.Dispose()
        }
    }
}

function Send-PcMonitorTelegramDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Mandatory = $true)]
        [psobject]$Config,
        [string]$Caption = ""
    )

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "Document file not found: $FilePath"
    }

    Add-Type -AssemblyName System.Net.Http

    $handler = New-Object System.Net.Http.HttpClientHandler
    $client = New-Object System.Net.Http.HttpClient($handler)
    $resolvedFilePath = (Resolve-Path -LiteralPath $FilePath).Path
    $response = $null
    $content = $null

    try {
        $content = New-Object System.Net.Http.MultipartFormDataContent
        $content.Add((New-Object System.Net.Http.StringContent("$($Config.chatID)")), "chat_id")
        if (-not [string]::IsNullOrWhiteSpace($Caption)) {
            $content.Add((New-Object System.Net.Http.StringContent($Caption)), "caption")
        }

        $bytes = [System.IO.File]::ReadAllBytes($resolvedFilePath)
        $fileContent = [System.Net.Http.ByteArrayContent]::new($bytes)
        $content.Add($fileContent, "document", [System.IO.Path]::GetFileName($resolvedFilePath))

        $response = $client.PostAsync("https://api.telegram.org/bot$($Config.botToken)/sendDocument", $content).GetAwaiter().GetResult()
        [void]$response.EnsureSuccessStatusCode()
    } finally {
        if ($response) {
            $response.Dispose()
        }
        if ($content) {
            $content.Dispose()
        }
        if ($client) {
            $client.Dispose()
        }
        if ($handler) {
            $handler.Dispose()
        }
    }
}

function Get-PcMonitorTelegramFileDownloadUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileId,
        [Parameter(Mandatory = $true)]
        [psobject]$Config
    )

    $result = Invoke-RestMethod -Uri "https://api.telegram.org/bot$($Config.botToken)/getFile?file_id=$FileId" -Method Get -ErrorAction Stop
    if (-not $result.ok -or -not $result.result.file_path) {
        throw "Unable to resolve Telegram file path."
    }

    return "https://api.telegram.org/file/bot$($Config.botToken)/$($result.result.file_path)"
}

function Save-PcMonitorTelegramDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Document,
        [Parameter(Mandatory = $true)]
        [psobject]$Config,
        [string]$DestinationDirectory,
        [string]$BasePath = $PSScriptRoot
    )

    Initialize-PcMonitorDataPaths -BasePath $BasePath | Out-Null

    if ([string]::IsNullOrWhiteSpace($DestinationDirectory)) {
        $DestinationDirectory = Get-PcMonitorDataPath -BasePath $BasePath -ChildPath "incoming"
    }

    if (-not (Test-Path -LiteralPath $DestinationDirectory)) {
        [void](New-Item -ItemType Directory -Path $DestinationDirectory -Force)
    }

    $safeName = if ($Document.file_name) { [System.IO.Path]::GetFileName([string]$Document.file_name) } else { "$($Document.file_id).bin" }
    $targetPath = Join-Path $DestinationDirectory $safeName
    $downloadUrl = Get-PcMonitorTelegramFileDownloadUrl -FileId $Document.file_id -Config $Config

    Invoke-WebRequest -Uri $downloadUrl -OutFile $targetPath -ErrorAction Stop
    return $targetPath
}

function Test-PcMonitorAdministrator {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PcMonitorTaskDefinitions {
    [CmdletBinding()]
    param()

    return @(
        @{
            Name = "EventMonitorTask.xml"
            TaskName = "PC Monitor\Event Monitor"
            Script = "event_monitor.ps1"
            Arguments = ""
        },
        @{
            Name = "PerformanceMonitorTask.xml"
            TaskName = "PC Monitor\Performance Monitor"
            Script = "performance_monitor.ps1"
            Arguments = ""
        },
        @{
            Name = "NetworkMonitorTask.xml"
            TaskName = "PC Monitor\Network Monitor"
            Script = "network_monitor.ps1"
            Arguments = ""
        },
        @{
            Name = "DailyReportTask.xml"
            TaskName = "PC Monitor\Daily Report"
            Script = "daily_report.ps1"
            Arguments = "-ReportType daily"
        },
        @{
            Name = "WeeklyReportTask.xml"
            TaskName = "PC Monitor\Weekly Report"
            Script = "daily_report.ps1"
            Arguments = "-ReportType weekly"
        },
        @{
            Name = "BotCommandsTask.xml"
            TaskName = "PC Monitor\Bot Commands"
            Script = "bot_commands.ps1"
            Arguments = "-WindowStyle Hidden"
            RunAsCurrentUser = $true
        }
    )
}

function Test-PcMonitorRequiredScripts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath
    )

    $missingScripts = @()
    foreach ($task in Get-PcMonitorTaskDefinitions) {
        $scriptPath = Join-Path $InstallPath $task.Script
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            $missingScripts += $task.Script
        }
    }

    $inventoryScript = Join-Path $InstallPath "pc_monitor_network_inventory.ps1"
    if (-not (Test-Path -LiteralPath $inventoryScript)) {
        $missingScripts += "pc_monitor_network_inventory.ps1"
    }

    return $missingScripts | Sort-Object -Unique
}

function Get-PcMonitorTaskCommandArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [Parameter(Mandatory = $true)]
        [hashtable]$Task
    )

    $scriptPath = Join-Path $InstallPath $Task.Script
    $parts = @()

    if (-not [string]::IsNullOrWhiteSpace($Task.Arguments)) {
        $parts += $Task.Arguments.Trim()
    }

    $parts += "-ExecutionPolicy Bypass"
    $parts += "-File `"$scriptPath`""

    return ($parts -join " ").Trim()
}

function Test-PcMonitorTaskRunsAsCurrentUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Task
    )

    return ($Task.ContainsKey("RunAsCurrentUser") -and [bool]$Task.RunAsCurrentUser)
}

function Sync-PcMonitorTaskXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,
        [Parameter(Mandatory = $true)]
        [string]$InstallPath
    )

    $tasksDir = Join-Path $BasePath "tasks"
    if (-not (Test-Path -LiteralPath $tasksDir)) {
        throw "Tasks directory not found: $tasksDir"
    }

    $updated = @()
    $namespaceUri = "http://schemas.microsoft.com/windows/2004/02/mit/task"

    foreach ($task in Get-PcMonitorTaskDefinitions) {
        $xmlPath = Join-Path $tasksDir $task.Name
        if (-not (Test-Path -LiteralPath $xmlPath)) {
            throw "Task XML file not found: $xmlPath"
        }

        $xmlDocument = Open-PcMonitorTaskXml -Path $xmlPath

        $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xmlDocument.NameTable)
        $namespaceManager.AddNamespace("task", $namespaceUri)

        $commandNode = $xmlDocument.SelectSingleNode("/task:Task/task:Actions/task:Exec/task:Command", $namespaceManager)
        $argumentsNode = $xmlDocument.SelectSingleNode("/task:Task/task:Actions/task:Exec/task:Arguments", $namespaceManager)
        $principalNode = $xmlDocument.SelectSingleNode("/task:Task/task:Principals/task:Principal", $namespaceManager)

        if (-not $commandNode -or -not $argumentsNode -or -not $principalNode) {
            throw "Task XML is missing required nodes: $xmlPath"
        }

        $commandNode.InnerText = "powershell.exe"
        $argumentsNode.InnerText = Get-PcMonitorTaskCommandArguments -InstallPath $InstallPath -Task $task

        if (Test-PcMonitorTaskRunsAsCurrentUser -Task $task) {
            $userIdNode = $xmlDocument.SelectSingleNode("/task:Task/task:Principals/task:Principal/task:UserId", $namespaceManager)
            if (-not $userIdNode) {
                $userIdNode = $xmlDocument.CreateElement("UserId", $namespaceUri)
                [void]$principalNode.AppendChild($userIdNode)
            }

            $logonTypeNode = $xmlDocument.SelectSingleNode("/task:Task/task:Principals/task:Principal/task:LogonType", $namespaceManager)
            $userIdNode.InnerText = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $logonTypeNode.InnerText = "InteractiveToken"
        }

        $writerSettings = New-Object System.Xml.XmlWriterSettings
        $writerSettings.Encoding = [System.Text.UnicodeEncoding]::new($false, $true)
        $writerSettings.Indent = $true
        $writerSettings.NewLineChars = "`r`n"
        $writerSettings.NewLineHandling = [System.Xml.NewLineHandling]::Replace

        $writer = [System.Xml.XmlWriter]::Create($xmlPath, $writerSettings)
        try {
            $xmlDocument.Save($writer)
        } finally {
            $writer.Dispose()
        }

        $updated += $task.Name
    }

    return $updated
}

function Open-PcMonitorTaskXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $xmlDocument = New-Object System.Xml.XmlDocument
    $xmlDocument.PreserveWhitespace = $true

    try {
        $xmlDocument.Load($Path)
        return $xmlDocument
    } catch {
        $encodings = @(
            [System.Text.Encoding]::Unicode,
            [System.Text.Encoding]::UTF8,
            [System.Text.Encoding]::Default
        )

        foreach ($encoding in $encodings) {
            try {
                $content = [System.IO.File]::ReadAllText($Path, $encoding)
                $xmlDocument = New-Object System.Xml.XmlDocument
                $xmlDocument.PreserveWhitespace = $true
                $xmlDocument.LoadXml($content)
                return $xmlDocument
            } catch {
            }
        }

        throw "Failed to open task XML: $Path"
    }
}

function Protect-PcMonitorSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Plaintext
    )

    Add-Type -AssemblyName System.Security
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Plaintext)
    $protected = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    return [System.Convert]::ToBase64String($protected)
}

function Unprotect-PcMonitorSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProtectedBase64
    )

    Add-Type -AssemblyName System.Security
    $protected = [System.Convert]::FromBase64String($ProtectedBase64)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $protected, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

function Test-PcMonitorAuthorizedChat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChatId,
        [Parameter(Mandatory = $true)]
        [psobject]$Config
    )

    if ("$($Config.chatID)" -eq $ChatId) {
        return $true
    }

    if ($Config.PSObject.Properties.Name -contains "allowedChatIDs") {
        foreach ($id in @($Config.allowedChatIDs)) {
            if ("$id" -eq $ChatId) {
                return $true
            }
        }
    }

    return $false
}

function Get-PcMonitorAlertStatePath {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot
    )

    Initialize-PcMonitorDataPaths -BasePath $BasePath | Out-Null
    return Get-PcMonitorDataPath -BasePath $BasePath -ChildPath "alert_state.json"
}

function Test-PcMonitorAlertCooldown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AlertKey,
        [int]$CooldownMinutes = 30,
        [string]$BasePath = $PSScriptRoot
    )

    $statePath = Get-PcMonitorAlertStatePath -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $statePath)) {
        return $false
    }

    try {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not ($state.PSObject.Properties.Name -contains $AlertKey)) {
            return $false
        }
        $lastAlert = [datetime]$state.$AlertKey
        return ((Get-Date) - $lastAlert).TotalMinutes -lt $CooldownMinutes
    } catch {
        return $false
    }
}

function Update-PcMonitorAlertCooldown {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AlertKey,
        [string]$BasePath = $PSScriptRoot
    )

    $statePath = Get-PcMonitorAlertStatePath -BasePath $BasePath
    $state = if (Test-Path -LiteralPath $statePath) {
        try {
            Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            [pscustomobject]@{}
        }
    } else {
        [pscustomobject]@{}
    }

    if ($state.PSObject.Properties.Name -contains $AlertKey) {
        $state.$AlertKey = (Get-Date).ToString("o")
    } else {
        $state | Add-Member -NotePropertyName $AlertKey -NotePropertyValue (Get-Date).ToString("o")
    }

    $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Get-PcMonitorTemperatureCelsius {
    [CmdletBinding()]
    param()

    try {
        $zones = Get-CimInstance -Namespace "root\wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction Stop
        $temps = @($zones | ForEach-Object {
            $c = [math]::Round(($_.CurrentTemperature - 2732) / 10, 1)
            if ($c -gt 0 -and $c -lt 150) { $c }
        } | Where-Object { $null -ne $_ })
        if ($temps.Count -gt 0) {
            return $temps
        }
        return $null
    } catch {
        return $null
    }
}

function Get-PcMonitorActivityInRange {
    [CmdletBinding()]
    param(
        [string]$BasePath = $PSScriptRoot,
        [Parameter(Mandatory = $true)]
        [datetime]$StartTime,
        [Parameter(Mandatory = $true)]
        [datetime]$EndTime
    )

    $logPath = Get-PcMonitorActionLogPath -BasePath $BasePath
    if (-not (Test-Path -LiteralPath $logPath)) {
        return @()
    }

    return @(Get-Content -LiteralPath $logPath -Encoding UTF8 |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object {
            try { $_ | ConvertFrom-Json } catch {}
        } |
        Where-Object {
            $null -ne $_ -and
            [datetime]$_.Timestamp -ge $StartTime -and
            [datetime]$_.Timestamp -le $EndTime
        })
}

function Install-PcMonitorTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $tasksDir = Join-Path $BasePath "tasks"
    $results = @()

    foreach ($task in Get-PcMonitorTaskDefinitions) {
        $xmlPath = Join-Path $tasksDir $task.Name
        if (-not (Test-Path -LiteralPath $xmlPath)) {
            throw "Task XML file not found: $xmlPath"
        }

        & schtasks /query /tn $task.TaskName 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            & schtasks /end /tn $task.TaskName 2>$null | Out-Null
            & schtasks /delete /tn $task.TaskName /f | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to remove existing task: $($task.TaskName)"
            }
        }

        if (Test-PcMonitorTaskRunsAsCurrentUser -Task $task) {
            $output = & schtasks /create /tn $task.TaskName /xml $xmlPath 2>&1
        } else {
            $output = & schtasks /create /tn $task.TaskName /xml $xmlPath /ru SYSTEM 2>&1
        }
        if ($LASTEXITCODE -ne 0) {
            $detail = ($output | Out-String).Trim()
            if ([string]::IsNullOrWhiteSpace($detail)) {
                $detail = "Unknown schtasks error"
            }
            throw "Failed to install $($task.TaskName): $detail"
        }

        if (Test-PcMonitorTaskRunsAsCurrentUser -Task $task) {
            & schtasks /run /tn $task.TaskName 2>$null | Out-Null
        }

        $results += $task.TaskName
    }

    return $results
}
