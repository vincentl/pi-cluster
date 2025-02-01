#!/bin/bash

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

# Get the nvme device
nvme=/dev/$(basename $(echo /sys/block/nvme* | cut -d ' ' -f 1))

# Confirmation
read -p "Completely overwrite ${nvme} [Y or N]? " -n 1 -r
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

# Format partitions
mkfs.vfat -F32 ${nvme}p1
mkfs.ext4 -F ${nvme}p2

# Mount
mount ${nvme}p2 /mnt
mkdir -p /mnt/boot
mount ${nvme}p1 /mnt/boot

# Install debootstrap and install vanilla bookworm
apt update
apt install -y debootstrap systemd-container

debootstrap --arch=arm64 bookworm /mnt http://deb.debian.org/debian/


# Setup apt in container to use raspberry packages too
cp /etc/apt/sources.list /mnt/etc/apt/sources.list
cp /etc/apt/sources.list.d/raspi.list /mnt/etc/apt/sources.list.d/raspi.list
cp /etc/apt/trusted.gpg /mnt/etc/apt/trusted.gpg
cp /etc/apt/trusted.gpg.d/raspberrypi-archive-stable.gpg /mnt/etc/apt/trusted.gpg.d/raspberrypi-archive-stable.gpg

# Get list of installed packages on microSD
apt list --installed 2>/dev/null | grep '/' | cut -f1 -d '/' > /mnt/root/packages.list 

# Install packages - human interaction for one package
systemd-nspawn -D /mnt

apt update
for i in $(cat packages.list); do apt install -y $i 2>&1 | tee -a packages.log; done
exit

# Copy mounts, users, groups, wifi setup, etc from microSD to NVMe
objects=(
    /fstab
    /default/
    /passwd
    /shadow
    /group
    /gshadow
    /subgid
    /subuid
    /timezone
    /apt/apt.conf.d/
    /ssh/
    /profile.d/
    /init.d/
    /hosts
    /kernel-img.conf
    /NetworkManager/system-connections/
    /systemd/
)
for object in "${objects[@]}"; do
    rsync -avzAX --delete /etc${object} /mnt/etc/${object}
done

# cmdline.txt
rsync -avzAX /boot/firmware/cmdline.txt /mnt/boot/firmware/cmdline.txt



# START HERE

# 2. Figure out how to script inside the container

echo "/dev/nvme0n1p2 /      ext4    defaults,noatime  0 1" >> /etc/fstab
echo "/dev/nvme0n1p1 /boot  vfat    defaults,noatime  0 2" >> /etc/fstab





# STILL WRONG - /etc/apt/apt.conf.d/20listchanges 
# cmdline.txt wrong too

rsync --archive --acls --xattrs /etc/apt/ /mnt/etc/apt

systemd-nspawn -D /mnt

# NEED TO SCRIPT THIS INSIDE THE CONTAINER

apt install -y wget gnupg2

mkdir -m 0755 -p /etc/apt/keyrings/
wget https://archive.raspbian.org/raspbian.public.key -O - | gpg --dearmor -o /etc/apt/keyrings/raspbian.public.key



cat >> /etc/apt/sources.list<< EOF
deb http://archive.raspberrypi.org/debian bookworm main
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
EOF


apt update
apt install -y linux-image-arm64 raspberrypi-bootloader raspberrypi-kernel
apt install -y initramfs-tools firmware-linux


echo "/dev/nvme0n1p2 /      ext4    defaults,noatime  0 1" > /etc/fstab
echo "/dev/nvme0n1p1 /boot  vfat    defaults,noatime  0 2" >> /etc/fstab

exit

rsync --existing --archive --acls --xattrs /etc/ /mnt/etc

umount -R /mnt

shutdown now


# get NVMe device + confirmation
microsd=/dev/$(basename $(df | grep /boot | cut -d' ' -f 1) p1)
nvme=/dev/$(basename $(echo /sys/block/nvme* | cut -d ' ' -f 1))

read -p "Completely overwrite ${nvme} with ${microsd} [Y or N]? " -n 1 -r
echo 
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Aborting..."
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

# Copy running microSD bytes to NVMe device 
dd status=progress bs=4k if=${microsd} of=${nvme}

# Resize the root partition and clean up
parted ${nvme} resizepart 2 100%
fsck -y ${nvme}p1
e2fsck -y -f ${nvme}p2
resize2fs ${nvme}p2
