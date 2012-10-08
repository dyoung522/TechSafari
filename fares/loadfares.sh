#!/bin/bash

CD_DEV="/dev/cdrom"
LOG="${0%.*}.log"

DVD_START=0 # Start on this DVD (counting from 0)
DVD_END=6   # End at this DVD (counting from 0)

DVD=$DVD_START

while [[ $((DVD++)) -le $DVD_END ]] ; do
    DVD_FILE="fares.dvd${DVD}"

    if [[ -f ${DVD_FILE}.iso ]] ; then
        echo "${DVD_FILE}.iso already exists, skipping"
        continue
    fi

    echo -n "Please load DVD ${DVD} and press enter: " ; read
    echo -n "Reading DVD ${DVD}... "

    #dd bs=2048 if=$CD_DEV of=${DVD_FILE}.load conv=noerror status=noxfer >$LOG 2>&1
    dd if=$CD_DEV of=${DVD_FILE}.load status=noxfer >$LOG 2>&1
    if [[ $? -ne 0 ]] ; then
        echo "ERROR"
        cat $LOG
        mv ${DVD_FILE}.load ${DVD_FILE}.err
    else
        echo "OK"
        rm -f $LOG
        mv ${DVD_FILE}.load ${DVD_FILE}.iso
        [[ -f ${DVD_FILE}.err ]] && rm -f ${DVD_FILE}.err
    fi
    sleep 5; eject $CD_DEV
done
