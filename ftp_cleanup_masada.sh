#!/bin/bash

FTPROOT="/data/ftproot/masada"
KEEPTIME=30

VERBOSE=1
[[ "$1" = "-q" ]] && VERBOSE=0

die() {
    echo "$*"
    exit 1
}

print() {
    [[ $VERBOSE -eq 0 ]] && return
    echo "$*"
}

cd $FTPROOT

for DIR in * ; do
    print "Processing $DIR"

    # Only process directories at this point
    [[ -d $DIR ]] || continue

    cd $DIR

    # If a per-directory skip file is found, skip this dir
    if [[ -f .cleanup_skip ]] ; then
        print "  Directory skipped per rule"
    else
        print "  Deleting files older than $KEEPTIME days"

        # Find and delete files that meet our criteria
        find . -type f -mtime +$KEEPTIME -not -wholename "./.*" |\
        while read RFILE ; do
            FILE=${RFILE##*/}
            # Skip files listed in the .ftpexception file
            if [[ -f .cleanup_exception ]] ; then
                if grep -q "$FILE" .cleanup_exception ; then
                    print "    $FILE skipped per rule"
                    continue
                fi
            fi

            # If we made it here, delete the file
            print "    Deleting $FILE"
            rm -f "$RFILE"
        done
    fi

    cd $FTPROOT
done
