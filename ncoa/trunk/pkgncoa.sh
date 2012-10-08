#!/bin/bash

#####
# $Id: pkgncoa.sh,v 1.1 2007/01/02 17:58:03 dyoung Exp $
#####
# $Log: pkgncoa.sh,v $
# Revision 1.1  2007/01/02 17:58:03  dyoung
# Initial release (Mac only)
#
#####

# Grab our custom function
source $(dirname $0)/pkg_functions.sh

REL="$1"
SLEEP=5
TOTAL_DISCS=2
DVD=0

if [[ -z "$REL" ]] ; then
    echo -e "\nUsage: $0 REL\n"
    exit 1
fi

while [[ $((++DVD)) -le ${TOTAL_DISCS} ]] ;do
    ISO="${NCOA_ISO_HOME}/ncoa-${REL}-dvd${DVD}.iso"

    if [[ -f ${ISO} ]] ; then
        echo "${ISO} already exists, skipping load"
    else
        while true; do
            DEV=$(get_cd_dev)
            if [[ $? -eq 0 ]] ; then
                echo -n "Please put disc $DVD in the DVD drive... "
                wait_for_cd
                DEV=$(get_cd_dev)
            elif [[ $? -ne 1 ]] ; then
                echo "Hmmm... I've having problems finding the DVD device, please check"
                exit 1
            fi
    
            VOL="$(diskutil info $DEV | grep 'Volume Name' | awk -F':' '{ print $2 }' | sed -e 's/^ *//')"
            echo "Found \"$VOL\" on $DEV"
            if [[ "${VOL##*D}" -ne $DVD ]] ; then
                echo "Oops, looks like the wrong disc!"
                cd_eject $DEV
            else
                break
            fi
        done

        # Unmount the DVD so we can read it
        echo -n "Unmounting DVD $DVD... "
        cd_umount $DEV

        echo -n "Loading NCOA DVD ${DVD} to ${ISO}... "
        dd if=${DEV} of=${ISO} bs=32768 > /tmp/dd.out 2>&1
        if [[ $? -ne 0 ]] ; then
            cat /tmp/dd.out
            echo "Error loading ${DVD}, aborting load"
            exit 1
        else
            rm -f /tmp/dd.out
            echo "OK"
        fi

        # Eject the DVD
        echo -n "Ejecting DVD $DVD... "
        cd_eject $DEV 
    fi
done

exit 0
