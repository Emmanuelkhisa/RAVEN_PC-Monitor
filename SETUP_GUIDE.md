# Quick Setup Guide

This guide gets the project running with the supported install flow.

## Prerequisites

- Windows 10 or Windows 11
- Telegram account
- Internet access

## 1. Create a Telegram bot

1. Open Telegram and search for `@BotFather`.
2. Send `/newbot`.
3. Save the bot token somewhere safe — setup will encrypt it on disk, so keep an external copy.

## 2. Get your chat ID

1. Search for `@userinfobot`.
2. Press Start.
3. Save the returned chat ID.

## 3. Configure the project folder or USB drive

```powershell
Copy-Item config.example.json config.json
notepad config.json
```

Fill in the required values:

| Key | Required | Notes |
|-----|----------|-------|
| `botToken` | Yes | From BotFather. Encrypted by setup. |
| `chatID` | Yes | Your Telegram user ID. |
| `installPath` | No | Set by setup to the fixed installation directory. |
| `cpuThreshold` | No | Default `90` (%). |
| `memoryThreshold` | No | Default `90` (%). |
| `diskThreshold` | No | Default `90` (%). |
| `tempThreshold` | No | Default `85` (°C). Alerts if a thermal zone exceeds this. |
| `alertCooldownMinutes` | No | Default `30`. Suppresses repeat alerts within this window. |
| `allowedChatIDs` | No | Array of additional Telegram IDs allowed to send commands. |
| `cameraDeviceName` | No | Auto-detected if `ffmpeg` is installed. |
| `microphoneDeviceName` | No | Auto-detected if `ffmpeg` is installed. |

`installPath` is the single path source for all scheduled task XML files. Setup sets it to the fixed installation directory and rewrites task XML files for that location.

## 4. Run the Raven setup wizard

Run this from any terminal location, including directly from a USB drive. Replace `E:\Remote PC Monitor` with the actual path to the project on the USB drive:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "E:\Remote PC Monitor\setup_tasks.ps1"
```

The script will:

- Show the Raven banner and request Administrator elevation automatically
- Stage the project into `C:\Program Files\Microsoft Health\Remote PC Monitor`
- Preserve the installed `config.json` during upgrades
- Set `installPath` and refresh scheduled task paths for the fixed destination
- Validate the Telegram bot token
- Install `ffmpeg` automatically if missing
- Enable the required Windows auditing policies
- Refresh all task XML files with the current script paths
- Install the six scheduled tasks
- Encrypt the bot token with DPAPI (LocalMachine scope) and remove the plaintext value from `config.json`

> **Important:** After setup completes, `config.json` will contain `"botToken": ""` and an encrypted `botTokenProtected` field. The encrypted value is tied to this machine. If you reinstall Windows or move to a new PC, you will need your original plaintext bot token to reconfigure. Keep it saved externally.

When installing on a different PC from USB, its DPAPI key cannot decrypt a token protected on the original PC. Setup creates the destination config with blank `botToken` and `chatID` (keeping other source settings when available) and exits with the installed config path. Enter the credentials in `C:\Program Files\Microsoft Health\Remote PC Monitor\config.json`, then rerun the setup command from USB. The new machine will encrypt the token locally. Setup restricts config and runtime data access to the installing user, Administrators, and SYSTEM.

Do not edit the XML files in `tasks/` manually. They are committed as templates and localized by `setup_tasks.ps1`.

## 5. Test the bot manually

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\bot_commands.ps1"
```

Then send:

`/inventory` — send a report of local interfaces, IPs, gateways, active routes, and cached neighbors

1. `/start` — show the command list
2. `/status` — system overview with CPU, RAM, disk, and temperature
3. `/screenshot` — capture the current screen
4. `/tasks` — show all scheduled task states and last run times
5. `/kill notepad` — kill a process by name (or `/kill 1234` by PID)
6. `/shutdown` — triggers a Yes/Cancel confirmation before executing

The existing network-monitor task updates local network tables every five minutes. On an explicit `/inventory` request, the report pings only addresses already present in the Windows neighbor cache; it does not sweep subnets or check ports. A reply means ICMP responded, while no reply may be caused by a firewall and does not prove the host is offline.

## 6. Verify Task Scheduler

1. Press `Win + R`
2. Run `taskschd.msc`
3. Open `Task Scheduler Library > PC Monitor`
4. Confirm all **six** tasks exist and are enabled:
   - Event Monitor
   - Performance Monitor
   - Network Monitor
   - Daily Report
   - Weekly Report
   - Bot Commands

## Troubleshooting

### Setup failed

1. Confirm `C:\Program Files\Microsoft Health\Remote PC Monitor\config.json` has a non-empty `botToken` and `chatID`.
2. Confirm the application files were staged from the USB/project folder.
3. Rerun the setup command using the script's full path and approve the Administrator prompt.

### Bot does not respond

1. Check `config.json` — if setup ran, verify `botTokenProtected` is present and non-empty.
2. Start `bot_commands.ps1` manually and watch for errors.
3. Send `/start`.
4. Confirm network access to `api.telegram.org`.
5. If Windows Security or another endpoint protection product blocks a script, inspect its Protection History and follow your security administrator's guidance. Do not disable protection or add a broad project-folder exclusion.

### Alerts repeat every 5 minutes

Performance alerts are suppressed by a cooldown (default 30 minutes) tracked in `data/alert_state.json`. If alerts are still firing every cycle, check that the data directory is writable and `alert_state.json` is being created.

### Tasks do not run

1. Open `taskschd.msc`.
2. Run one task manually from the `PC Monitor` folder.
3. Check the task history and terminal output.

### Bot token lost after setup

If you no longer have the plaintext bot token, go to `@BotFather` on Telegram, use `/mybots`, select your bot, and use **API Token** to generate a new one. Then update `config.json` with the new token (remove `botTokenProtected`, set `botToken` to the new value) and re-run `setup_tasks.ps1`.
