# Remote PC Monitor

Windows PC monitoring Tool that sends and reports through Telegram.

## Features

- ##### RAT Remote Access Tool*
- ##### Remote Control
- ##### Camera snapshots and microphone recordings via `ffmpeg`
- ##### Screenshot Capturing
- ##### Network adapter, IP, and VPN change detection
- ##### Remote PowerShell and CMD execution (`/run`, `/ps`, `/cmd`) - directly from telegram
- Login and failed-login alerts with anomaly detection for off-hours logins
- Event log tamper alerts
- Process launch and file access monitoring
- USB removable drive insertion alerts
- CPU, memory, disk, network, and temperature health checks with configurable cooldowns (no repeat spam)
- Network inventory tracking with interface IPs, gateways, DNS, active routes, and cached neighbors; `/inventory` pings cached addresses on request
- Telegram command centre: status, screenshots, file movement, clipboard, launching apps, typing text, process management, and power actions
- Inline Yes/Cancel confirmation for destructive power commands (shutdown, restart, sleep)
- Process kill by name or PID (`/kill`)
- Scheduled task health dashboard (`/tasks`)
- Telegram file inbox for sending files from phone to PC
- Activity history shared across alerts, reports, and remote commands

- Daily and weekly summary reports with alert counts and top command usage
- Bot token encrypted on disk with DPAPI (machine-scoped, no plaintext at rest after setup)

## Quick Start

### 1. Create a Telegram bot

1. Open Telegram and search for `BotFather`.
2. Send `/newbot`.
3. Save the bot token. Keep it somewhere external — setup encrypts and removes the plaintext value from `config.json`.

### 2. Get your chat ID

1. Open Telegram and search for `userinfobot`.
2. Press Start.
3. Save the chat ID it returns.

### 3. Configure `config.json` on the project folder or USB drive

```powershell
Copy-Item config.example.json config.json
notepad config.json
```

Required fields:

```json
{
  "botToken": "YOUR_BOT_TOKEN_HERE",
  "chatID": "YOUR_CHAT_ID_HERE"
}
```

Optional fields with their defaults:

```json
{
  "cpuThreshold": 90,
  "memoryThreshold": 90,
  "diskThreshold": 90,
  "tempThreshold": 85,
  "alertCooldownMinutes": 30,
  "allowedChatIDs": [],
  "installPath": "",
  "cameraDeviceName": "",
  "microphoneDeviceName": ""
}
```

`allowedChatIDs` is an array of additional Telegram user IDs permitted to send commands beyond the primary `chatID`. `alertCooldownMinutes` sets the minimum gap between repeat alerts for the same metric. `installPath` is set by setup.

### 4. Enable Windows auditing

`setup_tasks.ps1` configures the required audit policies automatically.
If you ever need to do it manually, run PowerShell as Administrator:

```powershell
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Process Creation" /success:enable
auditpol /set /subcategory:"Other Logon/Logoff Events" /success:enable /failure:enable
```

### 5. Run setup

The installer uses the script's location, not the terminal's current directory. Run it directly from the project folder or from a USB drive, replacing `E:\Remote PC Monitor` with the actual project path:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\Remote PC Monitor\setup_tasks.ps1"
```

This will:

- Request elevation automatically
- Copy the application to `C:\Program Files\Microsoft Health\Remote PC Monitor`
- Preserve the existing installed config on upgrades
- Set `installPath` to the fixed destination
- Validate your Telegram bot token
- Install `ffmpeg` automatically if missing
- Enable the required Windows audit policies
- Refresh all task XML files with the current script paths
- Install all six scheduled tasks
- Encrypt the bot token with LocalMachine DPAPI and remove the plaintext from `config.json`

The committed XML files in `tasks/` are templates. They ship with placeholder paths so the repo stays portable across machines.

If moving the project to another PC after setup, the source `botTokenProtected` value cannot be decrypted there. The installer creates a fresh destination config with blank `botToken` and `chatID` while preserving other settings, then exits with instructions. Edit `C:\Program Files\Microsoft Health\Remote PC Monitor\config.json` with the token and chat ID, and rerun setup from the USB drive. The new PC will encrypt the token for itself. Keep the plaintext token somewhere safe.

The installer's runtime data and config files are ACL-restricted to the installing user, Administrators, and SYSTEM. Application files remain under Program Files.

The existing five-minute network-monitor task snapshots local Windows network configuration, active routes, and the neighbor cache. When `/inventory` is explicitly requested, it sends one bounded ICMP ping to each unique address already in that cache and includes the result and response time. It does not sweep address ranges or check ports. A reply confirms the address responded to ICMP; no reply is not proof of an inactive host because firewalls may block ping. Devices not in the neighbor cache are not pinged.

## Manual Test

Start the bot listener manually:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\bot_commands.ps1"
```

