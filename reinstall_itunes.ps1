#Requires -RunAsAdministrator

# iTunes Full Reinstall Script
# Must be run as Administrator

$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== iTunes Reinstall Script ===" -ForegroundColor Cyan
Write-Host "This will remove all Apple/iTunes components and reinstall iTunes." -ForegroundColor Yellow
Write-Host ""

# ── Step 1: Kill running Apple processes ──────────────────────────────────────
Write-Host "[1/5] Stopping Apple processes..." -ForegroundColor Green
$appleProcesses = @("iTunes", "AppleMobileDeviceService", "mDNSResponder", "ApplePhotoStreams",
                    "iTunesHelper", "AppleSyncNotifier", "Bonjour Service")
foreach ($proc in $appleProcesses) {
    Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

# ── Step 2: Stop and disable Apple services ───────────────────────────────────
Write-Host "[2/5] Stopping Apple services..." -ForegroundColor Green
$appleServices = @("Apple Mobile Device Service", "Bonjour Service", "iPod Service")
foreach ($svc in $appleServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    }
}

# ── Step 3: Uninstall via Programs list (covers both MSI and EXE installs) ────
Write-Host "[3/5] Uninstalling iTunes and Apple components..." -ForegroundColor Green

# Products to remove — order matters (iTunes first, then dependencies)
$appleProducts = @(
    "iTunes",
    "Apple Mobile Device Support",
    "Apple Application Support (64-bit)",
    "Apple Application Support (32-bit)",
    "Apple Software Update",
    "Bonjour",
    "iCloud",
    "Apple Devices",
    "MobileMe",
    "iPod"
)

# Search both 32-bit and 64-bit uninstall registry keys
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($productName in $appleProducts) {
    foreach ($regPath in $regPaths) {
        $entries = Get-ItemProperty $regPath -ErrorAction SilentlyContinue |
                   Where-Object { $_.DisplayName -like "*$productName*" }
        foreach ($entry in $entries) {
            Write-Host "  Removing: $($entry.DisplayName)" -ForegroundColor Gray
            $uninstallString = $entry.UninstallString
            if ($uninstallString) {
                if ($uninstallString -match "msiexec") {
                    # MSI-based installer
                    $guid = ($uninstallString -replace '.*(\{[A-Z0-9\-]+\}).*', '$1')
                    Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn /norestart" -Wait -ErrorAction SilentlyContinue
                } else {
                    # EXE-based installer — try common silent flags
                    $exePath = $uninstallString -replace '"', '' -split ' ' | Select-Object -First 1
                    if (Test-Path $exePath) {
                        Start-Process $exePath -ArgumentList "/quiet /norestart" -Wait -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}

# Also try removing via Windows Package Manager (Microsoft Store version)
Write-Host "  Checking Microsoft Store version..." -ForegroundColor Gray
Get-AppxPackage -Name "AppleInc.iTunes" -AllUsers -ErrorAction SilentlyContinue |
    Remove-AppxPackage -ErrorAction SilentlyContinue

Start-Sleep -Seconds 3

# ── Step 4: Clean up leftover files and registry ──────────────────────────────
Write-Host "[4/5] Cleaning up leftover files..." -ForegroundColor Green

$foldersToRemove = @(
    "$env:ProgramFiles\iTunes",
    "$env:ProgramFiles\Common Files\Apple",
    "${env:ProgramFiles(x86)}\iTunes",
    "${env:ProgramFiles(x86)}\Common Files\Apple",
    "$env:ProgramData\Apple Computer",
    "$env:ProgramData\Apple",
    "$env:LOCALAPPDATA\Apple Computer",
    "$env:APPDATA\Apple Computer"
)
foreach ($folder in $foldersToRemove) {
    if (Test-Path $folder) {
        Write-Host "  Removing: $folder" -ForegroundColor Gray
        Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Remove Apple services that may be left behind
$servicesToRemove = @("Apple Mobile Device Service", "Bonjour", "iPod Service")
foreach ($svc in $servicesToRemove) {
    if (Get-Service $svc -ErrorAction SilentlyContinue) {
        sc.exe delete $svc | Out-Null
    }
}

# ── Step 5: Download and install fresh iTunes ─────────────────────────────────
Write-Host "[5/5] Downloading iTunes installer..." -ForegroundColor Green

$installerPath = "$env:TEMP\iTunesSetup.exe"

# Apple's official direct download for 64-bit iTunes Windows installer
$downloadUrl = "https://www.apple.com/itunes/download/win64"

try {
    Write-Host "  Downloading from Apple (this may take a moment)..." -ForegroundColor Gray
    $webClient = New-Object System.Net.WebClient
    $webClient.Headers.Add("User-Agent", "Mozilla/5.0")
    $webClient.DownloadFile($downloadUrl, $installerPath)

    if (Test-Path $installerPath) {
        $fileSize = (Get-Item $installerPath).Length
        if ($fileSize -gt 1MB) {
            Write-Host "  Download complete ($([math]::Round($fileSize/1MB, 1)) MB). Installing..." -ForegroundColor Gray
            Start-Process $installerPath -ArgumentList "/quiet /norestart" -Wait
            Write-Host ""
            Write-Host "iTunes installation complete!" -ForegroundColor Green
        } else {
            Write-Host "  Download may have failed (file too small). Opening Apple's download page..." -ForegroundColor Yellow
            Start-Process "https://www.apple.com/itunes/"
        }
    }
} catch {
    Write-Host "  Could not auto-download. Opening Apple's iTunes download page in your browser." -ForegroundColor Yellow
    Start-Process "https://www.apple.com/itunes/"
}

# Cleanup installer
Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "If iTunes does not appear, try rebooting and launching it from the Start Menu." -ForegroundColor Yellow
Read-Host "Press Enter to exit"
