#!/bin/bash

# Download OS image
url=$(wget -O /dev/null -o - --max-redirect=0 https://downloads.raspberrypi.org/raspios_lite_arm64_latest 2>/dev/null| sed -n "s/^Location: \(.*\) \[following\]$/\1/p")
img=$(basename $url .xz)
if [ ! -f $img ]; then
    echo "Downloading: $url"
    wget $url
    unxz $img.xz
fi

# PCIe External connector
path=/boot/firmware/config.txt
if ! grep -q "dtparam=nvme" $path; then
    echo "Adding nvme parameter to $path"
    echo "dtparam=nvme" | sudo tee -a $path
    echo "Rebooting..."
    sleep 3
    sudo reboot
fi

# Get sdm image manager
if command -v sdm >/dev/null 2>&1; then
  echo "sdm already installed"
else
  echo "Installing sdm"
  curl -L https://raw.githubusercontent.com/gitbls/sdm/master/EZsdmInstaller | bash
fi

# Setup NVMe OS

# get NVMe device + confirmation
nvme=$(echo /sys/block/nvme* | cut -d ' ' -f 1)
nvme=/dev/$(basename $nvme)

read -p "Completely overwrite ${nvme} [Y or N]? " -n 1 -r
echo 
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo "Aborting..."
    [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1
fi

# Setup custom image file with hostname, user, locale, ssh public key
custom="custom-$img"
cp $img $custom

sudo sdm --customize $custom \
  --customize \
  --plugin user:"adduser={{cluster.user}}" \
  --plugin disables:piwiz \
  --plugin L10n:host \
  --plugin copyfile:"from=/etc/NetworkManager/system-connections/preconfigured.nmconnection|to=/etc/NetworkManager/system-connections/" \
  --plugin copydir:"from=/home/{{cluster.user}}/.ssh|to=/home/{{cluster.user}}" \
  --restart

sudo sdm --burn $nvme \
  --hostname {{cluster.head-node}} \
  --expand-root \
  --regen-ssh-host-keys \
  $custom
