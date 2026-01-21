#Powershell command to check file size from Folder/SubFolder

Get-ChildItem E:\MSSQL\Backups\ -recurse | Select-Object Name,@{Name="MegaBytes";Expression={"{0:F2}" -f ($
_.length/1MB)}}

Get-ChildItem E:\MSSQL\Backups\ -recurse | Select-Object Name,@{Name=“GigaBytes";Expression={"{0:F2}" -f ($_.length/1GB)}}
Get-ChildItem D:\Hyper-V\ -recurse | Select-Object Name,@{Name=“GigaBytes";Expression={"{0:F2}" -f ($_.length/1GB)}}
