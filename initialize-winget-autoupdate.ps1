<#
.SYNOPSIS
    Disables the Winget-AutoUpdate scheduled task and launches winget-upgrade.ps1 hidden as a remediation.

.DESCRIPTION
    Intended to run as an Intune remediation script. The script:
      1. Logs the execution context (IsSystem / IsAdmin / user / session id).
      2. When admin and $MoveUserLogsToSystemLogDir is $true, appends the user-context logs from
         $UserLogDir to $UserLogArchiveName in $SystemLogDir and deletes them.
      3. Disables the $WauTaskName scheduled task if it exists and is enabled (admin only).
      4. Locates winget-upgrade.ps1 in the first existing location of $UpgradeScriptCandidates:
           - C:\Program Files\Winget-AutoUpdate\Winget-Upgrade.ps1
           - C:\Program Files\Winget-Autoupdate-aaS\Winget-AutoUpdate\Winget-Upgrade.ps1
           - C:\ProgramData\Winget-AutoUpdate\winget-upgrade.ps1
      5. Uses $WauInvisibleVbs (C:\ProgramData\Winget-AutoUpdate\Invisible.vbs), or $ToolsDir\Invisible.vbs
         if missing. When admin, Invisible.vbs is downloaded from $InvisibleUrl into $ToolsDir; when not
         admin, an existing copy (placed by an earlier SYSTEM run) must be present.
      6. Starts winget-upgrade.ps1 invisibly via wscript.exe + Invisible.vbs (-EncodedCommand).
      7. Polls $UpdateLogCandidates for up to $UpdateLogMaxWaitSeconds (60) seconds for an updates.log
         written after the script started.

    Outputs "Compliant" (exit 0) when the run is confirmed; otherwise writes "Not Compliant" as a
    warning and exits 1.

    Supports SYSTEM and user context. Steps that need admin rights (IME log folder, moving user logs,
    disabling the scheduled task, downloading Invisible.vbs into $ToolsDir) are gated on $IsAdmin.

    Configuration: all settings are in the "Variables: Configuration" block at the top of the script.
    Before deploying, fill out at least $ToolsDir and $InvisibleUrl.

