#!/bin/bash
#Script to config snmp on a Mac

mv /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.old
printf '#Allow read-access with the following SNMP Community String:
rocommunity public

launchctl unload /System/Library/LaunchDaemons/org.net-snmp.snmpd.plist
launchctl load /System/Library/LaunchDaemons/org.net-snmp.snmpd.plist
exit
