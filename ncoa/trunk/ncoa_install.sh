#!/bin/bash
#
# ncoa_install.sh
#   2006/04 - Donovan C. Young
#
#   ncoa_install.sh <build number>
#
#   Automates the installation of the NCOA directores on the MTC servers.
#
#   $Id: ncoa_install.sh,v 2.7 2007/06/13 19:46:37 dyoung Exp $
#
######################################################################
#   $Log: ncoa_install.sh,v $
#   Revision 2.7  2007/06/13 19:46:37  dyoung
#   Minor fix
#
#   Revision 2.6  2007/06/13 19:44:21  dyoung
#   Bug in options
#
#   Revision 2.5  2007/06/12 20:13:43  dyoung
#   Added rsync support
#
#   Revision 2.4  2007/04/20 19:45:36  dyoung
#   Added JCL_HOME (simple) auto locate functionality
#
#   Revision 2.3  2007/04/12 23:09:46  dyoung
#   Minor changes
#
#   Revision 2.2  2007/04/12 22:39:25  dyoung
#   More prep work for RSYNC install
#
#   Revision 2.1  2007/04/12 00:35:06  dyoung
#   Rewrite to use getopt for option parsing
#
#   Revision 1.20  2007/04/11 22:25:59  dyoung
#   Rewrote the testing functionality to use the separate ncoa_check.pl script
#   which allows for greater flexability in testing.
#   Also added many more "idiot" checks to be sure we have everything
#   necessary for a successful run.
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
    HDRFILE="/tmp/dvdhdr01.dat"

    print $VLOUD "Testing connection to $RSERVER and getting NCOA Release number"

    # Get the dvdhdr01.dat file to test the connection and get the build#
    rsync $RSERVER::ncoa-live/dvdhdr01.dat $HDRFILE || die "There was a problem contacting $RSERVER!"
    [[ -f $HDRFILE ]] || die "Unable to obtain the build number!"

    BUILD_NUM=$(grep "Release Number" $HDRFILE | awk '{ print $3 }')

    print $VDEBUG "Build number obtained from $RSERVER is $BUILD_NUM"

    rm -f $HDRFILE
}

ncoa_load() {
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
    [[ -z "$RSERVER" ]] && install_iso

    return 1
}

