#!/bin/bash

[[ $UID -ne 0 ]] && echo "Please run this program as root." && exit 1

DVD_START=0
DVD_END=6

COUNT=0
COUNT_TOT=52

STATE_LAST=""

DVD=$DVD_START
while [[ $((DVD++)) -le $DVD_END ]] ; do
    ISO="fares.dvd${DVD}.iso"

    [[ -f ${ISO} ]] && continue

    echo "${ISO} does not exist, please check the input files!"
    exit 1
done

echo "Input files OK"

MNT_DIR="./DVD"
[[ ! -d $MNT_DIR ]] && mkdir $MNT_DIR

LOAD_DIR="./LOAD"
[[ ! -d $LOAD_DIR ]] && mkdir $LOAD_DIR

DVD=$DVD_START
while [[ $((DVD++)) -le $DVD_END ]] ; do
    ISO="fares.dvd${DVD}.iso"

    echo "Mounting $ISO."
    mount -o loop $ISO $MNT_DIR || \
        (echo "Problem mounting ${ISO} - $!" && exit 1)

    echo -n "Building TXT files... "
    for INFILE in ${MNT_DIR}/*.zip ; do
        OUTFILE=${INFILE##*/}
        STATE=$(echo ${OUTFILE:0:2} | tr [a-z] [A-Z])
        OUTFILE="${LOAD_DIR}/${STATE}.txt.gz"

        if [[ $STATE_LAST != $STATE ]] ; then
            ((COUNT++))

            echo -n "$STATE "
            STATE_LAST=$STATE

            touch $OUTFILE
        fi

        zcat -cd $INFILE | gzip >> ./$OUTFILE
        if [[ $? -ne 0 ]] ; then
            echo "Error in ${INFILE}"
            umount ${MNT_DIR}
            exit 1
        fi
    done
    echo "Complete"
    umount ${MNT_DIR}
done

rmdir ${MNT_DIR}

if [[ $COUNT -lt $COUNT_TOT ]] ; then
    echo "We're missing files!"
    exit 1
else
    echo "Complete"
fi

echo "The next step is to run xferfares.sh <YYYYMM>"

