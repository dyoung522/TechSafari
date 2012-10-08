#!/bin/bash

die() {
    echo $*
    exit 1
}

LOGPAT="logfile.txt.*.gz"
LOGDIR="/var/log/rhino2"
LOGBASE="$LOGDIR/archive"

cd $LOGDIR || die "Unable to change to $LOGDIR"

# Exit silently if there are no files matching our pattern
ls $LOGPAT >/dev/null 2>&1 || exit

[[ -d $LOGBASE ]] || mkdir $LOGBASE || die "Unable to create $LOGBASE"

for LOGFILE in $LOGPAT ; do
    # Parse the date out of the filename
    LOGDATE=${LOGFILE#logfile.txt.}
    LOGYEAR=${LOGDATE:0:4}
    LOGMON=${LOGDATE:4:2}

    [[ -d $LOGBASE/$LOGYEAR ]] || mkdir $LOGBASE/$LOGYEAR || die "Unable to create $LOGBASE/$LOGYEAR"
    [[ -d $LOGBASE/$LOGYEAR/$LOGMON ]] || mkdir $LOGBASE/$LOGYEAR/$LOGMON || die "Unable to create $LOGBASE/$LOGYEAR/$LOGMON"
    mv $LOGFILE $LOGBASE/$LOGYEAR/$LOGMON || die "Unable to mv $LOGFILE to $LOGBASE/$LOGYEAR/$LOGMON"
done
