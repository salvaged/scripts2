#PS Command Check Free Space on Drives

Get-WmiObject Win32_logicaldisk |Select-Object DeviceID,@{L="FreeSpacePercentage";E={100*($_.FreeSpace/$_.
Size)}},FreeSpace,Size

#Cd to dir and run this to get the file size in GB and sorted 
gci -r | sort -descending -property length | select -first 10 name, @{Name="Gigabytes";Expression={[Math]::round($_.length / 1GB, 2)}}

gci -r|sort -descending -property length | select -first 10 name, @{Name="Gigabytes";Expression={[Math]::round($_.length / 1GB, 2)}}
