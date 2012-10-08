#!/bin/bash
#
# cass_clean.sh
#   2007/07 - Donovan C. Young
#
#   Automates the removal of old mdata directories.  Removes all but the
#   current load dir.
#
#   $Id: cass_clean.sh,v 1.1 2007/07/25 21:47:50 dyoung Exp $
#
######################################################################

# CASS locations
SYMLINK="/usr/local/mdata"                     # Where JCL thinks your CASS data is.

error() {
    echo $*
    exit 1
}

cass_clean() {
    # Remove all but the current directory
    cd $BUILD_DIR
    for CASS in $(ls -d mdata.200[0-9][0-9][0-9]) ; do
        [[ "$CASS" == "$CUR_BUILD_NUM" ]] && continue

        echo "Removing old directory: ${CASS}"
        [[ -d ${CASS} ]] && rm -rf $CASS
    done
}

# Make sure our environment is sane
source /etc/profile
source ~/.bash_profile

# Make sure CASS is installed on this system
if [[ ! -d ${SYMLINK} ]] ; then
    echo "CASS not installed on this host, please check and retry"
    exit 1
fi

# Get the current and previous directories
CUR_BUILD_DIR="$(readlink -f ${SYMLINK})"
CUR_BUILD_NUM="$(basename ${CUR_BUILD_DIR})"
    BUILD_DIR="${CUR_BUILD_DIR%/*}"

if [[ ! -d $CUR_BUILD_DIR ]] ; then
    echo "Current build is not valid!  Please check!"
    exit 1
fi

echo "Current Build Dir = $CUR_BUILD_DIR"

cass_clean
