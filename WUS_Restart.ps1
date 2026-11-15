<#
    WUS_Restart.ps1
    Stops the Windows Update services, renames SoftwareDistribution and catroot2,
    then resets the services. Any error is written to a log file on the Desktop
    of the user currently logged on. If nothing fails, no log file is created.
    Run from an elevated PowerShell (or as SYSTEM via your management tool).
#>

$ErrorActionPreference = 'Stop'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$errors = New-Object System.Collections.Generic.List[string]

function Get-LoggedOnUserDesktop {
    try {
        # Console user first, then fall back to the owner of explorer.exe (covers RDP sessions)
        $user = (Get-CimInstance Win32_ComputerSystem).UserName
        if (-not $user) {
            $exp = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Select-Object -First 1
            if ($exp) {
                $o = Invoke-CimMethod -InputObject $exp -MethodName GetOwner
                if ($o.User) { $user = "$($o.Domain)\$($o.User)" }
            }
        }
        if ($user) {
            $sid = (New-Object Security.Principal.NTAccount($user)).Translate([Security.Principal.SecurityIdentifier]).Value
            # Shell Folders returns the resolved path, including OneDrive-redirected desktops
            $key = "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders"
            $d = (Get-ItemProperty $key -Name Desktop -ErrorAction Stop).Desktop
            if ($d -and (Test-Path $d)) { return $d }
            $lp = (Get-CimInstance Win32_UserProfile | Where-Object SID -eq $sid).LocalPath
            if ($lp -and (Test-Path "$lp\Desktop")) { return "$lp\Desktop" }
        }
    } catch { }
    $fallback = [Environment]::GetFolderPath('Desktop')
    if (-not $fallback -or $fallback -match 'systemprofile') { $fallback = Join-Path $env:PUBLIC 'Desktop' }
    return $fallback
}

function Invoke-Step {
    param([string]$Name, [scriptblock]$Action)
    try {
        & $Action
        Write-Host "OK    $Name"
    } catch {
        $msg = "$Name -> $($_.Exception.Message)"
        $errors.Add($msg)
        Write-Host "FAIL  $msg" -ForegroundColor Red
    }
}

function Write-ErrorLog {
    $desktop = Get-LoggedOnUserDesktop
    $logFile = Join-Path $desktop "WU_Reset_Errors_$stamp.txt"
    $header = @(
        "Windows Update reset errors"
        "Computer : $env:COMPUTERNAME"
        "Run as   : $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
        "Time     : $(Get-Date)"
        "-----------------------------------------"
    )
    ($header + $errors) | Out-File -FilePath $logFile -Encoding utf8
    Write-Host "Errors written to $logFile" -ForegroundColor Yellow
}

# Must be elevated
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $errors.Add('Script was not run as Administrator. Nothing was changed.')
    Write-ErrorLog
    exit 1
}

$services = 'wuauserv','cryptSvc','bits','msiserver'
$folders  = 'C:\Windows\SoftwareDistribution','C:\Windows\System32\catroot2'

# 1. Stop services (-Force also stops dependent services)
foreach ($svc in $services) {
    Invoke-Step "Stop $svc" {
        $s = Get-Service -Name $svc
        if ($s.Status -ne 'Stopped') {
            Stop-Service -Name $svc -Force
            $s.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
        }
    }
}

# 2. Rename folders. A timestamp suffix avoids failing if a previous .old copy exists.
foreach ($folder in $folders) {
    Invoke-Step "Rename $folder" {
        if (Test-Path $folder) {
            Rename-Item -Path $folder -NewName ("{0}.old-{1}" -f (Split-Path $folder -Leaf), $stamp)
        }
    }
}

# 3. Start services again, even if an earlier step failed, so they are not left stopped
foreach ($svc in $services) {
    Invoke-Step "Start $svc" {
        $s = Get-Service -Name $svc
        if ($s.Status -ne 'Running') {
            Start-Service -Name $svc
            $s.WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
        }
    }
}

if ($errors.Count -gt 0) {
    Write-ErrorLog
    exit 1
}

Write-Host 'Completed with no errors.' -ForegroundColor Green
exit 0
