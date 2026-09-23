#!/bin/bash

# Check the OS is updated
rm -rf /var/lib/apt/lists/*
apt update
apt full-upgrade -y
apt install -y tcpdump

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

# setup time sync server
apt install -y ntp

# Stage /boot
if [ -z "$(ls -A /srv/tftp 2>/dev/null)" ]; then 
    rsync -aAX /boot/ /srv/tftp/
    echo 'console=tty0 ip=dhcp root=/dev/nfs ro nfsroot=10.0.0.1:/image/pi5,vers=3,nolock panic=60 ipv6.disable=1 rootwait systemd.gpt_auto=no cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 systemd.unified_cgroup_hierarchy=1 swapaccount=1' > /srv/tftp/firmware/cmdline.txt
fi

# Configure compute node image
if [[ ! -d /image/pi5 || -z "$(ls -A /image/pi5 2>/dev/null)" ]]; then
    mkdir -p /image/pi5
    read -rp "Insert microSD card and press Enter to continue..."
    mkdir -p /mnt/microsd
    mount /dev/mmcblk0p2 /mnt/microsd
    mount /dev/mmcblk0p1 /mnt/microsd/boot

    rsync -aAX --info=progress2 /mnt/microsd/boot/ /image/pi5/boot/
    rsync -aAX --info=progress2 /mnt/microsd/ /image/pi5/

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

    # Ensure mtab is up to date on network boot with read-only /etc
    rm -f /image/pi5/etc/mtab
    ln -s /proc/self/mounts /image/pi5/etc/mtab
    sed -i 's/^L[+]/#L+/' /image/pi5/usr/lib/tmpfiles.d/debian.conf

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
# <file system>        <mount point>    <type>  <options>       <dump>  <pass>
10.0.0.1:/image/pi5    /                nfs     tcp,nolock,ro,v4   1       1
10.0.0.1:/opt          /opt             nfs     tcp,nolock,ro,v4   0       0
proc                   /proc            proc    defaults           0       0
none                   /tmp             tmpfs   defaults           0       0
none                   /media           tmpfs   defaults           0       0
none                   /var             tmpfs   defaults           0       0
none                   /run             tmpfs   defaults           0       0
10.0.0.1:/home         /home            nfs     tcp,nolock,rw,v4   0       0
cgroup                 /sys/fs/cgroup   cgroup2 defaults           0       0
EOF

    # Point timesync to head node
    echo "FallbackNTP=10.0.0.1" >> /image/pi5/etc/systemd/timesyncd.conf
fi

# head node nfs
apt install -y nfs-kernel-server nfs-common
if ! grep -q /image/pi5 /etc/exports; then
    cat >> /etc/exports<< EOF
/image/pi5  10.0.1.0/24(ro,sync,no_root_squash,no_subtree_check)
/opt        10.0.1.0/24(ro,sync,no_root_squash,no_subtree_check)
/home       10.0.1.0/24(rw,sync,no_root_squash,no_subtree_check)
EOF
fi
exportfs -rv



