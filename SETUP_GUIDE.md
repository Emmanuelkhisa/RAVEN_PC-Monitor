# Quick Setup Guide

This guide gets the project running with the supported install flow.

## Prerequisites

- Windows 10 or Windows 11
- Telegram account
- Internet access

## 1. Create a Telegram bot

1. Open Telegram and search for `@BotFather`.
2. Send `/newbot`.
3. Save the bot token.

## 2. Get your chat ID

1. Search for `@userinfobot`.
2. Press Start.
3. Save the returned chat ID.

## 3. Configure the project

```powershell
Copy-Item config.example.json config.json
notepad config.json
```

Replace the placeholder values with your bot token and chat ID.
You can leave `installPath` as the placeholder value. The setup wizard will replace it with the current project folder automatically.
If you want camera and microphone commands, keep the device names filled in. `ffmpeg` is now installed automatically by setup when needed.

## 4. Run the Raven setup wizard

Run this once in the project directory:

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\setup_tasks.ps1"
```

The script will:

- Show the Raven banner
- Detect and save the install path
- Request Administrator approval automatically
- Validate the Telegram bot token
- Install `ffmpeg` automatically if it is missing
- Enable the required Windows auditing policies
- Refresh all task XML files
- Install the six supported scheduled tasks

Do not edit the XML files in `tasks/` manually. They are committed as templates and localized by `setup_tasks.ps1`.

## 5. Test the bot manually

```powershell
powershell.exe -ExecutionPolicy Bypass -File ".\bot_commands.ps1"
```

Then send:

1. `/start`
2. `/status`
3. `/screenshot`

## 6. Verify Task Scheduler

1. Press `Win + R`
2. Run `taskschd.msc`
3. Open `Task Scheduler Library > PC Monitor`
4. Confirm all six tasks exist and are enabled

## Troubleshooting

### Setup failed

1. Confirm `config.json` exists.
2. Confirm all `.ps1` files are still in the project directory.
3. Confirm `installPath` in `config.json` is correct or still a placeholder.
4. Re-run `setup_tasks.ps1` and approve the Administrator prompt.

### Bot does not respond

1. Check `config.json`.
2. Start `bot_commands.ps1` manually.
3. Send `/start`.
4. Confirm network access to Telegram.

### Tasks do not run

1. Open `taskschd.msc`.
2. Run one task manually from the `PC Monitor` folder.
3. Check the task history and terminal output.
