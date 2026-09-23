#!/bin/bash
# Copy the head node's running system from the microSD card to the NVMe drive.
# Runs on the head node, booted from the microSD card: sudo bash pi-cluster/head/10-nvme.sh
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need_root

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

# 3. partclone copies the partitions.
need_packages partclone

# 4. Let the bootloader look for NVMe drives behind adapters that are not HAT+ (PCIE_PROBE=1).
eeprom=$(rpi-eeprom-config)
if ! grep -qx 'PCIE_PROBE=1' <<< "$eeprom"; then
    conf=$(mktemp)
    { grep -v '^PCIE_PROBE=' <<< "$eeprom" || true; echo 'PCIE_PROBE=1'; } > "$conf"
    rpi-eeprom-config --apply "$conf"
    rm -f "$conf"
fi

# 5. A finished copy is one whose fstab names its own root partition (stage 10 writes that last).
mnt=$(mktemp -d)
trap 'umount -R "$mnt" 2>/dev/null || true; rmdir "$mnt"; mountpoint -q /boot/firmware || mount /boot/firmware' EXIT
copied() {
    local uuid found=1
    uuid=$(blkid -s PARTUUID -o value "${nvme}p2") || return 1
    mount -o ro "${nvme}p2" "$mnt" 2>/dev/null || return 1
    grep -q "^PARTUUID=${uuid}[[:space:]]" "$mnt/etc/fstab" && found=0
    umount "$mnt"
    return "$found"
}

if copied; then
    log "$nvme already holds a finished copy"
else
    # 6. Confirm before erasing the NVMe drive.
    lsblk -o NAME,SIZE,MODEL,FSTYPE,LABEL "$nvme"
    read -r -p "Erase $nvme and copy $card onto it? [y/N] " answer || true
    [[ ${answer:-} == [Yy]* ]] || die "stopped; nothing was changed"

    # 7. Partition the NVMe drive: a boot partition as large as the card's, the rest for /.
    boot_mib=$(( ($(lsblk -b -d -n -o SIZE "$card_boot") + 1048575) / 1048576 ))
    parted "$nvme" --script -- mklabel gpt \
        mkpart boot fat32 1MiB "$((1 + boot_mib))MiB" set 1 esp on \
        mkpart root ext4 "$((1 + boot_mib))MiB" 100%
    udevadm settle

    # 8. Copy both partitions; the boot partition is unmounted while it is copied.
    umount /boot/firmware
    partclone.vfat -b -s "$card_boot" -o "${nvme}p1"
    partclone.ext4 -F -b -s "$card_root" -o "${nvme}p2"
    mount /boot/firmware

    # 9. Check both copies and grow / to fill the drive (e2fsck exits 1 to 3 after repairs).
    fsck.vfat -a "${nvme}p1" || [[ $? -eq 1 ]]
    e2fsck -f -y "${nvme}p2" || [[ $? -lt 4 ]]
    resize2fs "${nvme}p2"

    # 10. Point the copy's fstab and cmdline.txt at the NVMe partitions.
    boot_uuid=$(blkid -s PARTUUID -o value "${nvme}p1")
    root_uuid=$(blkid -s PARTUUID -o value "${nvme}p2")
    mount "${nvme}p2" "$mnt"
    mount "${nvme}p1" "$mnt/boot/firmware"
    sed -Ei -e "s|^[^#[:space:]]+([[:space:]]+/boot/firmware[[:space:]])|PARTUUID=$boot_uuid\1|" \
        -e "s|^[^#[:space:]]+([[:space:]]+/[[:space:]])|PARTUUID=$root_uuid\1|" "$mnt/etc/fstab"
    sed -Ei "s|root=PARTUUID=[^[:space:]]+|root=PARTUUID=$root_uuid|" "$mnt/boot/firmware/cmdline.txt"
    umount "$mnt/boot/firmware" "$mnt"
fi

# 11. What to do next, from the Readme.
cat <<EOF

The NVMe drive holds a bootable copy. Next:
  sudo shutdown now
Then unplug the head node, remove the microSD card, plug the node back in, and on the workstation:
  ssh $HEAD_NODE findmnt -n -o SOURCE /
It should print a /dev/nvme... device.
EOF
