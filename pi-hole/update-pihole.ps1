<#
.SYNOPSIS
  Weekly Pi-hole (Docker Desktop) updater for Windows, scheduled with Task Scheduler.

.DESCRIPTION
  Run it ON the Windows PC where Pi-hole runs. "Update" = pull the newest
  pihole/pihole image and recreate the container if the image changed. Config is
  backed up first. No admin rights needed: the task runs as you, only while
  you're logged in, and catches up at the next opportunity if the PC was off.
  Docker Desktop must be running.

.PARAMETER Action
  Install  - copy this script to %LOCALAPPDATA%\PiholeUpdate and register the weekly task
  Remove   - unregister the task and delete the installed copy
  Run      - update now (this is what the task runs). Default.

.PARAMETER ProjectDir
  Folder containing docker-compose.yml. Default: %USERPROFILE%\pihole

.PARAMETER Day
  Day of week for the scheduled run. Default: Sunday.

.PARAMETER Time
  24h HH:mm local time. Default: 05:00.

.EXAMPLE
  .\update-pihole.ps1 -Action Install
  .\update-pihole.ps1 -Action Install -ProjectDir D:\pihole -Day Wednesday -Time 04:30
  .\update-pihole.ps1 -Action Run
#>
[CmdletBinding()]
param(
  [ValidateSet('Run', 'Install', 'Remove')]
  [string]$Action = 'Run',

  [string]$ProjectDir = (Join-Path $env:USERPROFILE 'pihole'),

  [ValidateSet('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday')]
  [string]$Day = 'Sunday',

  [ValidatePattern('^([01][0-9]|2[0-3]):[0-5][0-9]$')]
  [string]$Time = '05:00'
)

$ErrorActionPreference = 'Stop'

$TaskName    = 'Pi-hole Weekly Update'
$Container   = 'pihole'
$InstallDir  = Join-Path $env:LOCALAPPDATA 'PiholeUpdate'
$InstalledPs = Join-Path $InstallDir 'update-pihole.ps1'
$LogFile     = Join-Path $InstallDir 'update.log'

function Write-Log {
  param([string]$Message)
  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  if (-not (Test-Path -LiteralPath $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir | Out-Null }
  Add-Content -LiteralPath $LogFile -Value $line
  Write-Host $line
}

# Run a native command, log its output, throw on a non-zero exit code.
# (Windows PowerShell 5.1 turns native stderr into errors under -Stop, so relax it here.)
function Invoke-Native {
  param([string]$Exe, [string[]]$ArgList, [switch]$AllowFail)
  $ErrorActionPreference = 'Continue'
  $out = & $Exe @ArgList 2>&1 | ForEach-Object { "$_" }
  foreach ($l in $out) { if ($l) { Write-Log "    $l" } }
  if ($LASTEXITCODE -ne 0 -and -not $AllowFail) { throw "$Exe $($ArgList -join ' ') failed (exit $LASTEXITCODE)" }
  return ($out -join "`n")
}

function Get-Status {
  $ErrorActionPreference = 'Continue'
  $s = & docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' $Container 2>$null
  if ($LASTEXITCODE -ne 0) { return '' }
  return "$s".Trim()
}

function Get-ImageId {
  $ErrorActionPreference = 'Continue'
  $i = & docker inspect -f '{{.Image}}' $Container 2>$null
  if ($LASTEXITCODE -ne 0) { return 'none' }
  return "$i".Trim()
}

function Invoke-Update {
  Write-Log "=== Pi-hole update starting (dir: $ProjectDir) ==="
  try {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'docker CLI not found' }
    $ErrorActionPreference = 'Continue'
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop is not running; skipping this run' }
    $ErrorActionPreference = 'Stop'

    $compose = @('docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml') |
      Where-Object { Test-Path -LiteralPath (Join-Path $ProjectDir $_) } | Select-Object -First 1
    if (-not $compose) { throw "No compose file in $ProjectDir" }
    Set-Location -LiteralPath $ProjectDir

    $config = Join-Path $ProjectDir 'etc-pihole'
    if (Test-Path -LiteralPath $config) {
      $backups = Join-Path $ProjectDir 'backups'
      New-Item -ItemType Directory -Force -Path $backups | Out-Null
      $zip = Join-Path $backups ('etc-pihole-{0}.zip' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
      try {
        Compress-Archive -Path $config -DestinationPath $zip -CompressionLevel Optimal
        Write-Log "Config backup: $zip"
        Get-ChildItem -LiteralPath $backups -Filter 'etc-pihole-*.zip' |
          Sort-Object LastWriteTime -Descending | Select-Object -Skip 4 | Remove-Item -Force
      } catch {
        Write-Log "WARNING: config backup failed ($($_.Exception.Message)); continuing"
      }
    }

    $before = Get-ImageId
    Invoke-Native docker @('compose', 'pull') | Out-Null
    Invoke-Native docker @('compose', 'up', '-d') | Out-Null
    Invoke-Native docker @('image', 'prune', '-f') -AllowFail | Out-Null
    $after = Get-ImageId

    $status = ''
    for ($i = 0; $i -lt 45; $i++) {
      $status = Get-Status
      if ($status -eq 'healthy') { break }
      Start-Sleep -Seconds 2
    }
    if ($status -ne 'healthy') {
      Write-Log "Container status is '$status'. Last logs:"
      Invoke-Native docker @('logs', '--tail', '30', $Container) -AllowFail | Out-Null
      throw "Container is not healthy after update. Restore from the newest zip in $ProjectDir\backups if needed."
    }

    if ($before -eq $after) { Write-Log 'Already on the latest image; nothing changed.' }
    else { Write-Log 'Updated to a newer image.' }
    Invoke-Native docker @('exec', $Container, 'pihole', '-v') -AllowFail | Out-Null
    Write-Log '=== Done ==='
  }
  catch {
    Write-Log "FAILED: $($_.Exception.Message)"
    exit 1
  }
}

function Install-Task {
  if (-not (Test-Path -LiteralPath $ProjectDir)) { throw "Directory not found: $ProjectDir (use -ProjectDir)" }
  $ProjectDirFull = (Resolve-Path -LiteralPath $ProjectDir).Path

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  if ((Resolve-Path -LiteralPath $PSCommandPath).Path -ne $InstalledPs) {
    Copy-Item -LiteralPath $PSCommandPath -Destination $InstalledPs -Force
  }

  $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Action Run -ProjectDir "{1}"' -f $InstalledPs, $ProjectDirFull
  $taskAction    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
  $taskTrigger   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At $Time
  $taskSettings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
                     -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew `
                     -ExecutionTimeLimit (New-TimeSpan -Hours 1)
  $taskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                     -LogonType Interactive -RunLevel Limited

  Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger `
    -Settings $taskSettings -Principal $taskPrincipal -Force | Out-Null

  Write-Host "Installed weekly update: every $Day at $Time (runs as $env:USERNAME while logged in)"
  Write-Host "  Task     : $TaskName (Task Scheduler)"
  Write-Host "  Script   : $InstalledPs"
  Write-Host "  Log      : $LogFile"
  Write-Host "  Test now : Start-ScheduledTask -TaskName '$TaskName'"
}

function Remove-Task {
  if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
  }
  Remove-Item -LiteralPath $InstalledPs -Force -ErrorAction SilentlyContinue
  Write-Host "Removed scheduled task and installed script. Log kept: $LogFile"
}

switch ($Action) {
  'Run'     { Invoke-Update }
  'Install' { Install-Task }
  'Remove'  { Remove-Task }
}
