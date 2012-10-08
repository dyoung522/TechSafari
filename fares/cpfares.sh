#!/bin/bash

[[ $UID -ne 0 ]] && echo "Please run this program as root." && exit 1

DVD_START=0
DVD_END=6

COUNT=0
COUNT_TOT=52

STATE_LAST=""
FARES_BASE="/data/fares"
MYBASE=$PWD

for DVD_DIR in 200??? ; do
    echo "Copying files from $DVD_DIR"
    cd $DVD_DIR

    FARES_DIR="$FARES_BASE/$DVD_DIR/zips"

#    if [[ -d $FARES_DIR && -n "$(ls $FARES_DIR)" ]] ; then
#        echo "$FARES_DIR already exists, skipping load"
#        cd $MYBASE ; continue
#    fi
    [[ ! -d $FARES_DIR ]] && mkdir -p $FARES_DIR

    DVD=$DVD_START
    while [[ $((DVD++)) -le $DVD_END ]] ; do
        ISO="fares.dvd${DVD}.iso"
        [[ -f ${ISO} ]] && continue
        echo "${ISO} does not exist, please check the input files!"
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
        mount -o loop $ISO $MNT_DIR
        if [[ $? -ne 0 ]] ; then
            echo "Problem mounting ${ISO} - $!";
            cd $MYBASE ; continue
        fi

        echo -n "Copying files... "
        rsync -av --progress ${MNT_DIR}/ $FARES_DIR/
        echo "Complete"
        umount ${MNT_DIR}
    done

    rmdir ${MNT_DIR}
    cd $MYBASE
done


