#PS Entry Script

# Add local admin/temp fix
Add-LocalGroupMember -Group "Administrators" -Member "username"

# Trigger Windows Update scan
cmd.exe /c "Wuauclt /detectnow"

# Add content DNS suffix
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "Searchlist" -value "DOMAINNAME.com"
cmd.exe /c "ipconfig /registerdns"

# Enable WINRM, WMI and SNMP
netsh advfirewall firewall add rule name="Windows Remote Management (HTTPS-In)" dir=in action=allow protocol=TCP localport=5986
netsh advfirewall firewall add rule name="Windows Remote Management (HTTP-In)" dir=in action=allow protocol=TCP localport=5985
netsh advfirewall firewall set rule group="Windows Management Instrumentation (WMI)" new enable="Yes"
netsh advfirewall firewall set rule group="Windows Remote Management" new enable="Yes"
Get-WindowsFeature SNMP-Service,SNMP-WMI-Provider | Install-WindowsFeature -ErrorAction SilentlyContinue

# Install RDS role
Install-WindowsFeature –Name RDS-RD-Server –IncludeAllSubFeature 

# Set RDS licensing
$obj = Get-WmiObject -namespace "Root/CIMV2/TerminalServices" Win32_TerminalServiceSetting
$obj.ChangeMode("4")
$obj.SetSpecifiedLicenseServerList("servername.com")

# Install RSAT
Install-WindowsFeature -IncludeAllSubFeature RSAT
