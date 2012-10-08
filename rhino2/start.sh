#!/bin/bash
# Modified by Donovan Young 05/2009

# Function to cleanly modify ENV vars
# Usage envmunge <EVN> <Value> [after] (after can be used to put the new value at the end)
envmunge () {
    if ! eval echo $1 | /bin/egrep -q "(^|:)$2($|:)" ; then
        if [ "$3" = "after" ] ; then
            eval $1="\$$1:$2"
        else
            eval $1="$2:\$$1"
        fi
    fi
    eval export $1
}

# Allows us to throw an error and exit all in one line
die() {
    echo >&2 $*
    exit 1
}

# Determine mode (INIT used by the rhino2 init script)
INIT=0 ; [[ "$1" == "INIT" ]] && INIT=1

# If $R2HOME isn't already set, set it.
[[ -z "$R2HOME" ]] && export R2HOME="/usr/local/rhino2"

# Set internal variables to make future changes easier
R2LOGDIR="/var/log/rhino2"
R2CONTROL="${R2HOME}/bin/r2sys_control"
R2CONFIG="${R2HOME}/conf/config.xml"

# Set our PATH and other ENV variables
envmunge PATH "$R2HOME/bin"
envmunge LD_LIBRARY_PATH "/usr/local/lib"
envmunge LD_LIBRARY_PATH "/usr/local/mdata"
export FIFO_DIR="$R2HOME/fifo"

# Sanity Checks
cd $R2HOME/bin || die "Unable to change directory to ${R2HOME}/bin"
[[ -x "$R2CONTROL" ]] || die "$R2CONTROL is not valid!"
[[ -r "$R2CONFIG"  ]] || die "Could not read config file $R2CONFIG"
[[ -w "$FIFO_DIR"  ]] || die "FIFO dir $FIFO_DIR is not valid!"
[[ -w "$R2LOGDIR"  ]] || die "Log dir $R2LOGDIR is not valid!"

if [[ $(ps -u $(id -un) | grep r2sys_control | grep -v grep | wc -l) -gt 0 ]] ; then
    echo "******************************************************************************"
    echo
    echo WARNING: looks like r2sys_control is already running - will not delete FIFOs
    echo
    echo "******************************************************************************"
else
    # Clean any leftover pipes
    for FIFO in $FIFO_DIR/* ; do
        [[ -p "$FIFO" ]] && rm -f "$FIFO"
    done
fi

# Make sure stack limit is not set
ulimit -s unlimited

# Start R2
$R2CONTROL -l $R2LOGDIR/stdout.txt -b -X $R2CONFIG

# Quit here if we were called from init.d
[[ $INIT -gt 0 ]] && exit $?

# Tail the logfile
echo -e "Tailing logfile.txt ...\n"
sleep 1
tail -f $R2LOGDIR/logfile.txt

