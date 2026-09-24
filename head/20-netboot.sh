#!/bin/bash
# Turn the head node into the compute nodes' boot server: network, DHCP and TFTP, NFS, time, image.
# Runs on the head node, booted from NVMe: sudo bash pi-cluster/head/20-netboot.sh
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need_root
[[ $(root_source) != /dev/mmcblk* ]] || die "/ is still on the microSD card; run 10-nvme.sh first"

image_run() { bash "$REPO/head/image-run.sh" "$@"; }
image_has() {
    [[ $(dpkg-query --admindir="$IMAGE/var/lib/dpkg" -W -f '${db:Status-Status}' "$1" 2>/dev/null) == installed ]]
}

# 1. eth0 gets HEAD_IP on the cluster network: no gateway, no IPv6, no reboot.
if [[ $(nmcli -g ipv4.addresses connection show pi-cluster 2>/dev/null) != "$HEAD_IP/$PREFIX" ]]; then
    for addr in "$HEAD_IP" "$(node_ip 1)" "$(node_ip 254)"; do
        route=$(ip -o route get "$addr" 2>/dev/null) || continue
        [[ $route == local* || $route == *" via "* || $route == *" dev eth0 "* ]] ||
            die "your wifi network already uses $addr; choose other cluster addresses in cluster.env"
    done
    nmcli connection delete pi-cluster >/dev/null 2>&1 || true
    nmcli connection add type ethernet ifname eth0 con-name pi-cluster \
        ipv4.method manual ipv4.addresses "$HEAD_IP/$PREFIX" ipv4.never-default yes \
        ipv6.method disabled connection.autoconnect-priority 100
    nmcli connection up pi-cluster
fi

# 2. Packages: DHCP and TFTP, NFS server, time server, packet capture, image tools, nspawn.
need_packages dnsmasq nfs-kernel-server chrony tcpdump xz-utils curl rsync systemd-container

