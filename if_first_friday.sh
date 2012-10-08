#!/bin/bash

# Get today's day
TODAY=$(/bin/date +%d)
TODAY=${TODAY#0}    # Strip off any leading 0's

# Get 1st Friday of the Month day
MATCH=$(/usr/bin/cal | awk {'print $6'} | xargs | /usr/bin/cut -d" " -f2)

#See if today matches the 1st Friday of the month, if so exit success
[ "$TODAY" -eq "$MATCH" ] && exit 0

# if not, exit with status fail
exit 1
