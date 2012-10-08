#!/usr/bin/env bash

myexit() {
    echo $*
    exit
}

TRANSDIR="/var/log/rhino2/transactions"
if [[ -d $TRANSDIR ]] ; then
    cd $TRANSDIR
else
    myexit "$TRANSDIR does not exist, exiting"
fi

TESTTRAN='0011070085208263'

for FILE in trans_*.txt ; do
    # delete test transactions before archiving
    grep -qs $TESTTRAN $FILE
    if [[ $? -eq 0 ]] ; then
        rm $FILE || myexit "Unable to delete the test file $FILE"
        continue
    fi

    # Get the date of the file in EPOCH time
    FILEDATE=$(stat -c %Y $FILE)

    # Get the date seven days ago in EPOCH time
    KEEPDATE=$(( $(date +'%s') - (60 * 60 * 24 * 7) ))

    # Skip any files from the last 7 days
    [[ $FILEDATE -ge $KEEPDATE ]] && continue

    # Build our tar filename using the file's modification date
    TARFILE="$(date -d "1970-01-01 ${FILEDATE} sec" "+%Y%m").tar"
    if [[ -f $TARFILE ]] ; then
        # If the tar file already exists, update it
        tar -r --remove-files -f $TARFILE $FILE
    else
        # If the tar file does not exist, create it
        tar -c --remove-files -f $TARFILE $FILE
    fi
    # Count the number of files we've processed
    ((COUNT++))
done

if [[ -n "$COUNT" ]] ; then
    MESSAGE="$0 completed on $(date).  We processed $COUNT file(s) today"
else
    MESSAGE="$0 completed on $(date).  No files were processed today"
fi

echo $MESSAGE | /bin/mail -s "$(hostname -s) Daily Transaction Archive" support@techsafari.com