# 3. The compute image: the current Raspberry Pi OS Lite, checked and unpacked to $IMAGE.
if [[ ! -e $IMAGE/etc/os-release ]]; then
    url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$OS_IMAGE_URL")
    xz=$CACHE/${url##*/}
    sums=$(curl -fsSL "$url.sha256")
    mkdir -p "$CACHE" "$(dirname "$IMAGE")"
    if ! (cd "$CACHE" && sha256sum -c --status <<< "$sums" 2>/dev/null); then
        log "downloading $url"
        curl -fL -C - -o "$xz" "$url" || die "download failed; if it keeps failing, delete $xz and run again"
        (cd "$CACHE" && sha256sum -c <<< "$sums") || die "$xz does not match its checksum; delete it and run again"
    fi
    log "unpacking ${xz##*/}"
    xz -d -k -f -T0 "$xz"
    img=${xz%.xz}
    mnt=$(mktemp -d)
    loop=$(losetup -P -r --show -f "$img")
    trap 'umount -R "$mnt" 2>/dev/null || true; losetup -d "$loop"; rmdir "$mnt"' EXIT
    udevadm settle
    mount -o ro "${loop}p2" "$mnt"
    mount -o ro "${loop}p1" "$mnt/boot/firmware"
    log "copying the image to $IMAGE; this takes a few minutes"
    rsync -aHAX --numeric-ids --info=progress2 "$mnt/" "$IMAGE.new/"
    umount -R "$mnt"
    losetup -d "$loop"
    rmdir "$mnt"
    trap - EXIT
    mv "$IMAGE.new" "$IMAGE"
    rm -f "$img"
fi

# 4a. Image accounts: the head node's users and passwords, copied before any package adds users.
for f in passwd shadow group gshadow; do
    cmp -s "/etc/$f" "$IMAGE/etc/$f" || { cp -p "/etc/$f" "$IMAGE/etc/$f"; log "copied /etc/$f into the image"; }
done

# 4b. Image initramfs: NFS and network drivers (the image's MODULES=dep fails inside nspawn); no wifi or bluetooth.
put "$IMAGE/etc/initramfs-tools/conf.d/pi-cluster" <<EOF
$GENERATED
MODULES=netboot
EOF
put "$IMAGE/etc/modprobe.d/pi-cluster-blacklist.conf" <<EOF
$GENERATED
blacklist brcmfmac
blacklist brcmutil
blacklist btbcm
blacklist hci_uart
EOF

# 4c. Package scripts run inside nspawn must not start services on the head node's network.
put "$IMAGE/usr/sbin/policy-rc.d" 755 <<EOF
#!/bin/sh
$GENERATED
exit 101
EOF

# 4d. Boot over the network with a read-only NFS root, the rest mounted by the node (before any initramfs build reads fstab).
put "$IMAGE/boot/firmware/cmdline.txt" <<EOF
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=$HEAD_IP:$IMAGE,vers=3 ro ip=dhcp panic=60 ipv6.disable=1 cgroup_enable=memory
EOF
put "$IMAGE/etc/fstab" <<EOF
$GENERATED
# / is the NFS root, mounted read-only from cmdline.txt; systemd mounts /tmp, /run and /proc itself.
$HEAD_IP:/home  /home   nfs    defaults   0  0
$HEAD_IP:/opt   /opt    nfs    ro         0  0
tmpfs           /var    tmpfs  mode=0755  0  0
tmpfs           /media  tmpfs  mode=0755  0  0
EOF

# 4e. The NFS client, which mounts /home and /opt on the nodes.
if ! image_has nfs-common; then
    image_run apt-get update
    image_run env DEBIAN_FRONTEND=noninteractive apt-get install -y nfs-common
fi

# 4f. Rebuild the initramfs if it is older than its settings.
initramfs=$IMAGE/boot/firmware/initramfs_2712
if [[ ! $initramfs -nt $IMAGE/etc/initramfs-tools/conf.d/pi-cluster ||
      ! $initramfs -nt $IMAGE/etc/modprobe.d/pi-cluster-blacklist.conf ]]; then
    image_run update-initramfs -u -k all
fi

# 4g. Names: DHCP gives each node its hostname, /etc/hosts lists the cluster, and there is no DNS.
if [[ -e $IMAGE/etc/hostname ]]; then
    rm "$IMAGE/etc/hostname"
    log "removed the image's /etc/hostname"
fi
put "$IMAGE/etc/hosts" < <(hosts_file)
put "$IMAGE/etc/resolv.conf" <<EOF
$GENERATED
# Compute nodes have no DNS server; every cluster name is in /etc/hosts.
EOF

# 4h. Create Debian's tmpfiles links (/etc/mtab and two more) now, so boot finds nothing to change in /etc.
if [[ $(readlink "$IMAGE/etc/mtab") != ../proc/self/mounts ]]; then
    image_run systemd-tmpfiles --create /usr/lib/tmpfiles.d/debian.conf
fi

# 4i. Services: first-boot helpers, jobs that need a writable /var/lib, and NFS helpers the nodes never use off; ssh and the console login on.
touch "$IMAGE/etc/cloud/cloud-init.disabled"
systemctl --root="$IMAGE" --quiet mask userconfig.service regenerate_ssh_host_keys.service \
    rpi-resize.service rpi-eeprom-update.service apt-daily.timer apt-daily-upgrade.timer \
    dpkg-db-backup.timer man-db.timer rpc-statd-notify.service nfs-blkmap.service
systemctl --root="$IMAGE" --quiet disable rpcbind.service rpcbind.socket
systemctl --root="$IMAGE" --quiet enable ssh.service getty@tty1.service

# 4j. ssh: host keys made once and shared by every node; public-key logins only, as on the head node; no first-boot banner.
[[ -e $IMAGE/etc/ssh/ssh_host_ed25519_key ]] || image_run ssh-keygen -A
if [[ -e $IMAGE/etc/ssh/sshd_config.d/rename_user.conf ]]; then
    rm "$IMAGE/etc/ssh/sshd_config.d/rename_user.conf"
    log "removed the image's first-boot ssh banner"
fi
put "$IMAGE/etc/ssh/sshd_config.d/pi-cluster.conf" <<EOF
$GENERATED
PasswordAuthentication no
EOF

# 4k. Time from the head node, eth0 left to the kernel, swap in RAM only (the default swap file would sit in /var).
put "$IMAGE/etc/systemd/timesyncd.conf.d/pi-cluster.conf" <<EOF
$GENERATED
[Time]
NTP=$HEAD_IP
EOF
put "$IMAGE/etc/NetworkManager/conf.d/pi-cluster.conf" <<EOF
$GENERATED
[keyfile]
unmanaged-devices=interface-name:eth0
EOF
put "$IMAGE/etc/rpi/swap.conf.d/80-pi-cluster.conf" <<EOF
$GENERATED
[Main]
Mechanism=zram
EOF

# 4l. TFTP links for the registered nodes, so a rebuilt image still boots them.
if [[ -e $NODES ]]; then
    sed -n 's/.*# serial \([0-9a-f]\{8\}\).*/\1/p' "$NODES" | while read -r serial; do
        [[ -L $IMAGE/boot/$serial ]] || { ln -s firmware "$IMAGE/boot/$serial"; log "linked $IMAGE/boot/$serial"; }
    done
fi

# 4m. Last, an empty machine ID, so each node makes its own at boot.
: > "$IMAGE/etc/machine-id"
mkdir -p "$IMAGE/var/lib/dbus"
ln -sfn /etc/machine-id "$IMAGE/var/lib/dbus/machine-id"

# 5. Head node services: cloud-init off (it rewrites /etc/hosts at every boot), names, DHCP and TFTP, time.
if [[ -d /etc/cloud && ! -e /etc/cloud/cloud-init.disabled ]]; then
    touch /etc/cloud/cloud-init.disabled
    log "turned off cloud-init on the head node"
fi
put /etc/hosts < <(hosts_file)
[[ -e $NODES ]] || put "$NODES" <<EOF
# pi-cluster node registry, created by head/20-netboot.sh and appended to by head/30-add-node.sh.
# One dnsmasq dhcp-host line per compute node, MAC,IP,NAME  # serial XXXXXXXX
# dnsmasq reads it as its dhcp-hostsfile; /etc/hosts on the head node and in the image is built from it.
EOF
CHANGED=0
put /etc/dnsmasq.d/pi-cluster.conf <<EOF
$GENERATED
interface=eth0
bind-dynamic
# No DNS: every cluster name is in /etc/hosts.
port=0
# Addresses only for the nodes listed in $NODES.
dhcp-range=${NODE_SUBNET}.0,static
dhcp-hostsfile=$NODES
# No default route (the head node does not forward); time from the head node.
dhcp-option=option:router
dhcp-option=option:ntp-server,$HEAD_IP
# Raspberry Pi network boot: the vendor option the bootloader looks for, and TFTP from the image.
pxe-service=0,"Raspberry Pi Boot"
enable-tftp
tftp-root=$IMAGE/boot
EOF
if (( CHANGED )); then systemctl restart dnsmasq; fi
CHANGED=0
put /etc/chrony/conf.d/pi-cluster.conf <<EOF
$GENERATED
allow $CLUSTER_NET
EOF
if (( CHANGED )); then systemctl restart chrony; fi
systemctl enable --now --quiet dnsmasq chrony nfs-server

# 6. NFS exports: the image and /opt read-only, /home read-write, to the compute nodes only.
CHANGED=0
put /etc/exports.d/pi-cluster.exports <<EOF
$GENERATED
$IMAGE  $NODE_NET(ro,sync,no_subtree_check,no_root_squash)
/opt        $NODE_NET(ro,sync,no_subtree_check,no_root_squash)
/home       $NODE_NET(rw,sync,no_subtree_check,no_root_squash)
EOF
if (( CHANGED )); then exportfs -ra; fi
showmount -e
log "done; next, register compute node 1: sudo bash $(dirname "$0")/30-add-node.sh 1"
