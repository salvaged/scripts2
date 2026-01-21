#RLM Check Script for PRTG

#!/bin/bash

#check if rlm is running
systemctl is-active --quiet rlm
ecode=$?
if [ $ecode != '0' ]; then
  echo "1:$ecode:down"
  exit 1
else
  echo "0:$?:OK"
  exit 0
fi
