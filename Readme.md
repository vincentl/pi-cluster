# Raspberry Pi High Performance Computer Cluster

## Introduction

## Parts

## Physical Assembly

## Preliminary Configuration

- swap space
- cgroups

- Create ssh keys for cluster
- Run stage-1 script
-

- journalctl -f

## Login or Head node

### Bring Up

Start at [Raspberry Pi Software](https://www.raspberrypi.com/software/) and download the **Raspberry Pi Imager**. Run the imager and create a base microSD card with the `Raspberry Pi OS Lite (64-bit)` OS.

- Click the `Edit Settings` options and
  - In the `General` tab
    - Set hostname: `pi-login`
    - Set username (`pi`) and a password
    - Configure the wireless LAN
    - Set locale
  - In the `Services` tab
    - Enable SSH
    - Run ssh-keygen if you do not already have an ssh key
- Eject the microSSD card & load into the Raspberry Pi login node
- Boot the node
- Try to ssh to the node with

```bash
ssh pi@pi-login
```

### Setup NVMe

- Configure the NVMe device to have a boot partition and a root partition with Raspberry Pi OS.

```bash
# Turn on PCIe & reboot
sudo bash -c 'cat >> /boot/firmware/config.txt<< EOF
dtparam=nvme
EOF'
sudo reboot
# ssh once node reboots
ssh pi@pi-login
# Enumerate PCIe devices and look for a Non-Volatile memory controller
sudo lspci
# Check the nvme exists
ls /dev/nvme0n1
# Copy the image from the running SSD card onto the NVMe device (destroys all data on the device)
sudo dd status=progress bs=4096 if=/dev/mmcblk0 of=/dev/nvme0n1
```

- Resize the second partition to match the size of the NVMe device

```bash
sudo parted /dev/nvme0n1
(parted) unit chs
(parted) print
BIOS cylinder,head,sector geometry: 124034,128,63.  Each cylinder is 4129kB.
Partition Table: msdos
Disk Flags:

Number  Start    End          Type     File system  Flags
 1      1,2,2    131,6,5      primary  fat32        lba
 2      131,6,6  15468,24,23  primary  ext4
(parted) rm 2
(parted) mkpart primary 131,6,6 124034,79,62
(parted) print
(parted)

sudo e2fsck -f /dev/nvme0n1p2
sudo resize2fs /dev/nvme0n1p2
sudo tune2fs -c 1 /dev/nvme0n1p2

sudo raspi-config
# Menu 6 >  Boot Order > B2 > Finish (ESC)

sudo shutdown
```

- Remove power, remove the microSD card, reconnect power
- Update OS

```bash
sudo apt update
sudo apt full-upgrade
```

## Compute Node Setup

- Boot each compute node using the microSD card and get the serial number & MAC

```bash
pi-001# ip addr show eth0
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 2c:cf:67:c6:7d:83 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::9cca:8589:a2e:27a6/64 scope link noprefixroute
       valid_lft forever preferred_lft forever
pi-001# sudo raspi-config
# Menu 6 >  Boot Order > B3 > Finish (ESC)

pi-002# ip addr show eth0
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 2c:cf:67:c6:7d:52 brd ff:ff:ff:ff:ff:ff
    inet6 fe80::b13:7113:1a78:16f7/64 scope link tentative noprefixroute
       valid_lft forever preferred_lft forever
```

### Configure the local (wired) network

```bash
pi-login# /sbin/ifconfig
# Look for ethernet interface, likely eth0

pi-login# sudo apt-get autoremove --purge ifupdown
pi-login# sudo apt-get install ifupdown
pi-login# sudo bash -c 'cat >> /etc/network/interfaces.d/eth0<< EOF
allow-hotplug eth0
iface eth0 inet static
  address 10.0.0.1
  netmask 255.0.0.0
EOF'
pi-login# (as sudo) echo "wifi.powersave=off" >> /etc/NetworkManager/conf.d/00-wifi-power.conf
pi-login# sudo reboot
```

### Install and configure the DHCP server

```bash
pi-login# sudo apt-get install isc-dhcp-server
pi-login# sudoedit /etc/default/isc-dhcp-server
INTERFACESv4="eth0"
INTERFACESv6=""
pi-login# sudoedit /etc/dhcp/dhcpd.conf
default-lease-time 600;
max-lease-time 7200;
ddns-update-style none;
use-host-decl-names on;

subnet 10.0.0.0 netmask 255.0.0.0 {
  option routers 10.0.0.1;
  group {
    option tftp-server-name "10.0.0.1"; # option 66
    option vendor-class-identifier "PXEClient"; # option 60
    option vendor-encapsulated-options "Raspberry Pi Boot"; # option 43
    filename "pxelinux.0";
    host pi-001 {
      hardware ethernet 2c:cf:67:c6:7d:83;
      fixed-address 10.0.1.1;
      option host-name "pi-001";
      option root-path "10.0.0.1:/image/pi5,v3,tcp,hard,rsize=8192,wsize=8192";
    }
    host pi-002 {
      hardware ethernet 2c:cf:67:c6:7d:52;
      fixed-address 10.0.1.2;
      option host-name "pi-002";
      option root-path "10.0.0.1:/image/pi5,v3,tcp,hard,rsize=8192,wsize=8192";
    }
  }
}

pi-login# sudo systemctl start isc-dhcp-server.service

# Test DHCP
pi-login# sudo apt-get install tcpdump
pi-login# sudo tcpdump -i eth0
# Plugin one of the compute nodes and wait a few seconds
20:56:10.532633 IP localhost.bootpc > broadcast.bootps: BOOTP/DHCP, Request from 2c:cf:67:c6:7d:83 (oui Unknown), length 322
20:56:10.532757 IP 10.0.0.1.bootps > 10.0.1.1.bootpc: BOOTP/DHCP, Reply, length 308
20:56:10.563771 IP localhost.bootpc > broadcast.bootps: BOOTP/DHCP, Request from 2c:cf:67:c6:7d:83 (oui Unknown), length 309
20:56:10.563836 IP 10.0.0.1.bootps > 10.0.1.1.bootpc: BOOTP/DHCP, Reply, length 371
20:56:10.637672 ARP, Request who-has 10.0.0.1 tell 10.0.1.1, length 46
20:56:10.637686 ARP, Reply 10.0.0.1 is-at 2c:cf:67:7f:71:36 (oui Unknown), length 28
20:56:10.666620 IP 10.0.1.1.52142 > 10.0.0.1.tftp: TFTP, length 49, RRQ "8baee41e/config.txt" octet tsize 0 blksize 1468
20:56:10.666637 IP 10.0.0.1 > 10.0.1.1: ICMP 10.0.0.1 udp port tftp unreachable, length 85
```

### Prepare Network Boot

The compute nodes are using DHCP to obtain an IP address and then are attempting to fetch files from `10.0.0.1` using tftp.
This section describes how to setup the compute node image and tftp.

```bash
pi-login# sudo mkdir /image
pi-login# sudo chmod go-rX /image/
pi-login# sudo apt-get install debootstrap
# look in /etc/apt/sources.list for the release name (bookworm in this case)
pi-login# sudo debootstrap bookworm /image/pi5
pi-login# sudo cp /etc/apt/sources.list /image/pi5/etc/apt/sources.list

pi-login# sudoedit /etc/hosts
127.0.0.1	localhost
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters

127.0.1.1	pi-login
10.0.0.1        pi-login
10.0.1.1        pi-001
10.0.1.2        pi-002
pi-login# sudo cp /etc/hosts /image/pi5/etc/hosts

pi-login# cat > enter-chroot.sh<< EOF
#!/bin/bash
sudo mount --rbind /dev /image/pi5/dev
sudo mount --make-rslave /image/pi5/dev
sudo mount -t proc /proc /image/pi5/proc
sudo mount --rbind /sys /image/pi5/sys
sudo mount --make-rslave /image/pi5/sys
sudo mount --rbind /tmp /image/pi5/tmp
EOF
pi-login# chmod 750 enter-chroot.sh
pi-login# ./enter-chroot.sh
pi-login# dpkg --get-selections | grep -E 'linux-.*-v[0-9]+|firmware' | cut -f1 | sed 's/^/apt-get install -y /' > /tmp/packages.sh
pi-login# sudo chroot /image/pi5
chroot# apt-get install locales
chroot# locale-gen en_US.UTF-8
chroot# dpkg-reconfigure locales
# Select the local, enter, select the local again
chroot# apt-get update
chroot# apt-get full-upgrade
chroot# bash /tmp/packages.sh
chroot# apt-get install -y openssh-client openssh-server xz-utils
chroot# cat >> /image/pi5/etc/modprobe.d/blacklist.conf<< EOF
blacklist brcmfmac
blacklist brcmutil
blacklist btbcm
blacklist hci_uart
EOF
chroot# nano /etc/initramfs-tools/initramfs.conf
MODULES=netboot
BUSYBOX=y
KEYMAP=n
COMPRESS=xz
DEVICE=
NFSROOT=auto
BOOT=nfs
chroot# update-initramfs -u
chroot# echo ASYNCMOUNTNFS=no >> /etc/default/rcS
chroot# echo RAMTMP=yes >> /etc/default/tmpfs
chroot# nano /etc/ssh/sshd_config
PermitRootLogin prohibit-password
TCPKeepAlive yes

chroot# exit

pi-login# sudo mkdir /srv/tftp
pi-login# sudo apt-get install -y tftpd-hpa tftp-hpa
pi-login# sudo systemctl restart tftpd-hpa
pi-login# uname -a | sudo tee /srv/tftp/test
pi-login# tftp 10.0.0.1
tftp> get test
tftp> quit
pi-login# cat test && rm test
pi-login# sudo bash
root# ssh-keygen
root# cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
root# cp -r /root/.ssh/ /image/pi5/root/
root# cp -r /boot/firmware/* /srv/tftp
root# echo 'console=tty0 ip=dhcp root=/dev/nfs ro nfsroot=10.0.0.1:/image/pi5,vers=3,nolock panic=60 ipv6.disable=1 rootwait systemd.gpt_auto=no' > /srv/tftp/cmdline.txt
root# journalctl --follow
# Plugin pi-001
pi-login#

```

## Slurm Setup

## Deploy OpenMPI

## OpenSHMEM

## Add nodes

```bash
sudoedit /etc/dhcp/dhcpd.conf
sudoedit /etc/hosts
sudo cp /etc/hosts /image/pi5/etc/hosts
```

## Notes

- Smaller microSD is better for dd clone to NVMe
- But, can we use the same method that we use to create the compute node image (if it works)

## References

- https://aoterodelaroza.github.io/devnotes/diskless-rpi-cluster/
- https://glmdev.medium.com/building-a-raspberry-pi-cluster-784f0df9afbd
- https://medium.com/@hghcomphys/building-slurm-hpc-cluster-with-raspberry-pis-step-by-step-guide-ae84a58692d5
- https://ben.akrin.com/automated-headless-pi-imaging/
- https://forums.raspberrypi.com/viewtopic.php?t=315395
