#!/bin/bash
#
# This script will check your existing Maildirs for valid SEMEPHORE files
# used by the archive_mail.sh script and report the current status.
#
# Optionally, you can have it create the files for you by including
# either -A (create a .archive files) or -N (create a .noarchive files)
# on the command line.  USE WITH CAUTION!

die() {
    echo $*
    exit 1
}

# /Where our maildir is located.  Bomb out if we can't find it.
eval MAILDIR_DIR="~/Maildir"
[[ -d "$MAILDIR_DIR" ]] || die "Unable to locate your Maildir directory"

ls -ad "${MAILDIR_DIR}"/.[a-z\|A-Z]* |\
while read MAILDIR ; do
    printf "%-75s" "$MAILDIR "

    if [[ ! -d "${MAILDIR}/cur" ]] ; then
        echo "Not a maildir directory, skipping"
        continue
    fi

    if [[ -f "${MAILDIR}/.archive" ]] ; then
        echo -n "Archived "
    fi

    if [[ -f "${MAILDIR}/.noarchive" ]] ; then
        echo -n "Skipped "
    fi

    if [[ ! -f "${MAILDIR}/.archive" ]] ; then
        if [[ ! -f "${MAILDIR}/.noarchive" ]] ; then
            echo -n "NO SEMEPHORES FOUND "
            if [[ "$1" == "-A" ]] ; then
                echo -n "(Creating .archive)"
                touch "${MAILDIR}/".archive
            fi
            if [[ "$1" == "-N" ]] ; then
                echo -n "(Creating .noarchive)"
                touch "${MAILDIR}/".noarchive
            fi
        fi
    fi

    echo
done

