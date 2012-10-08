#!/bin/bash
#
# cass_install.sh
#   2007/07 - Donovan C. Young
#
#   Automates the installation of the Melissa Data directores
#
#   $Id: cass_install.sh,v 1.5 2007/08/03 15:44:32 dyoung Exp $
#
######################################################################

PROGRAM=$(basename $0)
OPT_VERBOSE=0
OPT_FORCE=0
OPT_CLEAN=0
OPT_TEST=0

# Verbose modes
VQUIET=0
VNORM=1
VLOUD=2
VDEBUG=3

# Other vars
DOLOAD=1    # set to 0 to prevent load
DOTEST=1    # set to 0 to prevent test
DOLINK=1    # set to 0 to prevent symlink creation

##
# Subroutines
##
get_jcl_home() {
    [[ -n "$JCL_HOME" && -d "$JCL_HOME" ]] && return
    
    for JCL_HOME in /opt/mtc_jcl /usr/local/mtc_jcl ; do
        [[ -d "$JCL_HOME" ]] && return
    done

    die "JCL_HOME is not set and we could not locate it, please check the environment variables!"
}

get_buildnum() {
    HDRFILE="/tmp/month.dat"

    print $VLOUD "Testing connection to $RSERVER and getting CASS Release number"

    # Get the dvdhdr01.dat file to test the connection and get the build#
    rsync $RSERVER::cass-live/DPV/month.dat $HDRFILE || die "There was a problem contacting $RSERVER!"
    [[ -f $HDRFILE ]] || die "Unable to obtain the build number!"

    BUILD_TMON=$(cat $HDRFILE | awk '{ print $1 }')
    BUILD_YEAR=$(cat $HDRFILE | awk '{ print $2 }')

    # The date above is one month behind the actual database date
    case $BUILD_TMON in
        'January'   ) BUILD_MON=02 ;;
        'February'  ) BUILD_MON=03 ;;
        'March'     ) BUILD_MON=04 ;;
        'April'     ) BUILD_MON=05 ;;
        'May'       ) BUILD_MON=06 ;;
        'June'      ) BUILD_MON=07 ;;
        'July'      ) BUILD_MON=08 ;;
        'August'    ) BUILD_MON=09 ;;
        'September' ) BUILD_MON=10 ;;
        'October'   ) BUILD_MON=11 ;;
        'November'  ) BUILD_MON=12 ;;
        'December'  ) BUILD_MON=01 ; BUILD_YEAR=$((BUILD_YEAR + 1)) ;;
    esac

    BUILD_NUM="${BUILD_YEAR}${BUILD_MON}"

    print $VDEBUG "Build number obtained from $RSERVER is $BUILD_NUM"

    rm -f $HDRFILE
}

cass_load() {
    if [[ -d ${BUILD_DIR} ]] ; then
        if [[ $OPT_FORCE -gt 0 ]] ; then
            print $VLOUD "Removing ${BUILD_DIR}"
            rm -rf ${BUILD_DIR}
        else
            if [[ -z "$(ls ${BUILD_DIR} 2> /dev/null)" ]] ; then
                print $VLOUD "${BUILD_DIR} seems to be empty, removing ${BUILD_DIR}"
                rm -rf ${BUILD_DIR}
            else
                print $VNORM "${BUILD_DIR} already exists, skipping data load"
                return 1
            fi
        fi
    fi

    print $VLOUD "${BUILD_DIR} does not exist.  Creating..."
    mkdir ${BUILD_DIR} || die "Error creating ${BUILD_DIR}!"

    [[ -n "$RSERVER" ]] && install_rsync
    [[ -z "$RSERVER" ]] && install_tar

    return 1
}

