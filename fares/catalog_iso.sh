#!/bin/bash

die() {
    echo $*
    exit 1
}

for ISO in *.iso
do
    echo "Cataloging $ISO"
    mount -o loop $ISO /mnt/cdrom || die "Unable to mount $ISO"
    ls -l /mnt/cdrom > $ISO.catalog
    umount /mnt/cdrom || die "Unable to umount /mnt/cdrom"
done
