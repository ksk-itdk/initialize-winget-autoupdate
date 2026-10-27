# initialize-winget-autoupdate

Intune remediation script that runs [Winget-AutoUpdate (WAU)](https://github.com/Romanitho/Winget-AutoUpdate) from Intune instead of from WAU's own scheduled task.

When WAU is started by the Intune Management Extension, the installs it performs run under Intune's managed installer, so with WDAC (App Control for Business) configured to trust the managed installer, updated applications are whitelisted automatically.

## What it does

1. Logs the execution context (IsSystem / IsAdmin / user / session id).
2. When admin and `$MoveUserLogsToSystemLogDir` is `$true`, moves the user-context logs into the Intune Management Extension log folder (see [User logs](#user-logs)).
3. Disables the `Winget-AutoUpdate` scheduled task if it exists and is enabled (admin only), so WAU is only run through Intune.
4. Locates `winget-upgrade.ps1` in the first existing location:
   - `C:\Program Files\Winget-AutoUpdate\Winget-Upgrade.ps1`
   - `C:\Program Files\Winget-Autoupdate-aaS\Winget-AutoUpdate\Winget-Upgrade.ps1`
   - `C:\ProgramData\Winget-AutoUpdate\winget-upgrade.ps1`
5. Uses `C:\ProgramData\Winget-AutoUpdate\Invisible.vbs`, or `$ToolsDir\Invisible.vbs` if missing. When admin, `Invisible.vbs` is downloaded from `$InvisibleUrl` into `$ToolsDir`.
6. Starts `winget-upgrade.ps1` hidden via `wscript.exe` + `Invisible.vbs`.
7. Polls for up to 60 seconds for a WAU `updates.log` written after the script started.

Exit codes: `0` = Compliant (WAU launched and verified), `1` = Not Compliant.

## Configuration

All settings are in the `Variables: Configuration` block at the top of the script. Fill out at least `$ToolsDir` and `$InvisibleUrl` before deploying; the rest have working defaults.

| Variable | Default | Description |
|---|---|---|
| `$ToolsDir` | `C:\Windows\Companyname\Tools` | Local folder that `Invisible.vbs` is downloaded to |
| `$InvisibleUrl` | `https://storageaccount.blob.core.windows.net/...` | Download URL for `Invisible.vbs`, e.g. a blob storage URL |
| `$SystemLogDir` | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs` | Log folder when running as admin (SYSTEM) |
| `$UserLogDir` | `C:\ProgramData\Logs\Software` | Log folder when running as a user |
| `$LogFileName` | `initialize-winget-autoupdate.log` | Log file name |
| `$LogMaxSizeBytes` | `1MB` | Rotate the log when it exceeds this size |
| `$LogMaxFiles` | `3` | Log files to keep (current + rotated) |
| `$MoveUserLogsToSystemLogDir` | `$true` | Move user logs into `$SystemLogDir` when running as admin. `$false` = leave them in place |
| `$UserLogArchiveName` | `initialize-winget-autoupdate-user.log` | File in `$SystemLogDir` that user logs are appended to |
| `$WauTaskName` | `Winget-AutoUpdate` | WAU scheduled task that is disabled |
| `$UpgradeScriptCandidates` | see above | `winget-upgrade.ps1` locations in priority order |
| `$WauInvisibleVbs` | `C:\ProgramData\Winget-AutoUpdate\Invisible.vbs` | `Invisible.vbs` in the WAU working directory |
| `$UpdateLogCandidates` | WAU `logs\updates.log` locations | Logs checked to confirm that WAU ran |
| `$UpdateLogMaxWaitSeconds` | `60` | How long to wait for `updates.log` after launch |
| `$UpdateLogPollSeconds` | `5` | How often to check `updates.log` |

## SYSTEM vs. user context

The script is intended to run as **SYSTEM**. It also runs in user context; steps that need admin rights are gated on `$IsAdmin` (Administrators SID `S-1-5-32-544` enabled in the process token):

| | SYSTEM / admin | User |
|---|---|---|
| Log file | `$SystemLogDir` (IME logs folder) | `$UserLogDir` (`C:\ProgramData\Logs\Software`) |
| Move user logs to `$SystemLogDir` | Yes, if `$MoveUserLogsToSystemLogDir = $true` | Skipped |
| Disable `Winget-AutoUpdate` task | Yes | Skipped |
| Download `Invisible.vbs` | Yes | Skipped - an existing copy in `$ToolsDir` (from a SYSTEM run) is required |

Logs rotate at 1 MB, keeping at most 3 files.

### User logs

Users cannot write to the IME logs folder, so user-context runs log to `$UserLogDir`. With `$MoveUserLogsToSystemLogDir = $true`, the next SYSTEM run appends those logs (rotated files first, oldest first) to `$SystemLogDir\initialize-winget-autoupdate-user.log` and deletes them, so they are included when Intune collects the IME logs. The archive file is rotated like the main log.

### Notes for user context

- WAU only skips machine-wide apps in user context when `winget_system_apps.txt` exists, which WAU creates during a SYSTEM run with `WAU_UserContext = 1`. Without it, WAU tries to update machine-wide apps as the user, which triggers UAC prompts a standard user cannot approve.
- The user-context log file is owned by the first user that creates it; on shared devices other users cannot append to it (the script continues without logging to file).
