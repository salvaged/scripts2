#################################
# Setup New PC                 ##
# Improve SSD Drive performance##
#################################

Stop-Service -Force -Name "SysMain"; Set-Service -Name "SysMain" -StartupType Disabled
Set-ItemProperty -Force -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "PrefetchParameters" -Value 0
Set-ItemProperty -Force -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "EnablePrefetcher" -Value 0
New-ItemProperty -Force -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters" -Name "EnableSuperfetch" -Value 0

rm C:\Windows\Prefetch\*

#######################################
#Disable Delivery Optimization peering# ####################################### 
$RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
$Name    = "DODownloadMode"
$Value   = 0   # 0 = HTTP only (disable peering)

# Create the key if it doesn't exist
if (!(Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}
New-ItemProperty -Path $RegPath -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
Write-Host "Delivery Optimization peering has been DISABLED." -ForegroundColor Green
Restart-Service -Name DoSvc -Force -ErrorAction SilentlyContinue
Write-Host "DoSvc service restarted."

######################
#Remove Unwanted apps#
######################

Get-AppxPackage *Spotify* | Remove-AppxPackage -AllUsers
Get-AppPackage *MicrosoftBing* | Remove-AppPackage -AllUsers
Get-AppxPackage -AllUsers Disney.37853FC22B2CE | Remove-AppxPackage
Get-AppxPackage -AllUsers *xbox* | Remove-AppxPackage -AllUsers
Set-ItemProperty -Path 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'AppCaptureEnabled' -Value 0
Set-ItemProperty -Path 'Microsoft.PowerShell.Core\Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\GameDVR' -Name 'HistoricalCaptureEnabled' -Value 0

shutdown.exe /r /t 120 /c "System will reboot in 2 minutes. Please save your work."