Send `/start` or `/help` in Telegram for the built-in command list. The full command reference follows.

## Telegram Command Reference

Commands are handled for the configured primary `chatID` and any IDs in `allowedChatIDs`. Commands that return files or media send those as Telegram attachments; ordinary replies are text.

### Observe

| Command | What it does | Typical feedback |
|---------|--------------|-----------------|
| `/start` or `/help` | Shows the bot's command summary. | Text containing the command groups and usage. |
| `/status` | Reports PC name, logged-in user, Windows version, uptime, primary IPv4 address, active window, CPU/load, memory, C: usage, and temperature when available. | `[COMMAND CENTRE STATUS]`, followed by values such as `CPU: ...`, `Memory: ...`, `Disk C: ...`. |
| `/inventory` | Sends a text report of local interfaces, IP addresses, gateways, DNS servers, active routes, and cached neighbors, including cache history. Pings only unique addresses already in the Windows neighbor cache when requested; no subnet sweep or port checks. | A `.txt` attachment with `Reachable`, `No ICMP reply`, or an error result and response time. Firewalls can block ICMP, so no reply does not prove offline. |
| `/screenshot` | Captures the primary display and sends it as a photo. | An image, captioned with the active window title when available. |
| `/camera` | Captures one image from the configured camera and sends it as a document. Requires `ffmpeg` and `cameraDeviceName`. | A camera snapshot attachment. |
| `/recordmic [seconds]` | Records audio from the configured microphone and sends it as a document. Requires `ffmpeg` and `microphoneDeviceName`; duration is limited to 3–60 seconds and defaults to 60. | A WAV attachment with a duration caption; for example, `/recordmic 15` records 15 seconds. |
| `/active` | Reports the title of the foreground window. | `[ACTIVE WINDOW] <window title>` or `Unknown`. |
| `/clipboard` | Reads the current text clipboard, up to 500 characters. | `[CLIPBOARD]` and the text, or `[CLIPBOARD] Empty`. |
| `/processes` | Lists up to 10 processes ordered by accumulated CPU time. | Process names with CPU seconds and RAM in MB. |

### Files and data

The path aliases are `desktop`, `documents`, `downloads`, `pictures`, and `temp`. Absolute paths and paths relative to the project directory can also be used.

| Command | What it does | Typical feedback |
|---------|--------------|-----------------|
| `/ls [path]` | Lists up to 20 items in a folder; defaults to `downloads`. | `[FILES] <resolved path>` followed by `[DIR]` / `[FILE]`, size, and modified time. Example: `/ls documents`. |
| `/find <name-fragment> [root]` | Recursively searches for a file-name fragment under `root`; defaults to `downloads`, returns up to 10 newest matches. The name fragment cannot contain spaces. | `[SEARCH] Matches for 'invoice' ...` and matching paths, or a no-match message. Example: `/find invoice documents`. |
| `/pull <path>` | Sends a file from the PC to Telegram. | A document attachment with the file path as its caption. Example: `/pull downloads\report.pdf`. |
| `/inbox [count]` | Lists the newest files received from Telegram; defaults to 10. | `[INBOX] Recent uploaded files` with names, sizes, and times, or an empty-inbox message. |
| Send a document | Saves a Telegram document to the PC's `data\incoming` folder. | A confirmation naming the saved path. |
| Caption a document with `/save <path>` | Saves that incoming document to the selected folder or alias instead of the default inbox. | The same saved-path confirmation. Example caption: `/save documents`. |
| `/recent [count]` | Lists recently modified files from the known folders; defaults to 10. | `[RECENT CHANGES]` followed by paths and modified times, or a no-files message. |

