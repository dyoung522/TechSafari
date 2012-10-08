#!/bin/bash
#
# ncoa_clean.sh
#   2006/10 - Donovan C. Young
#
#   ncoa_clean.sh <build number>
#
#   Automates the removal of old NCOA directories.  Removes all but the
#   current load dir.
#
#   $Id: ncoa_clean.sh,v 1.2 2006/10/06 15:01:37 dyoung Exp $
#
######################################################################
#   $Log: ncoa_clean.sh,v $
#   Revision 1.2  2006/10/06 15:01:37  dyoung
#   Added another safety check
#
#   Revision 1.1  2006/10/06 14:49:38  dyoung
#   Initial release.  Removes old NCOA directories
#
#
######################################################################

# NCOA locations
SYMLINK="/usr/local/NCOA"                     # Where JCL thinks your NCOA data is.

error() {
    echo $*
    exit 1
}

ncoa_clean() {
    # Remove all but the previous directory
    cd $BUILD_DIR
    for NCOA in $(ls -d NCOA-[0-9][0-9][0-9][0-9]) ; do
        [[ "$NCOA" == "$CUR_BUILD_NUM" ]] && continue

        echo "Removing old directory: ${NCOA}"
        [[ -d ${NCOA} ]] && rm -rf $NCOA
    done
}

# Make sure our environment is sane
source /etc/profile
source ~/.bash_profile

# Make sure NCOA is installed on this system
if [[ ! -d ${SYMLINK} ]] ; then
    echo "NCOA not installed on this host, please check and retry"
    exit 1
fi

# Get the current and previous directories
CUR_BUILD_DIR="$(readlink ${SYMLINK})"
CUR_BUILD_NUM="$(basename ${CUR_BUILD_DIR})"
    BUILD_DIR="${CUR_BUILD_DIR%/*}"

if [[ ! -d $CUR_BUILD_DIR ]] ; then
    echo "Current build is not valid!  Please check!"
    exit 1
fi

echo "Current Build Dir = $CUR_BUILD_DIR"

ncoa_clean
