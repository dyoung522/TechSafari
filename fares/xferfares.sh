#!/bin/bash

# July 10, 2007 - changed it so data now loads to pluto, not mtc01 - ejg

LOAD_DIR="LOAD"

RDIR="$(date +%Y%m)"
[[ -n "$1" ]] && RDIR="$1"

echo "Using the directory $RDIR... ^C now if this is not correct and provide the correct information on the command line"
sleep 10

MTC_SERV="pluto.prod.market-tech.com"
MTC_DIR="/pluto1/MTC/FARES/${RDIR}/IN"
MTC_NOTIFY="mlocke@market-tech.com,support@techsafari.com"

NS_SERV="db07.techsafari.com"
NS_DIR="/data/in/court/court_monthly/${RDIR}"
NS_NOTIFY="support@techsafari.com"

PAGER="support-pager@techsafari.com"

ERROR=0

[[ ! -d $LOAD_DIR ]] && exit 1

echo "Transferring files to ${MTC_SERV}:${MTC_DIR}"
rsync -av -e ssh --progress ${LOAD_DIR}/ ${MTC_SERV}:${MTC_DIR}/
if [[ $? -ne 0 ]] ; then
    echo "ERROR during FARES transfer to ${MTC_SERV}"
    echo "ERROR during FARES transfer to ${MTC_SERV}" \
        | mail -s "FARES XFER ERROR" ${PAGER}
    ERROR=1
else
    echo "FARES Transfer complete to ${MTC_SERV}:${MTC_DIR}"
    echo "FARES Transfer complete to ${MTC_SERV}:${MTC_DIR}" \
        | mail -s "FARES XFER COMPLETE" ${MTC_NOTIFY}
fi

echo "Transferring files to ${NS_SERV}:${NS_DIR}"
rsync -av -e ssh --progress ${LOAD_DIR}/ tuser@${NS_SERV}:${NS_DIR}/
if [[ $? -ne 0 ]] ; then
    echo "ERROR during FARES transfer to ${NS_SERV}"
    echo "ERROR during FARES transfer to ${NS_SERV}" \
        | mail -s "FARES XFER ERROR" ${PAGER}
    ERROR=1
else
    echo "FARES Transfer complete to ${NS_SERV}:${NS_DIR}"
    echo "FARES Transfer complete to ${NS_SERV}:${NS_DIR}" \
        | mail -s "FARES XFER COMPLETE" ${NS_NOTIFY}
fi

exit $ERROR
