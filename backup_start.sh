#!/bin/bash

usage() {
    echo -e "$0 <backup_list>"
    exit 1
}

die() {
    echo -e $*
    exit 1
}

calcsize() {
    SIZE=0
    for FILE in $* ; do
        ((SIZE += $(du -ck $FILE | tail -1 | cut -f1)))
    done
    echo $SIZE
}

FILELIST=$1
SLEEP=30
BPBACKUP="/usr/openv/netbackup/bin/bpbackup"
LOGFILE="$PWD/$(hostname -s)_backup.$(date +%Y%m%d).log"

[[ $UID -ne 0 ]] && die "Must run as root"
[[ -x "$BPBACKUP" ]] || die "$BPBACKUP does not exist or is not executable!"
[[ -z "$FILELIST" ]] && usage
[[ -f "$FILELIST" ]] || die "$FILELIST does not exist"
[[ -f "$LOGFILE" ]] && mv $LOGFILE ${LOGFILE}.$$

LINE=0
for LINE in $(sort -u $FILELIST | egrep -v '^[ ]*#') ; do
    (( LINES++ ))
    if [[ ! -e "$LINE" ]] ; then
        echo "Error in $FILELIST: (Line $LINES) $LINE does not exist"
        ERROR=1
    fi
done
[[ $ERROR -gt 0 ]] && exit 1

echo -e "\nGood, all ${LINE} entries are valid.\n"
du -shc $(egrep -v '^[ ]*#' $FILELIST)
echo -en "\nPress CTRL-C now if you wish to abort.  Waiting $SLEEP seconds..." && sleep $SLEEP
echo

echo -e "Logging to ${LOGFILE}\n"

LINE=0
egrep -v '^[ ]*#' $FILELIST |\
while read LINE ; do
    (( LINES++ ))
    BACKUPSIZE=$(calcsize $LINE)
    echo -en "Backing up $BACKUPSIZE KB in $LINE... "
    $BPBACKUP -w -L $LOGFILE "${LINE}"
    if [[ $? -eq 0 ]] ; then
        echo "OK"
    else
        echo "ERROR at line $LINES!"
        exit 1
    fi
done

exit 0
