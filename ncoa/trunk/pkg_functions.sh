#!/bin/bash

#####
# $Id: pkg_functions.sh,v 1.1 2007/01/02 17:58:21 dyoung Exp $
#####
# $Log: pkg_functions.sh,v $
# Revision 1.1  2007/01/02 17:58:21  dyoung
# Initial Release (Mac only)
#
#####

eval ISO_HOME="~/work/iso"
export NCOA_ISO_HOME="$ISO_HOME/ncoa"
export CASS_ISO_HOME="$ISO_HOME/cass"

##
# Subroutines for MAC
##
get_cd_dev() {
    COUNT=0
    for DISK in /dev/disk? ; do
        if [[ "$(diskutil info $DISK | grep "Protocol" | awk '{ print $2 }')" == "ATAPI" ]] ; then
            echo "$DISK"
            ((COUNT++))
        fi
    done
    exit $COUNT
}

wait_for_cd() {
    while [[ "$(get_cd_dev)" == "" ]] ; do
        sleep 1
    done

    return $?
}

cd_eject() {
    diskutil eject $*
}

cd_umount() {
    diskutil unmount $*
}
