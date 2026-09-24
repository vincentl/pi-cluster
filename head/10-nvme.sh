#!/bin/bash
# Copy the head node's running system from the microSD card to the NVMe drive.
# Runs on the head node, booted from the microSD card: sudo bash pi-cluster/head/10-nvme.sh [--force]
# --force copies again even if the NVMe drive already holds a finished copy of this system.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need_root
[[ $# -eq 0 || ( $# -eq 1 && $1 == --force ) ]] || die "usage: sudo bash $0 [--force]"
force=${1:-}

# 0. Nothing to do once / is on NVMe.
if [[ $(root_source) == /dev/nvme* ]]; then
    log "/ is already on $(root_source); nothing to do"
    exit 0
fi

# 1. Find the card that holds / and the NVMe drive.
card_root=$(root_source)
card_boot=$(findmnt -n -o SOURCE /boot/firmware) || die "/boot/firmware is not mounted"
card=/dev/$(lsblk -n -o PKNAME "$card_root")
[[ $card == /dev/mmcblk* ]] || die "/ is on $card_root, which is not a microSD card"
nvme=$(lsblk -d -n -p -o NAME,TRAN | awk '$2 == "nvme" { print $1; exit }')

# 2. No NVMe drive visible: enable the PCIe connector, which takes a reboot.
config=/boot/firmware/config.txt
if [[ -z $nvme ]]; then
    if grep -qE '^dtparam=(nvme|pciex1)' "$config"; then
        die "no NVMe drive found although $config enables PCIe; check the HAT, its cable and the drive"
    fi
    printf '\n[all]\ndtparam=nvme\n' >> "$config"
    log "enabled the PCIe connector in $config"
    log "rebooting; when the head node is back, run this again: sudo bash $0"
    sleep 5
    reboot
    exit 0
fi

# 3. An adapter that is not HAT+ (its slot had to be enabled in config.txt) also needs PCIE_PROBE=1 to boot.
if grep -qE '^dtparam=(nvme|pciex1)' "$config"; then
    eeprom=$(rpi-eeprom-config)
    if ! grep -qx 'PCIE_PROBE=1' <<< "$eeprom"; then
        conf=$(mktemp)
        { grep -v '^PCIE_PROBE=' <<< "$eeprom" || true; echo 'PCIE_PROBE=1'; } > "$conf"
        rpi-eeprom-config --apply "$conf"
        rm -f "$conf"
    fi
fi

# 4. A finished copy is this system (same machine ID) with an fstab naming its own root partition (stage 7).
mnt=$(mktemp -d)
trap 'umount -R "$mnt" 2>/dev/null || true; rmdir "$mnt"' EXIT
partuuid() { blkid -c /dev/null -s PARTUUID -o value "$1"; }
copied() {
    local uuid found=1
    uuid=$(partuuid "${nvme}p2") || return 1
    mount -o ro "${nvme}p2" "$mnt" 2>/dev/null || return 1
    if cmp -s /etc/machine-id "$mnt/etc/machine-id" && grep -q "^PARTUUID=${uuid}[[:space:]]" "$mnt/etc/fstab"; then
        found=0
    fi
    umount "$mnt"
    return "$found"
}

if [[ -z $force ]] && copied; then
    log "$nvme already holds a finished copy; to copy again, run this with --force"
else
    # 5. Confirm before erasing the NVMe drive.
    lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$nvme"
    read -r -p "Erase $nvme and copy $card onto it? [y/N] " answer || true
    [[ ${answer:-} == [Yy]* ]] || die "stopped; nothing was changed"

    # 6. New partitions and file systems: a boot partition as large as the card's, the rest of the drive for /.
    boot_mib=$(( ($(lsblk -b -d -n -o SIZE "$card_boot") + 1048575) / 1048576 ))
    parted "$nvme" --script -- mklabel gpt \
        mkpart boot fat32 1MiB "$((1 + boot_mib))MiB" set 1 esp on \
        mkpart root ext4 "$((1 + boot_mib))MiB" 100%
    udevadm settle
    mkfs.vfat -F 32 -n bootfs "${nvme}p1"
    mkfs.ext4 -F -q -L rootfs "${nvme}p2"

    # 7. Copy the running system file by file (rsync exit 24: files that vanished mid-copy), then point it at the NVMe.
    mount "${nvme}p2" "$mnt"
    log "copying / to $nvme; this takes a few minutes"
    rsync -aHAXx --numeric-ids --info=progress2 --exclude=/var/swap / "$mnt/" || [[ $? -eq 24 ]]
    mount "${nvme}p1" "$mnt/boot/firmware"
    rsync -rt --modify-window=1 /boot/firmware/ "$mnt/boot/firmware/"
    boot_uuid=$(partuuid "${nvme}p1")
    root_uuid=$(partuuid "${nvme}p2")
    sed -Ei -e "s|^[^#[:space:]]+([[:space:]]+/boot/firmware[[:space:]])|PARTUUID=$boot_uuid\1|" \
        -e "s|^[^#[:space:]]+([[:space:]]+/[[:space:]])|PARTUUID=$root_uuid\1|" "$mnt/etc/fstab"
    sed -Ei "s|root=PARTUUID=[^[:space:]]+|root=PARTUUID=$root_uuid|" "$mnt/boot/firmware/cmdline.txt"
    umount "$mnt/boot/firmware" "$mnt"
fi

# 8. What to do next, from the Readme.
cat <<EOF

The NVMe drive holds a bootable copy. Next:
  sudo shutdown now
When the LED next to the power button turns red, unplug the head node, remove the microSD card,
plug the node back in, and on the workstation:
  ssh $HEAD_NODE findmnt -n -o SOURCE /
It should print a /dev/nvme... device.
EOF
