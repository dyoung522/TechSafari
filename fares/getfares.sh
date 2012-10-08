#!/bin/bash

#[[ $UID -ne 0 ]] && echo "Please run this program as root." && exit 1

error() {
    echo "$*"
    exit 1
}

notify() {
    echo "$*"
    echo "$*" | mail -s "**Problem** Weekly FARES" $EMAIL_NOTIFY
    exit 1
}

DATE="${1:-$(date +%Y%m%d)}"
SAMP="${2:-Deeds}"

EMAIL_NOTIFY="mlocke@market-tech.com,lavila@market-tech.com,oncall@techsafari.com"

FTP_SITE="63.146.49.227"
FTP_USER="NorthAmInfoCorp"
FTP_PASS="winpace"
FTP_RDIR="${DATE}${SAMP}"
FTP_LDIR="${DATE}/ZIPS"
INSTALL_DIR="/fset36/MTC/FARES_WEEKLY/IN"

cd $INSTALL_DIR || error "Unable to cd to \"$INSTALL_DIR\""

[[ ! -d $FTP_LDIR ]] && mkdir -p $FTP_LDIR

ncftpls -t 30 -u $FTP_USER -p $FTP_PASS ftp://$FTP_SITE/$FTP_RDIR >/dev/null 2>&1 || \
    error "The directory $FTP_RDIR does not exist on the remote FTP site."

ncftpget -u $FTP_USER -p $FTP_PASS $FTP_SITE $FTP_LDIR "$FTP_RDIR/*" || \
    notify "An error occurred during Weekly FARES download processing"

chgrp -R prod $DATE
chmod -R g+rw $DATE

cd $DATE

/opt/mtcsbin/pkgfares.sh || \
    error "An error occurred during Weekly FARES packaging"

rsync -ae ssh ../$DATE tuser@db07.techsafari.com:/data/in/court/court_weekly/ || \
    error "An error occurred during transfer of Weekly FARES to NS system"

ssh tuser@db07.techsafari.com ln -nsf /data/in/court/court_weekly/${DATE} /data/in/court/court_weekly/current

echo "Weekly FARES Load is complete ($(date))" | mail -s "Weekly FARES Successful" $EMAIL_NOTIFY
exit 0
