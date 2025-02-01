#!/bin/bash

# Check the OS is updated
rm -rf /var/lib/apt/lists/*
apt update
apt full-upgrade -y
apt install -y tcpdump

# Deactivate wifi power management on head node to improve responsiveness over ssh
if [ ! -f /etc/systemd/system/wlan0pwr.service ]; then
    echo "Disabling wifi power management"
    cat >> /etc/systemd/system/wlan0pwr.service<< EOF
[Unit]
Description=Disable wlan0 powersave
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/sbin/iw wlan0 set power_save off

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable wlan0pwr
fi

# Enable wired ethernet
eth=$(ifconfig | grep -E "^eth" | cut -d: -f1)
if [ ! -f /etc/network/interfaces.d/${eth} ]; then
    echo "Enabling wired ethernet"
    apt autoremove --purge ifupdown
    apt install -y ifupdown

    cat >> /etc/network/interfaces.d/${eth}<< EOF
allow-hotplug ${eth}
iface ${eth} inet static
  address 10.0.0.1
  netmask 255.0.0.0
EOF

    echo "Rebooting..."
    sleep 3
    reboot
fi

# update hosts
cp hosts /etc/hosts

# turn on dhcpd
if ! $(dpkg-query --status isc-dhcp-server 2>&1 | grep -q "Status: install ok installed"); then
    apt install -y isc-dhcp-server
    cp isc-dhcp-server /etc/default/
    cp dhcpd.conf /etc/dhcp/
    systemctl start isc-dhcp-server.service
fi

# turn on tftp
if ! $(dpkg-query --status tftpd-hpa 2>&1 | grep -q "Status: install ok installed"); then
    apt install -y tftpd-hpa tftp-hpa
    systemctl restart tftpd-hpa
fi

# Stage /boot
if [ -z "$(ls -A /srv/tftp 2>/dev/null)" ]; then 
    rsync -aAX /boot/ /srv/tftp/
    echo 'console=tty0 ip=dhcp root=/dev/nfs ro nfsroot=10.0.0.1:/image/pi5,vers=3,nolock panic=60 ipv6.disable=1 rootwait systemd.gpt_auto=no cgroup_enable=memory cgroup_memory=1 swapaccount=1' > /srv/tftp/cmdline.txt
fi

# Configure compute node image
if [ ! -d /image/pi5 || -z "$(ls -A /image/pi5 2>/dev/null)" ]; then
    mkdir -p /image/pi5
    read -rp "Insert microSD card and press Enter to continue..."
    mkdir -p /mnt/microsd
    mount /dev/mmcblk0p2 /mnt/microsd
    mount /dev/mmcblk0p1 /mnt/microsd/boot

    rsync -aAXv /mnt/microsd/boot/ /image/pi5/boot/
    rsync -aAXv /mnt/microsd/ /image/pi5/

    umount /mnt/microsd/boot
    umount /mnt/microsd

    # Turnoff a few kernel modules not needed on a compute node
    sed -i 's/MODULES=.*/MODULES=netboot/' /image/pi5/etc/initramfs-tools/initramfs.conf
    cat >> /image/pi5/etc/modprobe.d/blacklist.conf<< EOF
blacklist brcmfmac
blacklist brcmutil
blacklist btbcm
blacklist hci_uart
EOF

    # Setup ramdisk on compute nodes
    echo ASYNCMOUNTNFS=no >> /image/pi5/etc/default/rcS
    echo RAMTMP=yes >> /image/pi5/etc/default/tmpfs

    # Enable auto root login for nspawn
    if [ ! -f /image/pi5/etc/systemd/system/console-getty.service.d/autologin.conf ]; then
        mkdir -p /image/pi5/etc/systemd/system/console-getty.service.d
        cat >| /image/pi5/etc/systemd/system/console-getty.service.d/autologin.conf<< EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noclear --autologin root --keep-baud console 115200,38400,9600 $TERM
EOF
    fi

    # Turnoff rpcbind and remove hostname
    rm /image/pi5/etc/systemd/system/multi-user.target.wants/rpcbind.service
    rm /image/pi5/etc/systemd/system/sockets.target.wants/rpcbind.socket
    rm /image/pi5/etc/hostname

    # Compute Node fstab
    cat >/image/pi5/etc/fstab<< EOF
proc                     /proc           proc     defaults     0  0
10.0.0.1:/image/pi5      /               nfs      defaults,ro  0  0
10.0.0.1:/home           /home           nfs      defaults,rw  0  0
cgroup                   /sys/fs/cgroup  cgroup2  defaults     0  0
EOF

fi

# head node nfs
apt install -y nfs-kernel-server nfs-common
if ! grep -q /image/pi5 /etc/exports; then
    cat >> /etc/exports<< EOF
/image/pi5  10.0.1.0/24(ro,sync,no_root_squash,no_subtree_check)
/home       10.0.1.0/24(rw,sync,no_root_squash,no_subtree_check)
EOF
fi
exportfs -rv



