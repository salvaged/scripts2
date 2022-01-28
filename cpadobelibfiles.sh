#!/bin/bash
#Copy's the Creative Cloud Library files from local user to users OneDrive account, you can use box or dropbox but this was for OneDrive

echo "$USER"
cd /Users/$USER/
rsync -abu /Users/$USER/Library/Application\ Support/Adobe/Creative\ Cloud\ Libraries/* /Users/$USER/OneDrive\ -\ Microsoft/CCLibrary 

echo copy succeeded
exit 0
