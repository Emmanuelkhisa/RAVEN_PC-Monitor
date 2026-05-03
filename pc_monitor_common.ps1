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
    $Config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $configPath -Encoding UTF8
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
