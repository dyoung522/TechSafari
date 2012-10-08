#!/bin/bash

[[ $UID -ne 0 ]] && echo "Please run this program as root." && exit 1

error() {
    echo "$*"
    echo "$*" | mail -s "**Problem** Weekly BANKRUPTCY" $EMAIL_NOTIFY
    exit 1
}

# Files get transferred on Monday, but have Sunday's date.
DATE="${1:-$(date -d '-1 day' +%Y%m%d)}"
EMAIL_NOTIFY="mlocke@market-tech.com,lavila@market-tech.com,oncall@techsafari.com"

FTP_SITE="eftplso.acxiom.com"
FTP_USER="USER"
FTP_PASS="PASSWORD"

FTP_DATE="${DATE:4:4}${DATE:0:4}"
FTP_RDIR="masada_out_${FTP_DATE}.txt"
FTP_LDIR="${DATE}"
INSTALL_DIR="/fset36/MTC/BANKRUPTCY/WEEKLY/IN"

cd $INSTALL_DIR || error "Unable to cd to $INSTALL_DIR"

[[ ! -d $FTP_LDIR ]] && mkdir -p $FTP_LDIR

#if [[ -z "$(/usr/local/bin/ncftpls -u $FTP_USER -p $FTP_PASS ftp://$FTP_SITE/$FTP_RDIR)" ]] ; then
#    echo "$FTP_RDIR does not exist on $FTP_SITE, please try again later or try a different date"
#    exit 1
#fi

echo "Downloading bankruptcy file..."
/usr/local/bin/ncftpget -R -u $FTP_USER -p $FTP_PASS $FTP_SITE $FTP_LDIR $FTP_RDIR || \
    error "An error occurred during Weekly BANKRUPTCY download processing"

chown -R mlocke:prod $DATE

echo "Weekly BANKRUPTCY transfer for file $FTP_RDIR is complete ($(date))" | mail -s "Weekly Bankruptcy Good" $EMAIL_NOTIFY

echo "Transfering file to NS system..."
su - tuser -c "scp -rp ${INSTALL_DIR}/${DATE}/${FTP_RDIR} db07.techsafari.com:/data/in/bk/bk_weekly/" ||\
    error "Failed to transfer $FTP_RDIR to NS system"

exit 0