### Control the PC

| Command | What it does | Typical feedback |
|---------|--------------|-----------------|
| `/open <app-or-path>` | Opens an application or target using Windows. | `[EXECUTED] Opened <target>`. Example: `/open notepad`. |
| `/kill <process-name-or-PID>` | Force-stops a process by name or numeric PID. A process name can match multiple processes. | `[KILLED]` with the process/PID, or `[FAILED]` with the error. Example: `/kill notepad` or `/kill 4321`. |
| `/setclipboard <text>` | Replaces the Windows clipboard text. | `[UPDATED] Clipboard text set.` Example: `/setclipboard meeting at 3`. |
| `/type <text>` | Types text into the currently focused window. | `[EXECUTED] Text sent to active window.` Example: `/type hello there`. |
| `/run <PowerShell>` or `/ps <PowerShell>` | Runs the supplied PowerShell command and returns its output. `/run` and `/ps` are aliases. | `[POWERSHELL]` followed by output, capped at 3,500 characters. Example: `/ps Get-Service`. |
| `/cmd <command>` | Runs a command through `cmd.exe /c`. | `[CMD]` followed by output, capped at 3,500 characters. Example: `/cmd whoami`. |
| `/lock` | Locks the Windows session. | `[EXECUTED] PC locked`, then the session locks. |
| `/sleep`, `/shutdown`, `/restart` | Requests the corresponding power action. The action occurs only after pressing **Yes, proceed** on the inline confirmation; **Cancel** aborts it. | A confirmation prompt, followed by an execution or cancellation message. |

### Routines and review

| Command | What it does | Typical feedback |
|---------|--------------|-----------------|
| `/routine snapshot` | Sends system status and clipboard text, then captures and sends a screenshot. | Two text messages and a photo. |
| `/routine workspace` | Sends system status, top processes, and up to eight recent file changes. | Three text reports. |
| `/history [count]` | Shows recent bot/monitor activity; defaults to 12 entries. | `[HISTORY]` followed by timestamp, category, action, and detail. |
| `/tasks` | Shows the installed scheduled monitor tasks, state, last run, and result. | `[SCHEDULED TASKS]` with one row per task; missing tasks are marked `Not installed`. |

Unknown slash commands return `[ERROR] Unknown command. Use /help.` Confirmation buttons are callback actions, not commands to type. Commands such as `/run`, `/cmd`, `/kill`, `/pull`, clipboard access, camera, microphone, and power actions can affect or expose the PC; use them only from an authorized chat.

## File Structure

