# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Remote PC Monitor** (codename "Raven") is a Windows PowerShell system monitoring and remote control tool that communicates exclusively through the Telegram Bot API. There is no build step — all scripts are interpreted PowerShell.

## Installation & Running

```powershell
# First-time setup (requires Administrator UAC prompt)
powershell.exe -ExecutionPolicy Bypass -File ".\setup_tasks.ps1"

# Run individual monitors manually (for testing)
powershell.exe -ExecutionPolicy Bypass -File ".\event_monitor.ps1"
powershell.exe -ExecutionPolicy Bypass -File ".\performance_monitor.ps1"
powershell.exe -ExecutionPolicy Bypass -File ".\network_monitor.ps1"
powershell.exe -ExecutionPolicy Bypass -File ".\daily_report.ps1" -ReportType daily
powershell.exe -ExecutionPolicy Bypass -File ".\daily_report.ps1" -ReportType weekly

# Run the bot listener interactively
powershell.exe -ExecutionPolicy Bypass -File ".\bot_commands.ps1"
```

`setup_tasks.ps1` is the full installer: it validates config, auto-detects/installs ffmpeg, enables Windows audit policies, localizes the task XML templates, and registers all 6 scheduled tasks.

## Configuration

Copy `config.example.json` → `config.json` and fill in:
- `botToken` — Telegram bot token (required)
- `chatID` — Telegram chat ID (required)
- `installPath` — absolute path to this repo (auto-set by setup_tasks.ps1)
- `cpuThreshold`, `memoryThreshold`, `diskThreshold` — alert thresholds (default 90)
- `ffmpegPath`, `cameraDeviceName`, `microphoneDeviceName` — auto-detected if omitted

`config.json` and `network_state.json` are gitignored (they contain credentials and runtime state).

## Architecture

### Shared Library: `pc_monitor_common.ps1`

Every script dot-sources this file at the top (`". $PSScriptRoot\pc_monitor_common.ps1"`). It provides ~40 functions organized around:
- **Config I/O**: `Get-PcMonitorConfig`, `Save-PcMonitorConfig`
- **Telegram API**: `Send-PcMonitorTelegramMessage`, `Send-PcMonitorTelegramPhoto`, `Send-PcMonitorTelegramDocument`, `Save-PcMonitorTelegramDocument`
- **Logging**: `Write-PcMonitorActivity`, `Get-PcMonitorRecentActivity` — writes JSON lines to `data/logs/activity.log`
- **Task management**: `Get-PcMonitorTaskDefinitions`, `Sync-PcMonitorTaskXml`, `Install-PcMonitorTasks`
- **Media**: `Get-PcMonitorFfmpegPath`, `Install-PcMonitorFfmpeg`, `Get-PcMonitorDirectShowDevices`

When adding new shared functionality, add it here and prefix functions with `PcMonitor` following the `Verb-PcMonitorNoun` pattern.

### Scheduled Task Model

Six Windows Scheduled Tasks drive the system. XML templates live in `tasks/` with placeholder paths; `setup_tasks.ps1` localizes them per machine.

| Task | Script | Runs As | Trigger |
|------|--------|---------|---------|
| Event Monitor | `event_monitor.ps1` | SYSTEM | Every 5 min |
| Performance Monitor | `performance_monitor.ps1` | SYSTEM | Every 5 min |
| Network Monitor | `network_monitor.ps1` | SYSTEM | Every 5 min |
| Daily Report | `daily_report.ps1 -ReportType daily` | SYSTEM | Daily 8 AM |
| Weekly Report | `daily_report.ps1 -ReportType weekly` | SYSTEM | Tuesday 2 PM |
| Bot Commands | `bot_commands.ps1` | Current User | Continuous |

Bot Commands is the only task running as the current user (needed for UI interaction: screenshots, clipboard, simulated keystrokes). The other five run as SYSTEM for system-level access.

### Activity Log

All scripts write to `data/logs/activity.log` as JSON lines:
```json
{"Timestamp":"2026-05-04T13:18:46","Computer":"HOSTNAME","User":"User","Category":"bot","Action":"command-received","Detail":"/shutdown"}
```
Categories: `event`, `bot`, `network`. This log feeds the daily/weekly summary reports.

### Bot Command Flow

`bot_commands.ps1` uses Telegram long-polling. A Mutex prevents concurrent instances. Commands map directly to PowerShell logic in the same file — no routing layer. New commands are added by extending the `switch` block in that script.

### File Transfer Paths

- Incoming files (from Telegram to PC): `data/incoming/`
- Outgoing files (PC to Telegram): `data/outgoing/`

### Windows Event IDs Used

- `4624` — successful login
- `4625` — failed login
- `4800` / `4801` — screen lock / unlock
- `1102` — security log cleared (tamper alert)

## Key Constraints

- **Windows only** — relies on Windows Event Log, WMI/CIM, Task Scheduler, and DirectShow APIs.
- **PowerShell 5.1+** — no PowerShell Core (pwsh) features used, but compatible with both.
- **SYSTEM context** — most tasks run as SYSTEM; user-level paths (Desktop, Documents) resolved via registry lookup in `Get-PcMonitorKnownLocations`.
- **No webhooks** — bot polling only; intervals are hardcoded.
- **Task XML are templates** — never commit absolute paths into `tasks/*.xml`; always use the placeholder variables that `Sync-PcMonitorTaskXml` replaces.
