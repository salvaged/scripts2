#!/bin/bash
#Purpose is to remove the Messages from iMessage on your mac and remove attachments, can be run using a cronjob

killall Messages
echo "$USER"
cd /Users/$USER/Library/Messages/Attachments/
rm -rf *
cd /Users/$USER/Library/Messages/
rm -rf chat.db
pause 5
open -a Messages.app
exit
