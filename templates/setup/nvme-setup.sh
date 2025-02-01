#!/bin/bash

apt update
apt full-upgrade -y
apt install -y partclone

# PCIe External connector
path=/boot/firmware/config.txt
if ! grep -q "dtparam=nvme" $path; then
    echo "Adding nvme parameter to $path"
    echo "dtparam=nvme" >> $path
    echo "Rebooting..."
    sleep 3
    reboot
fi

# Format NVMe & Install OS
# get NVMe device + confirmation
microsd=/dev/$(basename $(df | grep /boot/firmware | cut -d' ' -f 1) p1)
nvme=/dev/$(basename $(echo /sys/block/nvme* | cut -d ' ' -f 1))

read -p "Completely overwrite ${nvme} with ${microsd} [Y or N]? " -n 1 -r
echo 
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Aborting..."
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

# Create partitions
parted ${nvme} --script -- mklabel gpt \
  mkpart primary fat32 1MiB 513MiB \
  set 1 esp on \
  mkpart primary ext4 513MiB 100%

# Copy running microSD bytes to NVMe device
umount ${microsd}p1
partclone.vfat -b -s ${microsd}p1 -o ${nvme}p1
partclone.ext4 -F -b -s ${microsd}p2 -o ${nvme}p2

# Resize the root partition and clean up
parted ${nvme} resizepart 2 100%
fsck -y ${nvme}p1
e2fsck -y -f ${nvme}p2
resize2fs ${nvme}p2

# Patch up fstab with correct UUIDs
mount ${nvme}p2 /mnt
mount ${nvme}p1 /mnt/boot
sed -Ei 's|^[^ ]*(.*vfat)|PARTUUID='$(blkid -o value -s PARTUUID ${nvme}p1)'\1|' /mnt/etc/fstab 
sed -Ei 's|^[^ ]*(.*ext4)|PARTUUID='$(blkid -o value -s PARTUUID ${nvme}p2)'\1|' /mnt/etc/fstab

# And cmdline.txt
sed -Ei 's|root=PARTUUID=[^ ]* |root=PARTUUID='$(blkid -o value -s PARTUUID ${nvme}p2)' |' /mnt/boot/cmdline.txt