install_iso() {
    print $VNORM "Starting NCOA Data Load to ${BUILD_DIR}"

    cd ${BUILD_DIR}

    for DISC in 1 2 ; do
        BUILD_ISO="${ISODIR}/ncoa-${BUILD_NUM}-dvd${DISC}.iso"

        [[ ! -f ${BUILD_ISO} ]] && die "${BUILD_ISO} does not exist"

        # Mounting ISO
        print $VDEBUG "Mounting Disc ${DISC}"
        mount -o loop ${BUILD_ISO} /mnt/cdrom
        [[ $? -ne 0 ]] && die "Could not mount disc ${DISC}:  $!"

        clear_dmesg

        # copy the files
        print $VNORM "Copying files from Disc ${DISC}"
        cp /mnt/cdrom/* ${BUILD_DIR}
        [[ $? -ne 0 ]] && die "Problem copying files from disc ${DISC}:  $!"

        umount /mnt/cdrom
        [[ $? -ne 0 ]] && die "Could not unmount disc ${DISC}:  $!"
    done

    print $VNORM "Decompressing files"

    if [[ -n "$(ls *.szp 2> /dev/null)" ]] ; then
        ### Starting unszping
        print $VLOUD "Unszp'ing files"

        for FILE in *.szp ; do
            $UNSZP $FILE >/dev/null
            [[ $? -ne 0 ]] && die "Problem unszp'ing ${FILE}:  $!"

            # Remove the original file
            rm -f $FILE
        done
    fi

    if [[ -n "$(ls *.zip 2> /dev/null)" ]] ; then
        ### Unzip all zip files
        print $VLOUD "Unzip'ing files"

        for FILE in *.zip ; do
            $UNZIP -o $FILE >/dev/null
            [[ $? -ne 0 ]] && die "Problem unzip'ing ${FILE}:  $!"

            # Remove the original file
            rm -f $FILE
        done
    fi

    if [[ ! -f "rv9.pg" ]] ; then
        ### Build rv file
        print $VLOUD "Building RV file"
        cat rv9.esd | $BUILDRV
        [[ $? -ne 0 ]] && die "Problem with the rv9 file"
    fi

    return 1
}

install_rsync() {
    ROPT="-a"
    [[ $OPT_VERBOSE -ge $VDEBUG ]] && ROPT="$ROPT -v"

    print $VNORM "Starting NCOA Rsync to ${BUILD_DIR}"
    print $VDEBUG "Using: rsync $ROPT $RSERVER::ncoa-live $BUILD_DIR"

    rsync $ROPT $RSERVER::ncoa-live $BUILD_DIR
    STATUS=$?
    [[ $STATUS -ne 0 ]] && die "rsync returned $STATUS, please check and try again."

    return 1
}

ncoa_test() {
    print $VNORM "Running NCOA tests"
    [[ $OPT_VERBOSE -ge $VLOUD ]] && CHECK_OPTS="--verbose"
    $NCOA_CHECK $CHECK_OPTS --jcltest --build ${BUILD_NUM}
    [[ $? -ne 0 ]] && return 1
    print $VLOUD "NCOA Test Successful"

    return 0
}

ncoa_link() {
    if [[ $($FUSER $SYMLINK/*) ]]; then
        print $VQUIET "Something is using the NCOA libraries at this point in time."
        print $VQUIET "Please try again at a later time."
        exit 99
    fi

    print $VLOUD "Creating symbolic link"
    ln -nsf ${BUILD_DIR} ${SYMLINK} || die "Unable to create symlink!"

    print $VNORM "New NCOA build is now in place."

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
    VERSION=$(echo "$Revision: 2.7 $" | awk '{print $2}')
    echo -e "\n$0 $VERSION - Donovan C. Young"
}   

usage() {
    version;
    cat <<EOT

    Usage: $PROGRAM OPTIONS < -b <build> | -s <server> >

        One of the following commands are required:

      * -b|--build <build>   : The 4-digit release printed on the DVD (required)
      * -s|--server <server> : Use <server> for NCOA image (assumes Rsync mode)

        And any combination of the following OPTIONS are optional:

        -c|--clean           : Run the ncoa_clean.sh script prior to install
        -f|--force           : Force the install regardless of current status
                               (use this to restart a bad install)
        -h|--help            : Print this help message.
        -t|--test            : Run tests even if already installed
        --notest             : Do not run tests
        -v|--verbose         : Provide more feedback (may be given more than once)
        -V|--version         : Display the program version and exit

    * Required

EOT
    exit 3
}

OPTIONS=$(getopt -n ncoa_install -o b:cfhs:tvV --long build:,clean,force,help,server:,test,notest,verbose,version -- "$@")
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

[[ ${BUILD_NUM} != [0-9][0-9][0-9][0-9] ]] && usage

# Make sure our environment is sane
get_jcl_home
source $JCL_HOME/jcl.profile
[[ -d "/usr/local/rhino" ]] && PATH="$PATH:/usr/local/rhino"
[[ -d "/opt/mtcsbin" ]] && PATH="$PATH:/opt/mtcsbin"

## Program locations
if [[ -z "$RSERVER" ]] ; then
    # unszp
    UNSZP="$JCL_HOME/ncoa/unszp"
    [[ ! -x $UNSZP ]] && die "Could not locate unszp!"

    # build_rv_pg
    BUILDRV="$JCL_HOME/ncoa/build_rv_pg"
    [[ ! -x $BUILDRV ]] && die "Could not locate build_rv_pg!"

    # Unzip
    UNZIP="$(type -p unzip)"
    [[ ! -x $UNZIP ]] && die "Could not locate unzip!"
fi

# fuser
FUSER="$(type -p fuser)"
[[ ! -x $FUSER ]] && die "Could not locate fuser!"

# ncoa_check.pl
NCOA_CHECK="$(type -p ncoa_check.pl)"
[[ ! -x $NCOA_CHECK ]] && die "Could not locate ncoa_check.pl!"

# ncoa_clean.pl
if [[ $OPT_CLEAN -ne 0 ]] ; then
    NCOA_CLEAN="$(type -p ncoa_clean.sh)"
    [[ ! -x $NCOA_CLEAN ]] && die "Could not locate ncoa_clean.sh!"
    DOCLEAN=1
fi

# NCOA locations
if [[ -z "$RSERVER" ]] ; then
    ISODIR="/data/ncoa"                     # Where the DVD isos are.
    [[ ! -d ${ISODIR} ]] && die "NCOA ISO's not found on this host, please check and retry"
fi

SYMLINK="/usr/local/NCOA"
if [[ ! -d ${SYMLINK} ]] ; then
    [[ $OPT_FORCE -eq 0 ]] && die "NCOA not installed on this host, please check and retry"

    # Force is on, so assume /usr/local as our installation directory
    PREV_BUILD_DIR=""
         BUILD_DIR="$(dirname ${SYMLINK})/NCOA-${BUILD_NUM}"

    ln -nsf ${BUILD_DIR} ${SYMLINK}
else
    # Get the current and previous directories
    PREV_BUILD_DIR="$(readlink ${SYMLINK})"
         BUILD_DIR="$(dirname ${PREV_BUILD_DIR})/NCOA-${BUILD_NUM}"
fi

if [[ "$BUILD_DIR" = "$PREV_BUILD_DIR" ]] ; then
    [[ $OPT_TEST -eq 0 && $OPT_FORCE -eq 0 ]] && myexit "${BUILD_DIR} Already installed."
    DOLOAD=0
fi

[[ $DOCLEAN -eq 1 ]] && $NCOA_CLEAN
[[ $DOLOAD  -eq 1 ]] && ncoa_load
[[ $DOTEST  -eq 1 ]] && ( ncoa_test || die "Test Failed" )
[[ $DOLOAD  -eq 1 ]] && ncoa_link

exit 0

