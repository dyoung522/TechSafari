#!/bin/bash

ARCHIVE_DAYS="90"
eval ARCHIVE_DIR="~/Maildir_Archive"
eval MAILDIR_DIR="~/Maildir"

# Temporarily disable qmail queueing
chmod +t $HOME

ls -ad ${MAILDIR_DIR}/.[a-z\|A-Z]* |\
while read MAILDIR ; do
    MAILDIR_FILE="${MAILDIR##*/}"
    ARCHIVE_FILE="${ARCHIVE_DIR}/$(echo "${MAILDIR_FILE}" | sed -e 's/^.//' -e 's/ /_/g').$(date +%Y%m%d).tar"

    # Skip any directories that don't have a cur directory (not a Maildir)
    [[ ! -d "${MAILDIR}/cur" ]] && continue

    # We really only need one of the two checks below, but I left it as-is for
    # versatility.  The .noarchive has greater weight, so a folder can be
    # disabled even if it contains the .archive file.

    # Only process directories that have the .archive file
    [[ ! -f "${MAILDIR}/.archive" ]] && continue

    # Skip directories that have the .noarchive file
    [[ -f "${MAILDIR}/.noarchive" ]] && continue

    # CD into the directory before archive, or skip it if we fail
    cd "${MAILDIR}" || continue

    echo "Archiving ${MAILDIR}"

    find cur -daystart -mtime +${ARCHIVE_DAYS} -type f -exec tar --remove-files -rpsf ${ARCHIVE_FILE} {} \;

    # If an archive was created, compress it now
    [[ -f ${ARCHIVE_FILE} ]] && gzip -9 ${ARCHIVE_FILE} &
done

# Archive procmail log
if [[ -s procmail.log ]] ; then
    mv procmail.log $ARCHIVE_DIR/procmail.$(date +%Y%m%d).log
    touch procmail.log

    gzip -9 $ARCHIVE_DIR/procmail.*.log &
fi

# Sort sent mail
if [[ -x /usr/local/bin/mail2qtr.pl ]] ; then
    /usr/local/bin/mail2qtr.pl ".Sent Mail"

    # Create the .noarchive semaphore file in any newly created .Sent folders
    for DIR in ~/Maildir/.Sent\ Mail.????.Q? ; do 
        touch "$DIR/.noarchive"
    done
fi

# Delete Mailer-Daemon files
find $MAILDIR_DIR/Mailer-Daemon -type f -mtime +$ARCHIVE_DAYS -exec rm -f {} \;

# Re-enable qmail queueing
chmod -t $HOME
