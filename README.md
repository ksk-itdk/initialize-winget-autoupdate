# initialize-winget-autoupdate

Intune remediation script that runs [Winget-AutoUpdate (WAU)](https://github.com/Romanitho/Winget-AutoUpdate) from Intune instead of from WAU's own scheduled task.

When WAU is started by the Intune Management Extension, the installs it performs run under Intune's managed installer, so with WDAC (App Control for Business) configured to trust the managed installer, updated applications are whitelisted automatically.

## What it does

1. Logs the execution context (IsSystem / IsAdmin / user / session id).
2. Disables the `Winget-AutoUpdate` scheduled task if it exists and is enabled (admin only), so WAU is only run through Intune.
3. Locates `winget-upgrade.ps1` in the first existing location:
   - `C:\Program Files\Winget-AutoUpdate\Winget-Upgrade.ps1`
   - `C:\Program Files\Winget-Autoupdate-aaS\Winget-AutoUpdate\Winget-Upgrade.ps1`
   - `C:\ProgramData\Winget-AutoUpdate\winget-upgrade.ps1`
4. Uses `C:\ProgramData\Winget-AutoUpdate\Invisible.vbs`, or `$ToolsDir\Invisible.vbs` if missing. When admin, `Invisible.vbs` is downloaded from `$InvisibleUrl` into `$ToolsDir`.
5. Starts `winget-upgrade.ps1` hidden via `wscript.exe` + `Invisible.vbs`.
6. Polls for up to 60 seconds for a WAU `updates.log` written after the script started.

Exit codes: `0` = Compliant (WAU launched and verified), `1` = Not Compliant.

## Configuration

Fill out the `Variables: Configuration` block at the top of the script before deploying:

| Variable | Description |
|---|---|
| `$ToolsDir` | Local folder that `Invisible.vbs` is downloaded to, e.g. `C:\Windows\Companyname\Tools` |
| `$InvisibleUrl` | Download URL for `Invisible.vbs`, e.g. a blob storage URL |

## SYSTEM vs. user context

The script is intended to run as **SYSTEM**. It also runs in user context; steps that need admin rights are gated on `$IsAdmin` (Administrators SID `S-1-5-32-544` enabled in the process token):

| | SYSTEM / admin | User |
|---|---|---|
| Log file | `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\initialize-winget-autoupdate.log` | `C:\ProgramData\Logs\Software\initialize-winget-autoupdate.log` |
| Disable `Winget-AutoUpdate` task | Yes | Skipped |
| Download `Invisible.vbs` | Yes | Skipped - an existing copy in `$ToolsDir` (from a SYSTEM run) is required |

Logs rotate at 1 MB, keeping at most 3 files.

### Notes for user context

- WAU only skips machine-wide apps in user context when `winget_system_apps.txt` exists, which WAU creates during a SYSTEM run with `WAU_UserContext = 1`. Without it, WAU tries to update machine-wide apps as the user, which triggers UAC prompts a standard user cannot approve.
- The user-context log file is owned by the first user that creates it; on shared devices other users cannot append to it (the script continues without logging to file).
