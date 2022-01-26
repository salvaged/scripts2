#!/bin/bash

killall Messages
echo "$USER"
cd /Users/$USER/Library/Messages/Attachments/
rm -rf *
open -a Messages.app
exit
