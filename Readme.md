# Raspberry Pi High Performance Computer Cluster

## Introduction

## Parts

- small microSD card

## Physical Assembly

## Preliminary Configuration

### Create a cluster.toml file

### Generate Setup Scripts

The `stage-1.py` script uses the `cluster.toml` file to generate several setup
scripts and a list of instructions. Recommend capturing the output because
there are quite a few steps and several can take some time.

```bash
python3 stage-1.py cluster.toml setup | tee instructions.txt
less instructions.txt
```

## working on network-boot.sh endgame

```bash
# set root password
systemd-nspawn --directory /image/pi5
passwd
logout

# configure compute node
systemd-nspawn --boot --directory /image/pi5 --bind=/srv/tftp:/boot







cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
root# cp -r /root/.ssh/ /image/pi5/root/
root# cp -r /boot/firmware/\* /srv/tftp

rsync -aAX /home/pi/.ssh/ /image/pi5/root/.ssh
cp -r /root/.ssh/ /image/pi5/root/

rsync -aAX /boot/ /srv/tftp
echo 'console=tty0 ip=dhcp root=/dev/nfs ro nfsroot=10.0.0.1:/image/pi5,vers=3,nolock panic=60 ipv6.disable=1 rootwait systemd.gpt_auto=no' > /srv/tftp/cmdline.txt

apt-get install -y systemd-container debootstrap
env $(grep VERSION_CODENAME /etc/os-release) debootstrap --include=dbus,libpam-systemd $VERSION_CODENAME /image/pi5




# set root password
systemd-nspawn --directory /image/pi5
passwd
logout

# configure compute node
systemd-nspawn --boot --directory /image/pi5 --bind=/srv/tftp:/boot

apt-get install -y initramfs-tools-core nfs-client

# Turnoff a few kernel modules not needed on a compute node
sed -i 's/MODULES=.*/MODULES=netboot/' /etc/initramfs-tools/initramfs.conf
cat >> /etc/modprobe.d/blacklist.conf<< EOF
blacklist brcmfmac
blacklist brcmutil
blacklist btbcm
blacklist hci_uart
EOF

# Setup ramdisk on compute nodes
echo ASYNCMOUNTNFS=no >> /etc/default/rcS
echo RAMTMP=yes >> /etc/default/tmpfs






##### INSIDE
echo "BOOT=nfs" >> /etc/ap-tools/initramfs.conf



#####
```

## old stuff 0

## old stuff 1

## old stuff 2

# Test DHCP

```bash
pi-login# sudo apt-get install tcpdump
pi-login# sudo tcpdump -i eth0

```

### Prepare Network Boot

The compute nodes are using DHCP to obtain an IP address and then are attempting to fetch files from `10.0.0.1` using tftp.
This section describes how to setup the compute node image and tftp.

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
root# cp -r /boot/firmware/\* /srv/tftp
root# echo 'console=tty0 ip=dhcp root=/dev/nfs ro nfsroot=10.0.0.1:/image/pi5,vers=3,nolock panic=60 ipv6.disable=1 rootwait systemd.gpt_auto=no' > /srv/tftp/cmdline.txt

root# journalctl --follow

# Plugin pi-001

pi-login#

````

## Slurm Setup

## Deploy OpenMPI

## OpenSHMEM

## Add nodes

```bash
sudoedit /etc/dhcp/dhcpd.conf
sudoedit /etc/hosts
sudo cp /etc/hosts /image/pi5/etc/hosts
````

## Notes

- Smaller microSD is better for dd clone to NVMe
- But, can we use the same method that we use to create the compute node image (if it works)

## References

- https://aoterodelaroza.github.io/devnotes/diskless-rpi-cluster/
- https://glmdev.medium.com/building-a-raspberry-pi-cluster-784f0df9afbd
- https://medium.com/@hghcomphys/building-slurm-hpc-cluster-with-raspberry-pis-step-by-step-guide-ae84a58692d5
- https://ben.akrin.com/automated-headless-pi-imaging/
- https://forums.raspberrypi.com/viewtopic.php?t=315395
