#!/bin/bash
#
#  $Id: global.sh,v 1.9 2007/01/09 19:46:14 dyoung Exp $
#
#  05/2006 - Donovan C. Young
#
#  global.sh - runs a command on each server specified in a given file
#
#    ~/.global/config holds default values, see global.config for more info
#
######################################################################
#
#  $Log: global.sh,v $
#  Revision 1.9  2007/01/09 19:46:14  dyoung
#  fixed spelling error
#
#  Revision 1.8  2006/07/06 17:58:47  dyoung
#  Added code to skip commented hosts in host files.
#
#  Revision 1.7  2006/06/21 16:53:45  dyoung
#  moved .globalrc to .global/config and moved default host file location to
#  ~/.global/
#
#  Revision 1.6  2006/06/21 16:15:17  dyoung
#  Minor change
#
#  Revision 1.5  2006/06/21 16:10:00  dyoung
#  Added LOG_DIR and other enhancements.
#
#  Revision 1.4  2006/06/08 22:11:31  dyoung
#  Fixed typo
#
#  Revision 1.3  2006/06/08 22:09:16  dyoung
#  Moved globalrc to seperate file
#
#  Revision 1.2  2006/06/08 21:55:27  dyoung
#  Minor change
#
#  Revision 1.1  2006/05/31 00:51:44  dyoung
#  Runs commands sequentially on multiple servers.
#
######################################################################

# Global variables
SSH="/usr/bin/ssh"
SSH_OPTS="-tq"
eval CONFIG_FILE="~/.global/config"
eval LOG_DIR="."
eval DEFAULT_HOST_DIR="~"

usage() {
    version
    cat <<EoT
Runs a remote command on each server found in the host file.  Without -v or
-q options, only the server name, command and exit code are displayed.  All
output is put in individual log files in the form of: [host].output

Empty output files are removed at the end of the run.

Usage:
        $0 [OPTIONS] <cmd>

    Options:
        -l <user> : specifies the user to run cmd as
        -h <file> : specifies an alternate host file list
        -q        : quiet mode - No output unless command errors
        -v        : verbose mode - All command output is displayed

EoT
    exit 1
}

version() {
    VERSION=$(echo "$Revision: 1.9 $" | awk '{print $2}')
    echo -e "\n$0 $VERSION - Donovan C. Young\n"
}

# Delare option variables and defaults
typeset -i QUIET=0
typeset -i VERBOSE=0

if [[ ! -r $CONFIG_FILE ]] ; then
    echo "Could not read $CONFIG_FILE"
    exit 1
fi

[[ -f $CONFIG_FILE ]] && source $CONFIG_FILE
[[ -z "$*"        ]] && usage

typeset -i OPT_QUIET=$QUIET
typeset -i OPT_VERBOSE=$VERBOSE

while getopts "h:l:qv" opt
do
    case $opt in
        l ) SSH_USER="$OPTARG" ;;
        h ) SSH_HOST_FILE="$OPTARG" ;;
        q ) OPT_QUIET=$((QUIET     ^ 1 )) ; OPT_VERBOSE=0 ;;
        v ) OPT_VERBOSE=$((VERBOSE ^ 1 )) ; OPT_QUIET=0 ;;
        ? ) usage ;;
    esac
done

shift $((OPTIND - 1))
ssh_cmd=$*

# Check command
if [[ -z "$ssh_cmd" ]] ; then
    echo "No remote command specified."
    usage
fi

# Check host file
eval SSH_HOST_FILE=$SSH_HOST_FILE
if [[ "$(echo $SSH_HOST_FILE | cut -c1)" != "/" ]] ; then
    eval SSH_HOST_FILE="${DEFAULT_HOST_DIR}/${SSH_HOST_FILE}"
fi
if [[ ! -r "$SSH_HOST_FILE" ]] ; then
    echo "$0: host file \"$SSH_HOST_FILE\" does not exist, or is not readable."
    usage
fi

# Check user
if [[ -z "$SSH_USER" ]] ; then
    echo "No username specified"
    usage
fi

# Check log dir
eval LOG_DIR=$LOG_DIR
[[ ! -d "$LOG_DIR" ]] && mkdir -p ${LOG_DIR}
if [[ ! -d "$LOG_DIR" ]] ; then
    echo "${LOG_DIR} is not a valid directory."
    echo "Please check the LOG_DIR setting in $CONFIG_FILE."
    exit 1
fi

[[ $OPT_VERBOSE -eq 1 ]] && [[ $OPT_QUIET -eq 1 ]] && OPT_VERBOSE=0

if [[ $OPT_VERBOSE -eq 1 ]] ; then
    version
    echo "  running command: \"$ssh_cmd\""
    echo "          as user: \"$SSH_USER\""
    echo "    on servers in: \"$SSH_HOST_FILE\""
    echo "sending output to: \"$LOG_DIR\""
    echo
fi

for ssh_host in $(cat $SSH_HOST_FILE) ; do
    # Skip commented out host lines
    [[ "${ssh_host:0:1}" = "#" ]] && continue

    ssh_log="${LOG_DIR}/${ssh_host%%.*}.output"

    # Verbose
    if [[ $OPT_VERBOSE -eq 1 ]] ; then
        printf ">>> %-10s (%s)\n" "${ssh_host%%.*}" "$ssh_cmd"
        ${SSH} ${SSH_OPTS} -l $SSH_USER $ssh_host $ssh_cmd | tee ${ssh_log} 2>&1
        ssh_exit=$?
        [[ $ssh_exit -ne 0 ]] && echo -e "\nCommand exited with code: ${ssh_exit}\n"

    # Not Verbose
    else
        [[ $OPT_QUIET -eq 0 ]] && printf ">>> %-10s (%s) : " "${ssh_host%%.*}" "$ssh_cmd"

        ${SSH} ${SSH_OPTS} -l $SSH_USER $ssh_host $ssh_cmd > ${ssh_log} 2>&1
        ssh_exit=$?

        if [[ $OPT_QUIET -eq 1 ]] ; then
            if [[ $ssh_exit -ne 0 ]] ; then
                printf ">>> %-10s : Exited with code %d\n" ${ssh_host%%.*} $ssh_exit >&2
            fi
        else
            echo "(Exit Code: ${ssh_exit})"
        fi
    fi

    # Remove empty log files
    [[ -s ${ssh_log} ]] || rm -f ${ssh_log}
done