```text
Remote PC Monitor/
|-- bot_commands.ps1
|-- daily_report.ps1
|-- event_monitor.ps1
|-- network_monitor.ps1
|-- pc_monitor_network_inventory.ps1
|-- pc_monitor_common.ps1
|-- performance_monitor.ps1
|-- setup_tasks.ps1
|-- config.example.json
|-- config.json
|-- tasks/
|   |-- BotCommandsTask.xml
|   |-- DailyReportTask.xml
|   |-- EventMonitorTask.xml
|   |-- NetworkMonitorTask.xml
|   |-- PerformanceMonitorTask.xml
|   |-- WeeklyReportTask.xml
|-- README.md
`-- LICENSE
```

## Scripts

| Script | Purpose |
|--------|---------|
| `pc_monitor_common.ps1` | Shared config, Telegram, logging, task, and security helpers |
| `event_monitor.ps1` | Windows event alerts (logins, lock/unlock, log tampering, off-hours anomalies) |
| `performance_monitor.ps1` | CPU, memory, disk, network, and temperature threshold checks with cooldowns |
| `network_monitor.ps1` | Adapter, IP, and VPN change detection |
| `daily_report.ps1` | Daily/weekly summary with alert counts and top bot commands |
| `bot_commands.ps1` | Telegram long-poll command listener |

## Scheduled Tasks

| Task | Runs As | Trigger |
|------|---------|---------|
| Event Monitor | SYSTEM | Every 5 min |
| Performance Monitor | SYSTEM | Every 5 min |
| Network Monitor | SYSTEM | Every 5 min |
| Daily Report | SYSTEM | Daily 8 AM |
| Weekly Report | SYSTEM | Tuesday 2 PM |
| Bot Commands | Current User | On logon (continuous) |

## Setup Model

For GitHub users and forks, the supported setup flow is:

1. Clone or download the repository
2. Copy `config.example.json` to `config.json`
3. Fill in `botToken` and `chatID`
4. Optionally set `tempThreshold`, `alertCooldownMinutes`, or `allowedChatIDs`
5. Run `setup_tasks.ps1` and approve the Administrator prompt

Do not manually edit the XML files in `tasks/`. `setup_tasks.ps1` localizes them automatically for the current machine.

## Troubleshooting

### No alerts

1. Verify `config.json` has the right bot token and chat ID.
2. Run `taskschd.msc` and confirm the `PC Monitor` tasks exist and are enabled.
3. Confirm the `Logon` and `Other Logon/Logoff Events` audit subcategories are enabled.
4. Run a script manually: `powershell.exe -ExecutionPolicy Bypass -File ".\event_monitor.ps1"`

### Bot commands do not respond

1. Start `bot_commands.ps1` manually and watch for errors.
2. Send `/start`.
3. Confirm the machine can reach `api.telegram.org`.
4. Check that `botTokenProtected` in `config.json` is non-empty (set by setup).

### Alerts repeat every cycle despite cooldowns

Check that `data/alert_state.json` is being created and is writable. If the file does not exist after an alert fires, the data directory may not be writable by the SYSTEM account.

### Tasks do not install

1. Re-run `setup_tasks.ps1` and approve the UAC prompt.
2. If `winget` is unavailable, install the Microsoft App Installer package and try again.
3. Review the terminal output for the failing task name.

### Bot token lost after setup

Go to `@BotFather` on Telegram, use `/mybots`, select your bot, and use **API Token** to revoke and generate a new one. Then remove `botTokenProtected` from `config.json`, set `botToken` to the new value, and re-run `setup_tasks.ps1`.

## Security Notes

- The bot token is encrypted with Windows DPAPI (LocalMachine scope) by `setup_tasks.ps1`. The plaintext token is removed from `config.json` after setup. Keep the original token noted externally — it cannot be recovered from the encrypted value on a different machine.
- Use `allowedChatIDs` to restrict which Telegram users can issue commands. Any message from an unknown chat ID is silently ignored.
- Rotate the Telegram bot token via `@BotFather` if it is ever exposed.
- `/shutdown`, `/restart`, and `/sleep` require inline confirmation before executing.

## Changelog

### Version 3.0 - 2026-09-11

- Alert cooldowns: repeat performance alerts suppressed for a configurable window (default 30 min)
- Temperature monitoring via WMI thermal zones; shown in `/status` and performance alerts
- Off-hours login anomaly detection (flags logins between 23:00–06:00)
- USB removable drive alerts via WMI event subscription in the bot listener
- `/kill <name|PID>` command to terminate processes remotely
- `/run` as an alias for `/ps` (arbitrary PowerShell execution)
- `/tasks` command to view all scheduled task states and last run results
- Inline keyboard confirmation for `/shutdown`, `/restart`, and `/sleep`
- Bot token encrypted on disk with LocalMachine DPAPI after setup
- `allowedChatIDs` config array for multi-user command access
- Richer daily/weekly reports: alert counts by category, top bot commands

### Version 2.0 - 2026-03-17

- Added multi-event monitoring
- Added Telegram bot commands
- Added performance monitoring
- Added network monitoring
- Added daily and weekly reports
- Removed legacy and duplicate installer scripts
- Consolidated shared logic into `pc_monitor_common.ps1`

### Version 1.0 2026-02-13

- Basic login monitoring