.NOTES
    Runs in SYSTEM context as an Intune Remediations script; also supports user context.
    Logs to $SystemLogDir\$LogFileName (C:\ProgramData\Microsoft\IntuneManagementExtension\Logs) when
    admin, otherwise to $UserLogDir\$LogFileName (C:\ProgramData\Logs\Software).

    Version:      1.2.0
    Release notes:
      1.2.0 - Moved all settings into the "Variables: Configuration" block at the top of the script:
              $SystemLogDir, $UserLogDir, $LogFileName, $LogMaxSizeBytes, $LogMaxFiles, $WauTaskName,
              $UpgradeScriptCandidates, $WauInvisibleVbs, $UpdateLogCandidates, $UpdateLogMaxWaitSeconds
              and $UpdateLogPollSeconds (renamed from $LogMaxWaitSeconds/$LogPollSeconds).
            - Added $MoveUserLogsToSystemLogDir (default $true): when running as admin (SYSTEM), the user
              logs in $UserLogDir (current + rotated, oldest first) are appended to $UserLogArchiveName
              (initialize-winget-autoupdate-user.log) in $SystemLogDir and then deleted, so they are
              collected with the Intune Management Extension logs. The archive is rotated like the main log.
              Set to $false to leave the user logs in place.
            - Invoke-LogRollover now takes the log path as a -Path parameter.
      1.1.5 - Added user-context support gated on $IsAdmin (Administrators SID S-1-5-32-544 enabled in
              the process token; a non-elevated/filtered token has it as deny-only and evaluates to $false):
            - Log file is written to the IME logs folder when admin, otherwise to
              C:\ProgramData\Logs\Software. Failure to create the log folder no longer stops the script.
            - Disabling the Winget-AutoUpdate task is skipped when not admin; "disabled" is only logged
              when Disable-ScheduledTask actually succeeded.
            - Invisible.vbs: when not admin, an existing $ToolsDir\Invisible.vbs is used
              instead of downloading; Not Compliant (1) if none exists.
            - Fixed false Compliant: Write-Log no longer throws when the log file cannot be written.
              Previously an Out-File failure inside try/catch skipped the "Exit 1" in the catch block, so
              the script ended with exit 0 without launching winget-upgrade.ps1.
            - Creating the Tools folder and downloading Invisible.vbs now stop on failure instead of
              logging success.
            - Startup banner shows the correct version and logs IsAdmin and the running user.
            - Moved the local Tools folder ($ToolsDir) and the Invisible.vbs download URL ($InvisibleUrl)
              into a "Variables: Configuration" block at the top of the script so they are easy to fill
              out, and restored the step-by-step .DESCRIPTION.
      1.1.4 - Converted the help header to valid comment-based help keywords: moved version and release
              notes from the invalid .VERSION/.RELEASENOTES keywords into .NOTES so Get-Help works.
      1.1.3 - Changed the post-launch updates.log verification from a same-day match to a strict
              "written at or after script start" comparison ($LastWrite -ge $ScriptStart). The same-day
              rule produced false positives by matching a pre-existing updates.log from an earlier run on
              the same day; the strict check confirms the log was written by the current run.
      1.1.2 - Added post-launch verification that winget-upgrade.ps1 actually ran: polls (up to 60s) the
              updates.log in priority order: 1) C:\Program Files\Winget-AutoUpdate\logs\updates.log,
              2) C:\Program Files\Winget-Autoupdate-aaS\Winget-AutoUpdate\logs\updates.log,
              3) C:\ProgramData\Winget-AutoUpdate\logs\updates.log. Compliant if at least one existing
              log has today's date; otherwise Not Compliant (1).
      1.1.1 - Fixed hidden launch failing when the winget-upgrade.ps1 path contains spaces
              (e.g. C:\Program Files\Winget-Autoupdate-aaS\...): switched the wscript/Invisible.vbs launch
              from -File "" ... "" to -EncodedCommand (Base64 of the UTF-16LE script call). The doubled-quote
              -File form was silently dropped by wscript for spaced paths, so the script never started.
      1.1.0 - Added a Test-Path check for winget-upgrade.ps1 before starting it; exits Not Compliant (1)
              if missing.
            - Added prioritized lookup for winget-upgrade.ps1; only the first existing script is run.
              Priority: 1) C:\Program Files\Winget-AutoUpdate\Winget-Upgrade.ps1,
              2) C:\Program Files\Winget-Autoupdate-aaS\Winget-AutoUpdate\Winget-Upgrade.ps1,
              3) $WorkingDir\winget-upgrade.ps1.
            - Added Invisible.vbs presence check: if not found in the working directory it is downloaded
              from $InvisibleUrl into $ToolsDir (created if missing) and used for the launch.
            - Replaced the $WorkingDir variable with the literal path C:\ProgramData\Winget-AutoUpdate in
              the active code paths (upgrade-script candidate and Invisible.vbs lookup).
            - Added per-candidate Write-Host output during the winget-upgrade.ps1 lookup.
            - Added file logging via a Write-Log helper: Write-Host/Write-Warning messages are also appended
              (with timestamp and level) to the IME log folder.
            - Added log rollover at 1 MB, keeping at most 3 files (.log, .1, .2); oldest is discarded.
            - Moved the log setup/Write-Log helper to the top so the startup banner, IsSystem and
              SessionID lines are also logged.
            - Fixed the wscript/Invisible.vbs launch: the entire PowerShell invocation is now passed as ONE
              quoted argument, since Invisible.vbs runs WScript.Arguments(0) as the full command line.
      1.0.0 - Initial versioned release.
#>

# Helper for consistent timestamp output
function Get-Now { (Get-Date).ToString('MM/dd/yyyy hh:mm:ss tt') }