install_tar() {
    BUILD_TAR="${TARDIR}/mdata.${BUILD_NUM}.tgz"
    BUILD_BASE="$(dirname ${BUILD_DIR})"
    TAR_OPTS="-xpz"
    # add the verbose flag if appropriate
    [[ $OPT_VERBOSE -ge $VDEBUG ]] && TAR_OPTS="${TAR_OPTS} -v"

    [[ ! -f "${BUILD_TAR}" ]] && die "${BUILD_TAR} does not exist!"

    print $VLOUD "Untaring ${MELFILE}"
    $TAR $TAR_OPTS -f ${BUILD_TAR} -C ${BUILD_BASE}

    ECODE=$?
    if [[ $ECODE -ne 0 ]] ; then
        print $VDEBUG "Tar exited with status $ECODE"
        die "There was a problem untarring $BUILD_TAR to $BUILD_BASE"
    fi
}

install_rsync() {
    ROPT="-a"
    [[ $OPT_VERBOSE -ge $VDEBUG ]] && ROPT="$ROPT -v"

    print $VNORM "Starting CASS Rsync to ${BUILD_DIR}"
    print $VDEBUG "Using: rsync $ROPT $RSERVER::cass-live $BUILD_DIR"

    rsync $ROPT $RSERVER::cass-live $BUILD_DIR
    STATUS=$?
    [[ $STATUS -ne 0 ]] && die "rsync returned $STATUS, please check and try again."

    return 1
}

cass_test() {
    print $VNORM "Running CASS tests"
    [[ $OPT_VERBOSE -ge $VLOUD ]] && CHECK_OPTS="--verbose"
    $CASS_CHECK $CHECK_OPTS --build ${BUILD_NUM}
    if [[ $? -ne 0 ]] ; then
        DOLINK=0
        return 1
    fi
    print $VLOUD "CASS Test Successful"
    return 0
}

