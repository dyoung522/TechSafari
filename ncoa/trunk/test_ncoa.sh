#!/bin/bash
#
# test_ncoa.sh
#   2006/06 - Donovan C. Young
#
#   test_ncoa.sh
#
#   Runs the NCOA test to confirm NCOA is working as expected.
#
#   $Id: test_ncoa.sh,v 1.3 2007/04/11 20:26:36 dyoung Exp $
#
######################################################################
#   $Log: test_ncoa.sh,v $
#   Revision 1.3  2007/04/11 20:26:36  dyoung
#   Cleaned up JCL test routines
#
#   Revision 1.2  2006/06/29 17:56:23  dyoung
#   Minor typo
#
#   Revision 1.1  2006/06/29 17:53:56  dyoung
#   Tests NCOA installation
#
#
######################################################################

# NCOA locations
SYMLINK="/usr/local/NCOA" # Where JCL thinks your NCOA data is.
CASSTEST="/usr/local/CASS_TEST/ncoa"

if [[ -z "$JCL_HOME" ]] ; then
    echo "JCL_HOME is not set!"
    exit 2
fi

# Make sure our environment is sane
source /etc/profile
source ~/.bash_profile
source $JCL_HOME/jcl.profile

# Make sure NCOA is installed on this system
if [[ ! -d ${SYMLINK} ]] ; then
    echo "NCOA not installed on this host, please check and retry"
    exit 1
fi

BUILD_DIR="$(ls -l ${SYMLINK} | awk -F'> ' '{ print $2 }')"

echo "NCOA is currently installed at ${BUILD_DIR}"
echo "Testing..."

cd ${CASSTEST}
mtc_jcl -w -m -l LOGFILE -x test_ncoa.jcl > LOGFILE 2>&1

JCL_STATUS=$?

if [[ ${JCL_STATUS} -ne 0 ]] ; then
    echo -e "\n!!! WARNING !!! WARNING !!! WARNING !!!"
    tail -n 10 LOGFILE
    echo -e "\n!!! WARNING !!! WARNING !!! WARNING !!!"
    exit $JCL_STATUS
else
    echo "NCOA Test Successful"
    exit 0
fi