## Variables: Configuration - fill out / review before deploying
# Local folder that Invisible.vbs is downloaded to when it is not present in the WAU working directory
$ToolsDir = "C:\Windows\Companyname\Tools"
# Download source for Invisible.vbs (only used when running as admin)
$InvisibleUrl = "https://storageaccount.blob.core.windows.net/config/Tools/Invisible.vbs"

# Log folders: admin (SYSTEM) logs to $SystemLogDir, users log to $UserLogDir (users cannot write to the IME folder)
$SystemLogDir = "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs"
$UserLogDir = "C:\ProgramData\Logs\Software"
$LogFileName = "initialize-winget-autoupdate.log"
$LogMaxSizeBytes = 1MB   # rotate when the log exceeds this size
$LogMaxFiles = 3         # total number of log files to keep (current + rotated)

# When running as admin (SYSTEM): append the user logs from $UserLogDir to $UserLogArchiveName in $SystemLogDir
# and delete them, so they are collected with the Intune Management Extension logs. $false = leave user logs in place.
$MoveUserLogsToSystemLogDir = $true
$UserLogArchiveName = "initialize-winget-autoupdate-user.log"

# Winget-AutoUpdate scheduled task that is disabled so WAU only runs through this script
$WauTaskName = "Winget-AutoUpdate"
# winget-upgrade.ps1 locations in priority order; the first existing one is run
$UpgradeScriptCandidates = @(
    "C:\Program Files\Winget-AutoUpdate\Winget-Upgrade.ps1",
    "C:\Program Files\Winget-Autoupdate-aaS\Winget-AutoUpdate\Winget-Upgrade.ps1",
    "C:\ProgramData\Winget-AutoUpdate\winget-upgrade.ps1"
)
# Invisible.vbs in the WAU working directory; $ToolsDir\Invisible.vbs is used when this is missing
$WauInvisibleVbs = "C:\ProgramData\Winget-AutoUpdate\Invisible.vbs"
# WAU updates.log locations checked to confirm that winget-upgrade.ps1 ran
$UpdateLogCandidates = @(
    "C:\Program Files\Winget-AutoUpdate\logs\updates.log",
    "C:\Program Files\Winget-Autoupdate-aaS\Winget-AutoUpdate\logs\updates.log",
    "C:\ProgramData\Winget-AutoUpdate\logs\updates.log"
)
$UpdateLogMaxWaitSeconds = 60   # how long to wait for updates.log after launch
$UpdateLogPollSeconds = 5       # how often to check updates.log

## Variables: Permissions/Accounts
[Security.Principal.WindowsIdentity]$CurrentProcessToken = [Security.Principal.WindowsIdentity]::GetCurrent()
[Boolean]$IsAdmin = [Boolean]($CurrentProcessToken.Groups -contains [Security.Principal.SecurityIdentifier]'S-1-5-32-544')

# Log file setup
if ($IsAdmin) {
    $LogDir = $SystemLogDir
}
else {
    $LogDir = $UserLogDir
}
$LogFile = Join-Path $LogDir $LogFileName
if (-not (Test-Path $LogDir)) {
    try {
        New-Item -Path $LogDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Warning "Unable to create log folder $LogDir : $($_.Exception.Message)"
    }
}

# Rotates a log when it exceeds the max size, keeping at most $LogMaxFiles files
function Invoke-LogRollover {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return }
    if ((Get-Item $Path).Length -lt $LogMaxSizeBytes) { return }

    # Remove the oldest allowed file, then shift the rest up by one index
    $oldest = "$Path.$($LogMaxFiles - 1)"
    if (Test-Path $oldest) { Remove-Item $oldest -Force -ErrorAction SilentlyContinue }
    for ($i = $LogMaxFiles - 2; $i -ge 1; $i--) {
        $src = "$Path.$i"
        if (Test-Path $src) { Move-Item $src "$Path.$($i + 1)" -Force -ErrorAction SilentlyContinue }
    }
    Move-Item $Path "$Path.1" -Force -ErrorAction SilentlyContinue
}
Invoke-LogRollover -Path $LogFile