cass_link() {
    if [[ $($FUSER $SYMLINK/*) ]]; then
        print $VQUIET "Something is using the CASS libraries at this point in time."
        print $VQUIET "Please try again at a later time."
        exit 99
    fi

    print $VLOUD "Creating symbolic link"
    ln -nsf ${BUILD_DIR} ${SYMLINK} || die "Unable to create symlink!"

    print $VNORM "New CASS build is now in place."

    return 1
}

die() {
    echo -e "ERROR: $*"
    exit 1
}

myexit() {
    echo -e $*
    exit 0
}

print() {
    [[ $1 != [0-9] ]] && die "Invalid print statement"

    if [[ $OPT_VERBOSE -ge $1 ]] ; then
        shift;
        echo -e $*
    fi
    
    return 1
}

# Clearing the kernel ring buffer
clear_dmesg() {
    dmesg -c > /dev/null 2>&1
    [[ $? -ne 0 ]] && die "Could not clear the kernel ring buffer:  $!"
    print $VDEBUG "Kernel ring buffer cleared"
}

version() {
    VERSION=$(echo "$Revision: 1.5 $" | awk '{print $2}')
    echo -e "\n$0 $VERSION - Donovan C. Young"
}   

usage() {
    version;
    cat <<EOT

    Usage: $PROGRAM OPTIONS < -b <build> | -s <server> >

        One of the following commands are required:

      * -b|--build <build>   : The 6-digit release based upon YYYYMM
      * -s|--server <server> : Use <server> for CASS image (assumes Rsync mode)

        And any combination of the following OPTIONS are optional:

        -c|--clean           : Run the cass_clean.sh script prior to install
        -f|--force           : Force the install regardless of current status
                               (use this to restart a bad install)
        -h|--help            : Print this help message.
        -t|--test            : Run tests even if already installed
        --nolink             : Do not create the symlink, only install the files
        --notest             : Do not run tests
        -v|--verbose         : Provide more feedback (may be given more than once)
        -V|--version         : Display the program version and exit

    * Required

EOT
    exit 3
}

OPTIONS=$(getopt -n cass_install -o b:cfhs:tvV --long build:,clean,force,help,server:,test,nolink,notest,verbose,version -- "$@")
[[ $? -ne 0 ]] && usage

eval set -- "$OPTIONS"

while true ; do
    case $1 in
        -b|--build   ) BUILD_NUM=$2; shift;;
        -c|--clean   ) OPT_CLEAN=1;;
        -f|--force   ) OPT_FORCE=1;;
        -h|--help    ) usage;;
        -s|--server  ) RSERVER=$2; shift;;
        -t|--test    ) OPT_TEST=1;;
        --nolink     ) DOLINK=0;;
        --notest     ) DOTEST=0;;
        -v|--verbose ) ((OPT_VERBOSE++));;
        -V|--version ) version; myexit;;
        --      ) shift; break;;
        *       ) usage;;
    esac
    shift
done

##
# Validate options and programs
##
[[ "$UID" -ne 0 ]] && die "This program must be run as root"

[[ -n "$RSERVER" ]] && get_buildnum

[[ ${BUILD_NUM} != 200[0-9][0-9][0-9] ]] && usage

# Make sure our environment is sane
get_jcl_home
source $JCL_HOME/jcl.profile
[[ -d "/usr/local/rhino" ]] && PATH="$PATH:/usr/local/rhino"
[[ -d "/opt/mtcsbin" ]] && PATH="$PATH:/opt/mtcsbin"

## Program locations
if [[ -z "$RSERVER" ]] ; then
    # Tar
    TAR="$(type -p tar)"
    [[ ! -x $TAR ]] && die "Could not locate tar!"
    print $VDEBUG "tar found at $TAR"
fi

# fuser
FUSER="$(type -p fuser)"
[[ ! -x $FUSER ]] && die "Could not locate fuser!"
print $VDEBUG "fuser found at $FUSER"

# cass_check.pl
CASS_CHECK="$(type -p cass_check.pl)"
[[ ! -x $CASS_CHECK ]] && die "Could not locate cass_check.pl!"
print $VDEBUG "cass_check.pl found at $CASS_CHECK"

# cass_clean.pl
if [[ $OPT_CLEAN -ne 0 ]] ; then
    CASS_CLEAN="$(type -p cass_clean.sh)"
    [[ ! -x $CASS_CLEAN ]] && die "Could not locate cass_clean.sh!"
    print $VDEBUG "cass_clean.sh found at $CASS_CLEAN"
    DOCLEAN=1
fi

# CASS locations
if [[ -z "$RSERVER" ]] ; then
    TARDIR="/data/cass"                     # Where the DVD isos are.
    [[ ! -d ${TARDIR} ]] && die "CASS tar files not found on this host, please check and retry"
fi

SYMLINK="/usr/local/mdata"
if [[ ! -d ${SYMLINK} ]] ; then
    [[ $OPT_FORCE -eq 0 ]] && die "CASS not installed on this host, please check and retry"

    # Force is on, so assume /usr/local as our installation directory
    PREV_BUILD_DIR=""
         BUILD_DIR="$(dirname ${SYMLINK})/mdata.${BUILD_NUM}"

    ln -nsf ${BUILD_DIR} ${SYMLINK}
else
    # Get the current and previous directories
    PREV_BUILD_DIR="$(readlink -f ${SYMLINK})"
         BUILD_DIR="$(dirname ${PREV_BUILD_DIR})/mdata.${BUILD_NUM}"
fi

if [[ "$BUILD_DIR" = "$PREV_BUILD_DIR" ]] ; then
    [[ $OPT_TEST -eq 0 && $OPT_FORCE -eq 0 ]] && myexit "${BUILD_DIR} Already installed."
    DOLOAD=0
fi

[[ $DOCLEAN -eq 1 ]] && $CASS_CLEAN
[[ $DOLOAD  -eq 1 ]] && cass_load
if [[ $DOTEST  -eq 1 ]] ; then cass_test || die "Test Failed"; fi
[[ $DOLINK  -eq 1 ]] && cass_link

exit 0

