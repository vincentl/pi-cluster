#!/bin/bash
#
# $1: name of IMG to mount and systemd-nspawn into
# $2: mount point (/mnt/$2)
#

function cleanup() {
    if [[ "$mpt" != "" ]] && [[ "$loopdev" != "" ]]
    then
        if [ -d /mnt/$mpt/boot/firmware ]
        then
            umount /mnt/$mpt/{boot/firmware,}
        else
            umount /mnt/$mpt/{boot,}
        fi
        losetup -d $loopdev
        [ "$mpt" != "sdm" ] && rm -rf /mnt/$mpt
        mpt=""
    fi
}

function errexit() {
    echo -e "$1"
    cleanup
    exit 1
}

function doexit() {
    cleanup
    exit 0
}

img="$1"
mpt="$2"
[ "$img" == "" ] && errexit "? Missing IMG filename"
[ "$mpt" == "" ] && mpt="sdm"
[ -f $img ] || errexit "? File '$img' cannot be accessed"
[ "$(which systemd-nspawn)" == "" ] && errexit "? sudo apt install systemd-container"
[ "$(which sdm)" != "" ] && sdm --ppart $img
trap "doexit" EXIT
loopdev=$(losetup --show -P -f $img)
mkdir -p /mnt/$mpt/
mount -v ${loopdev}p2 /mnt/$mpt
if [ -d /mnt/$mpt/boot/firmware ]
then
    mount -v ${loopdev}p1 /mnt/$mpt/boot/firmware
else
    mount -v ${loopdev}p1 /mnt/$mpt/boot
fi
systemd-nspawn --directory /mnt/$mpt < $(tty)
sts=$?
if [ $sts -eq 127 ]
then
    echo "? Cannot nspawn into 32-bit IMG on Pi5 16KB page system"
fi
trap EXIT
if [ -d /mnt/$mpt/boot/firmware ]
then
    umount /mnt/$mpt/{boot/firmware,}
else
    umount /mnt/$mpt/{boot,}
fi
losetup -d $loopdev