# Writes to host (keeping existing behaviour) and appends to the log file
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN')][string]$Level = 'INFO'
    )
    if ($Level -eq 'WARN') {
        Write-Warning $Message
    }
    else {
        Write-Host $Message
    }
    # Out-File throws a terminating error when the file cannot be opened; swallow it so a logging
    # failure can never skip the script's Exit statements (previously caused a false exit 0).
    try {
        "$(Get-Now) [$Level] $Message" | Out-File -FilePath $LogFile -Append -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Unable to write to log file $LogFile : $($_.Exception.Message)"
    }
}

Write-Log "initialize-winget-autoupdate - VERSION 1.2.0"

$ScriptStart = Get-Date
Write-Log "IsSystem: $($CurrentProcessToken.IsSystem)"
Write-Log "IsAdmin: $IsAdmin"
Write-Log "User: $($CurrentProcessToken.Name)"
Write-Log "SessionID: $([System.Diagnostics.Process]::GetCurrentProcess().SessionId)"

if ($IsAdmin) {
    if ($MoveUserLogsToSystemLogDir) {
        Write-Log "Moving user logs from $UserLogDir to $SystemLogDir"
        $UserLogFile = Join-Path $UserLogDir $LogFileName
        $UserLogArchive = Join-Path $SystemLogDir $UserLogArchiveName
        # Oldest rotated file first so the archive stays in chronological order
        $UserLogs = @((@(for ($i = $LogMaxFiles - 1; $i -ge 1; $i--) { "$UserLogFile.$i" }) + $UserLogFile) | Where-Object { Test-Path $_ })
        if ($UserLogs.Count -gt 0) {
            Invoke-LogRollover -Path $UserLogArchive
            foreach ($UserLog in $UserLogs) {
                try {
                    $Content = Get-Content -Path $UserLog -Raw -ErrorAction Stop
                    if ($Content) {
                        $Content | Out-File -FilePath $UserLogArchive -Append -Encoding UTF8 -NoNewline -ErrorAction Stop
                    }
                    Remove-Item -Path $UserLog -Force -ErrorAction Stop
                    Write-Log "Moved user log $UserLog to $UserLogArchive"
                }
                catch {
                    Write-Log "Failed to move user log $UserLog : $($_.Exception.Message)" -Level WARN
                }
            }
        }
        else {
            Write-Log "No user logs found in $UserLogDir"
        }
    }
    else {
        Write-Log "Moving user logs is disabled (MoveUserLogsToSystemLogDir = false)"
    }
}

Write-Log "Check for task Scheduled"
$Task = Get-ScheduledTask -TaskName $WauTaskName -ErrorAction SilentlyContinue
if ($Task) {
    Write-Log "Task Scheduled found"
    if ($Task.State -ne "Disabled") {
        if ($IsAdmin) {
            try {
                $Task | Disable-ScheduledTask -ErrorAction Stop | Out-Null
                Write-Log "Task Scheduled disabled"
            }
            catch {
                Write-Log "Failed to disable Task Scheduled: $($_.Exception.Message)" -Level WARN
            }
        }
        else {
            Write-Log "Not admin - skipping disable of Task Scheduled"
        }
    }
    else {
        Write-Log "Task Scheduled already disabled"
    }
}
else {
    Write-Log "Task Scheduled NOT found"
}

Write-Log "Checking for winget-upgrade.ps1"
$UpgradeScript = $null
foreach ($Candidate in $UpgradeScriptCandidates) {
    if (Test-Path $Candidate) {
        Write-Log "Found: $Candidate"
        if (-not $UpgradeScript) { $UpgradeScript = $Candidate }
    }
    else {
        Write-Log "Not found: $Candidate"
    }
}
if (-not $UpgradeScript) {
    Write-Log "winget-upgrade.ps1 not found in any known location"
    Write-Log "Not Compliant - winget-upgrade.ps1 not found" -Level WARN
    Exit 1
}
Write-Log "winget-upgrade.ps1 found: $UpgradeScript"

Write-Log "Checking for Invisible.vbs"
$InvisibleVbs = $WauInvisibleVbs
if (-not (Test-Path $InvisibleVbs)) {
    $InvisibleVbs = Join-Path $ToolsDir "Invisible.vbs"
    if ($IsAdmin) {
        Write-Log "Invisible.vbs not found in WorkingDir - downloading"
        try {
            if (-not (Test-Path $ToolsDir)) {
                New-Item -Path $ToolsDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Write-Log "Created folder: $ToolsDir"
            }
            Invoke-WebRequest -Uri $InvisibleUrl -OutFile $InvisibleVbs -UseBasicParsing -ErrorAction Stop
            Write-Log "Invisible.vbs downloaded to: $InvisibleVbs"
        }
        catch {
            Write-Log "Failed to download Invisible.vbs: $($_.Exception.Message)"
            Write-Log "Not Compliant - Invisible.vbs not available" -Level WARN
            Exit 1
        }
    }
    else {
        # Users cannot write to C:\Windows, so only an existing copy (placed by a SYSTEM run) can be used
        Write-Log "Invisible.vbs not found in WorkingDir - not admin, checking $InvisibleVbs"
        if (-not (Test-Path $InvisibleVbs)) {
            Write-Log "Not Compliant - Invisible.vbs not available and download requires admin" -Level WARN
            Exit 1
        }
    }
}
Write-Log "Invisible.vbs found: $InvisibleVbs"

try {
    Write-Log "start script with VBS"
    Write-Log "start script $(Get-Now)"
    # Invisible.vbs runs WScript.Arguments(0) as a full command line, so the entire PowerShell
    # invocation must be passed as ONE quoted argument. Using -EncodedCommand (Base64 of the
    # UTF-16LE script call) avoids any inner quotes/spaces, which wscript mis-parses when the
    # script path contains spaces (e.g. "C:\Program Files\...").
    $Inner = "& '$UpgradeScript'"
    $EncodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Inner))
    $PsCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $EncodedCommand"
    $WScriptArgs = "`"$InvisibleVbs`" `"$PsCommand`""
    Write-Log "wscript args: $WScriptArgs"
    Start-Process "$env:windir\System32\wscript.exe" -ArgumentList $WScriptArgs
    Write-Log "end script $(Get-Now)"

    # Verify winget-upgrade.ps1 actually ran by confirming an updates.log was written by THIS run.
    # The launch is async, so poll for a short while to let the hidden run create/update the log.
    $LogUpdated = $false
    $Elapsed = 0
    do {
        foreach ($LogPath in $UpdateLogCandidates) {
            if (Test-Path $LogPath) {
                $LastWrite = (Get-Item $LogPath).LastWriteTime
                if ($LastWrite -ge $ScriptStart) {
                    Write-Log "updates.log written after start: $LogPath ($LastWrite)"
                    $LogUpdated = $true
                    break
                }
                else {
                    Write-Log "updates.log not written after start: $LogPath ($LastWrite)"
                }
            }
            else {
                Write-Log "updates.log not found: $LogPath"
            }
        }
        if (-not $LogUpdated -and $Elapsed -lt $UpdateLogMaxWaitSeconds) {
            Start-Sleep -Seconds $UpdateLogPollSeconds
            $Elapsed += $UpdateLogPollSeconds
        }
    } while (-not $LogUpdated -and $Elapsed -lt $UpdateLogMaxWaitSeconds)

    if (-not $LogUpdated) {
        Write-Log "Not Compliant - no updates.log was written after start" -Level WARN
        Exit 1
    }

    Write-Output "Compliant"
    Exit 0
}
catch {
    Write-Log "Script failed"
    Write-Log "Not Compliant - Script failed" -Level WARN
    Exit 1
} 