# Phase 1 plan: `head/` scripts

Status: approved by Vincent on 2026-09-22 (D22) and implemented the same day; not
hardware-tested. Kickoff: `ai/prompts/2026-09-22-trixie-refresh.md`. Facts are rows F1–F39 at
the end; every row was fetched on 2026-09-22 from the source given, nothing from memory.

## What the research changed

The spec holds, with corrections. Five findings change the design:

1. Imager's cloud-init rewrites the head node's `/etc/hosts` on every boot (F26). Node names
   appended there would vanish at the next reboot. 20-netboot.sh turns cloud-init off on the
   head node after its first boot.
2. Debian's dnsmasq reads every file in `/etc/dnsmasq.d` as configuration (F33). A hosts file
   there breaks dnsmasq at the next restart. The node registry moves to `/etc/pi-cluster/nodes`.
3. The stock image has `MODULES=dep`, which makes every initramfs build inside nspawn fail and
   leaves kernel upgrades half-installed (F14). The spec's `MODULES=netboot` step is therefore
   required, and must happen before any `apt` run in the image.
4. NVMe boot from an adapter that is not HAT+ needs `PCIE_PROBE=1` in the EEPROM (F7). Nobody
   documents whether the X1012 is HAT+ (F8). New 10-nvme.sh stage; a Pi 5 writes the EEPROM
   immediately, so no extra reboot (F9).
5. The stock image ships without ssh host keys, with ssh disabled, and with first-boot units
   that misbehave on a read-only root (F24, F25). Handled in 20-netboot.sh stage 4.

## Human steps in the Readme

Counting rule: one step is one command typed, one Imager write, or one physical action
(insert, connect, unplug). Steps for node 1 count once; further nodes are counted separately.

| Section          | Before (`2e628cb`) | After this plan |
|------------------|--------------------|-----------------|
| Before you start | 3                  | 3               |
| 1. Flash         | 3                  | 3               |
| 2. NVMe          | 6 (+2 if the slot needs enabling) | 6 (+2 if the slot needs enabling) |
| 3. Network boot  | 1                  | 1               |
| 4. Add node 1    | 6                  | 6               |
| 5. Check         | 2                  | 2               |
| **Total**        | **21 (+2)**        | **21 (+2)**     |
| Each further node | 5                 | 5               |
| Reboot-and-rerun cycles | 1, conditional | 1, conditional |

No step added. Considered and rejected: running every command as `ssh -t pi-login sudo …` from
the workstation saves the one `ssh pi-login` step but makes every later command longer.

## Changes to the kickoff prompt that need your OK

| # | Change | Why |
|---|--------|-----|
| C1 | Registry at `/etc/pi-cluster/nodes` instead of `/etc/dnsmasq.d/cluster-nodes.hosts`. One `dhcp-host` line per node, `MAC,IP,NAME  # serial XXXXXXXX`. | F33. Trailing comments are legal in a hostsfile (F32); the serial comment lets reruns and image rebuilds recreate the TFTP link. |
| C2 | `/etc/hosts` on the head node and in the image is regenerated from `cluster.env` plus the registry by both 20 and 30, instead of 30 appending. Cloud-init is turned off on the head node (`/etc/cloud/cloud-init.disabled`). | F26. One source of truth, idempotent, survives reboots. Alternative (editing cloud-init's hosts template) is a dpkg conffile. |
| C3 | 20-netboot.sh stage order: network, packages, image, image config, head services, exports. | dnsmasq exits at start if `tftp-root` is missing (F32), and exports need `/image/pi5` to exist. |
| C4 | The image is unpacked into `/image/pi5.new` and renamed when complete. The guard stays `/image/pi5/etc/os-release`. | rsync writes `etc/` before `usr/`, so an interrupted copy would pass the guard. |
| C5 | dnsmasq: `bind-dynamic` instead of `bind-interfaces`. | With `bind-interfaces` dnsmasq exits if eth0 has no address when it starts (F32). |
| C6 | dnsmasq: empty `dhcp-option=option:router`, so nodes get no default route. | dnsmasq sends the head as router by default (F32); with no NAT (D8), traffic to the internet would time out instead of failing at once. Changes a DHCP option, not the address layout. |
| C7 | Image fstab: no `/` line; no `/tmp`, `/run`, `/proc`, cgroup lines; `/home` and `/opt` as plain `nfs` (negotiates v4.2); tmpfs `/var` and `/media`. | systemd-remount-fs would apply a `/` line to the NFS root (F20); systemd already mounts the rest (F21). Root stays NFSv3, the initramfs cannot mount v4 (F17). |
| C8 | cmdline: `console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=HEAD_IP:/image/pi5,vers=3 ro ip=dhcp panic=60 ipv6.disable=1 cgroup_enable=memory`. Dropped `cgroup_enable=cpuset`, `cgroup_memory=1`, `swapaccount=1`, `systemd.unified_cgroup_hierarchy=1`, `rootwait`, `systemd.gpt_auto=no`, `nolock`. | F16–F18. Console tokens are Pi OS's own defaults. |
| C9 | `MODULES=netboot` goes in `etc/initramfs-tools/conf.d/pi-cluster`, not an edit of `initramfs.conf`; regenerate with `update-initramfs -u -k all`. | F14, F15. conf.d overrides without touching a dpkg-managed file. |
| C10 | mtab: run Debian's own rule inside the image once (`systemd-tmpfiles --create /usr/lib/tmpfiles.d/debian.conf`) instead of editing `/usr/lib/tmpfiles.d/debian.conf`. | F23. The edited file is replaced on every systemd upgrade; a link with the right target needs no fix. |
| C11 | The image gets `nfs-common`. Its dependency `rpcbind` is disabled as the spec says. | Not in the image (F2); nodes need `mount.nfs` for `/home` and `/opt`. |
| C12 | More image units: cloud-init off; `userconfig` masked and `getty@tty1` re-enabled; `regenerate_ssh_host_keys`, `rpi-resize`, `rpi-eeprom-update`, `apt-daily`, `apt-daily-upgrade`, `dpkg-db-backup` and `man-db` timers masked; `ssh` enabled. Masked rather than disabled so an upgrade in the image cannot bring them back. | F25, F29, F22. `rpi-eeprom-update` would otherwise flash every node from the shared image. |
| C13 | `/usr/sbin/policy-rc.d` (exit 101) in the image. | Without it, `apt` inside nspawn starts packaged daemons on the head node's network (F30), and a clash on port 22 or 111 fails the upgrade. |
| C14 | `image-run.sh` uses `--resolv-conf=bind-host`, not `replace-host`, and empties the machine ID after every command. | `replace-host` writes the head's home-network resolver into the image for good (F30, F31). Package scripts fill `/etc/machine-id` inside nspawn (F24). |
| C15 | "Warn if any node holds an NFS lease" is implemented as: established TCP connections to port 2049 (`ss`). | NFS has no leases; DHCP leases are useless here because `ip=dhcp` never renews. |
| C16 | 10-nvme.sh: new `PCIE_PROBE=1` stage; the boot partition is sized from the card instead of a fixed 512 MiB; a finished clone is detected from the NVMe's own `fstab`. | F7, F9; C16 guard is a real-state check, so a rerun before shutdown does not re-clone. |
| C17 | Image drop-ins: timesyncd `NTP=HEAD_IP`, NetworkManager `unmanaged-devices=interface-name:eth0`, rpi-swap `Mechanism=zram`, sshd `PasswordAuthentication no`, empty `resolv.conf`. | F35, F37 (both spec conditions hold), F28 (default swap file lands on tmpfs `/var`), matches the head's Imager SSH setting, F31. |
| C18 | 20-netboot.sh stops with a clear message if the wifi network already contains `HEAD_IP` (for example a 10.0.0.0/24 home router). | Otherwise eth0 and wlan0 fight over the same addresses. Check only, no layout change. |
| C19 | Readme §5 runs from the workstation. | The head node has no private key, so `ssh pi-001` from pi-login fails; the workstation reaches nodes through ProxyJump. |
| C20 | Readme Maintenance: `image-run.sh apt update` before `apt full-upgrade -y`. | Without it the upgrade uses stale package lists. |
| C21 | Added while implementing: the Readme runs every script as `sudo bash pi-cluster/head/…`, and 20-netboot.sh calls image-run.sh through `bash`. | A copy made on Windows (D14) arrives without execute bits, and `sudo pi-cluster/head/10-nvme.sh` would fail with "command not found". No step added. |

Kept as specified, after checking: per-serial symlinks as the TFTP layout (F10, F13, F32:
dnsmasq follows them); wifi/bluetooth blacklist; `dtparam=nvme` reboot stage (F6); passwd,
shadow, group, gshadow copied from the head node.

## `head/lib.sh`

Sourced by every script. `set -euo pipefail`; `REPO` from `$0`; sources `cluster.env`.

- Derived: `IMAGE=/image/pi5`, `NODE_NET=${NODE_SUBNET}.0/24`, `PREFIX=${CLUSTER_NET#*/}`,
  `NODES=/etc/pi-cluster/nodes`, `CACHE=/var/cache/pi-cluster`.
- `log`, `die`, `need_root`, `node_name N` (`pi-001`), `node_ip N` (`10.0.1.1`).
- `put FILE [MODE]`: write stdin to FILE only if the content differs, log it, set `CHANGED=1`.
  Callers restart a service only when its file changed, so a rerun restarts nothing.
- `hosts_file`: prints `/etc/hosts` for both head and image: generated-by header, localhost
  lines, `HEAD_IP HEAD_NODE`, one line per registered node.

## `head/10-nvme.sh`

Runs from the microSD. Ports `templates/setup/nvme-setup.sh`.

| # | Stage | Guard (real state) | Ports |
|---|-------|--------------------|-------|
| 0 | Exit 0 with a message if `/` is on NVMe | `findmnt -n -o SOURCE /` is `/dev/nvme*` | new |
| 1 | Find the card (`lsblk -no PKNAME` of `/`, must be `mmcblk*`) and the NVMe disk (`lsblk -dn -o NAME,TRAN`, TRAN=nvme) | detection only | replaces :23-24 |
| 2 | No NVMe disk: append `[all]` + `dtparam=nvme` to `/boot/firmware/config.txt`, say "run this again after the reboot", reboot. Already there and still no disk: stop with a hardware message | disk present; line present | :7-15 |
| 3 | Install `partclone` | `dpkg-query` status | :3-5, without the full-upgrade |
| 4 | EEPROM `PCIE_PROBE=1` via `rpi-eeprom-config --apply` | `rpi-eeprom-config` shows `PCIE_PROBE=1` | new (F7, F9) |
| 5 | Clone already finished: skip to 10 | NVMe p2 mounts read-only and its `etc/fstab` names NVMe p2's PARTUUID | new |
| 6 | Confirm, showing the NVMe model, size and current partitions | none; this is the confirmation | :26-32 |
| 7 | GPT: p1 as large as the card's boot partition, ESP flag; p2 the rest | after confirm | :34-38 |
| 8 | Unmount `/boot/firmware`; `partclone.vfat` p1; `partclone.ext4 -F` p2; remount | after confirm | :40-43 |
| 9 | `parted resizepart 2 100%`; `fsck.vfat -a`; `e2fsck -fy` (exit codes below 4 are repairs, not failures); `resize2fs` | after clone | :45-49 |
| 10 | NVMe `fstab` and `cmdline.txt` to NVMe PARTUUIDs (the last write, so it is the completion mark for stage 5) | same check as 5 | :51-58 |
| 11 | Print the next two Readme commands (`sudo shutdown now`; from the workstation `ssh pi-login findmnt -n -o SOURCE /`) | none | new |

Dropped: `AllowAgentForwarding` (the Readme uses ProxyJump) and the `hosts` copy (20-netboot.sh
writes `/etc/hosts`).

## `head/20-netboot.sh`

Runs from NVMe; stops if `/` is on the card. Ports `templates/setup/network-boot.sh`,
`dhcpd.conf`, `isc-dhcp-server`, `hosts`, `stage-1.py:78-84` and the loop-mount pattern of
`manage.sh:41-49`.

| # | Stage | Guard | Ports |
|---|-------|-------|-------|
| 1 | Network: C18 check, then `nmcli con add type ethernet ifname eth0 con-name pi-cluster ipv4.method manual ipv4.addresses HEAD_IP/PREFIX ipv4.never-default yes ipv6.method disabled connection.autoconnect-priority 100`, `nmcli con up`. Priority outranks the DHCP profile Imager's netplan puts on eth0 (F26, F37) | `nmcli -g ipv4.addresses con show pi-cluster` equals `HEAD_IP/PREFIX` | :9-26, no reboot |
| 2 | Packages (below); `apt-get update` only if one is missing | `dpkg-query` per package | :3-7, :28-43 |
| 3 | Image: resolve the `OS_IMAGE_URL` redirect; download to `CACHE` with `curl -fL -C -` unless the published `.sha256` already matches; verify; `xz -dk`; `losetup -P -r`; mount p2 then p1 at `boot/firmware`, read-only; `rsync -aHAX --numeric-ids` into `/image/pi5.new`; unmount and detach under `trap`; rename; delete the `.img`, keep the `.img.xz` | `/image/pi5/etc/os-release` | :51-63, manage.sh |
| 4 | Image configuration, list below | per item | :65-113 |
| 5 | Head services: cloud-init off; `/etc/hosts`; registry created if missing (never rewritten); `/etc/dnsmasq.d/pi-cluster.conf`; `/etc/chrony/conf.d/pi-cluster.conf` (`allow CLUSTER_NET`); enable dnsmasq, chrony, nfs-server; restart only those whose file changed; start any that is inactive | `put`; file exists; `systemctl is-active` | :28-43 |
| 6 | `/etc/exports.d/pi-cluster.exports`: `/image/pi5` and `/opt` ro, `/home` rw, all `sync,no_subtree_check,no_root_squash` to `NODE_NET`; `exportfs -ra` when changed; print `showmount -e` | `put` | :116-125 |

dnsmasq file (C5, C6; F11, F32):

```
interface=eth0
bind-dynamic
port=0
dhcp-range=10.0.1.0,static
dhcp-hostsfile=/etc/pi-cluster/nodes
dhcp-option=option:router
dhcp-option=option:ntp-server,10.0.0.1
pxe-service=0,"Raspberry Pi Boot"
enable-tftp
tftp-root=/image/pi5/boot
```

Stage 4, in this order (a–c must precede any package work in the image):

- a. Accounts: `passwd shadow group gshadow` from the head (`cmp -s`). First, so packages
  installed into the image reuse the head's uids.
- b. `etc/initramfs-tools/conf.d/pi-cluster` (`MODULES=netboot`) and
  `etc/modprobe.d/pi-cluster-blacklist.conf` (brcmfmac, brcmutil, btbcm, hci_uart).
- c. `usr/sbin/policy-rc.d`.
- d. `nfs-common` via `image-run.sh` (guard: `dpkg-query --admindir=/image/pi5/var/lib/dpkg`).
- e. `image-run.sh update-initramfs -u -k all` (guard: `boot/firmware/initramfs_2712` newer than
  both files from b).
- f. `boot/firmware/cmdline.txt` (C8) and `etc/fstab` (C7).
- g. Remove `etc/hostname`; `etc/hosts` from `hosts_file`; empty `etc/resolv.conf`.
- h. `image-run.sh systemd-tmpfiles --create /usr/lib/tmpfiles.d/debian.conf` (guard: `etc/mtab`
  links to `../proc/self/mounts`).
- i. Units (C12) with `systemctl --root`, which checks state itself; `etc/cloud/cloud-init.disabled`.
- j. `image-run.sh ssh-keygen -A` (guard: `etc/ssh/ssh_host_ed25519_key`); sshd drop-in.
- k. Drop-ins: timesyncd, NetworkManager, rpi-swap (C17).
- l. Serial links: `ln -sfn firmware /image/pi5/boot/<serial>` for every registered node that
  has a serial, so a rebuilt image keeps booting the nodes.
- m. Last: empty `etc/machine-id`, `var/lib/dbus/machine-id` a link to `/etc/machine-id` (F24).

## `head/30-add-node.sh N`

Ports `templates/setup/add-node.sh`.

| # | Stage | Guard |
|---|-------|-------|
| 0 | N is an integer 1–254; `/image/pi5` and the registry exist | none |
| 1 | MAC: reuse the registry line if the node is there. Otherwise say "connect node N now" and run `tcpdump -l -n -i eth0 -c 1 'udp dst port 67 and not ether src <each registered MAC>'`; read `Request from <mac>` (F39) | registry line for the name |
| 2 | Done already: skip to 5 | line has `# serial X` and `/image/pi5/boot/X` is a link |
| 3 | Start `tcpdump -c 1 'udp dst port 69 and src host <node ip>'` in the background first (fixes the race in audit §3); append `MAC,IP,NAME`; rewrite `/etc/hosts` on the head and in the image; `systemctl reload dnsmasq` (SIGHUP, F33) | line present; `put` |
| 4 | Wait for the capture; read `RRQ "<serial>/`; require 8 hex digits; `ln -sfn firmware /image/pi5/boot/<serial>`; add `# serial <serial>` to the line | link exists |
| 5 | Print MAC, serial, name, address, and "from your workstation: `ssh pi-001 uptime`" | none |

The node's first TFTP attempt fails (no link yet); the bootloader retries and boots (F10).

## `head/image-run.sh [command…]`

About 15 lines: `need_root`; stop if there is no image; warn with the addresses of connected
NFS clients (C15); `systemd-nspawn -q -D /image/pi5 --bind=/opt --resolv-conf=bind-host "$@"`,
which gives a shell when no command is given; afterwards empty the machine ID again (C14);
exit with nspawn's status. Without `--boot`: the command runs as PID 1; debhelper skips
service restarts and policy-rc.d stops init scripts (F30). `apt full-upgrade` and
`update-initramfs` work this way once C9 and C13 are in place (F13, F14); confirmed on hardware
in Phase 2.

## Packages

Head node, new:

- `dnsmasq`: DHCP and TFTP for the nodes (D4).
- `nfs-kernel-server`: serves the node root, `/home` and `/opt`.
- `chrony`: time server for the nodes; `ntp` is gone from trixie (F3). Replaces
  systemd-timesyncd on the head (F34).
- `tcpdump`: 30-add-node.sh reads each node's MAC and serial from its boot packets.
- `systemd-container`: `systemd-nspawn` for image-run.sh.
- `partclone` (10-nvme.sh only): clones the card's partitions to NVMe.
- Already in the image, listed so the script does not depend on that: `xz-utils` (unpack the
  image), `curl` (download it), `rsync` (copy it).

Compute image, new: `nfs-common` (C11).

Dropped from the old scripts: `ntp`, `ifupdown`, `net-tools`, `isc-dhcp-server`, `tftpd-hpa`,
`tftp-hpa`.

## Deletions

`git rm stage-1.py utils.py cluster.toml manage.sh templates/`; `rm -rf setup/ instructions.txt
__pycache__/`. `CLAUDE.md`: drop the "Being retired" line and the stale "Don't commit" names;
`.gitignore` keeps `.DS_Store`, `*.img`, `*.img.xz`.

## Readme changes (same commit)

1. §1 Imager table for Imager 2.0.11.1: Device; OS under "Raspberry Pi OS (other)"; Storage;
   Hostname; Localisation; User; Wi-Fi; Remote access (Enable SSH, public-key authentication,
   key); Raspberry Pi Connect off (F27).
2. §2: the script also sets the bootloader to look for the NVMe drive; `sudo` asks for the
   password set in Imager (F26).
3. §3: add a bullet that cloud-init is turned off on the head node and why.
4. §4: menu path "Misc utility images → Bootloader (Pi 5 family) → Network Boot"; the green LED
   flashes rapidly without stopping, or a connected screen turns green (F5).
5. §5: commands run from the workstation (C19); `findmnt -t nfs,nfs4`.
6. Maintenance: `apt update` row (C20); rebuilding the image keeps registered nodes booting.
7. Troubleshooting: wifi overlap message (C18); registry path.
8. Notes, Security: remove "passwordless sudo, as Imager sets it up" (F26).
9. `docs/images/README.md`: figures 04 and 05 described as the User and Remote access screens.

The Status note stays until Phase 2.

## Check on hardware in Phase 2

- X1012: whether the NVMe appears without `dtparam=nvme` (HAT+ or not); `rpi-eeprom-config`
  shows `PCIE_PROBE=1`; the head boots from NVMe with the card out.
- Where `nmcli con add` stores the profile on Pi OS's netplan-patched NetworkManager, and that
  `pi-cluster` wins over `netplan-eth0` after a reboot (F37).
- A node: `/proc/cmdline` has `cgroup_disable=memory` before `cgroup_enable=memory`;
  `/sys/fs/cgroup/cgroup.controllers` lists cpuset, cpu, memory; `hostname` is `pi-001`;
  root is `ro` and `vers=3`; `/home` and `/opt` are NFSv4; `timedatectl` synchronized;
  `systemctl --failed` is empty; machine IDs differ between nodes.
- `image-run.sh apt update` and `apt full-upgrade -y` with a kernel update: `kernel_2712.img`
  and `initramfs_2712` change, `etc/machine-id` stays empty, nodes reboot fine.
- A rerun of every script changes nothing and restarts nothing.

## Facts

| # | Question | Finding | Source | Consequence |
|---|----------|---------|--------|-------------|
| F1 | Where `raspios_lite_arm64_latest` points | 302 to `raspios_lite_arm64-2026-09-15/2026-09-15-raspios-trixie-arm64-lite.img.xz` (516 MB); `.sha256` published next to it | `curl -sIL https://downloads.raspberrypi.com/raspios_lite_arm64_latest`; https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2026-09-15/ | Follow the redirect, verify the checksum |
| F2 | What the image contains | cloud-init 25.2, netplan.io 1.1.2, network-manager 1.52.1-1+rpt4, systemd 257.13, initramfs-tools 0.148.4+rpt2, raspi-firmware 1:1.20260907-1, rpi-eeprom 28.31-1, flashrom 1.4.0, linux-image-rpi-2712 and -rpi-v8 6.18.50, userconf-pi 0.19, rpi-swap 1.2.4. Absent: nfs-common, rpcbind, tcpdump, partclone, chrony, systemd-container | https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2026-09-15/2026-09-15-raspios-trixie-arm64-lite.info | C11; head package list |
| F3 | Trixie packages | dnsmasq 2.91-1+deb13u2; nfs-kernel-server and nfs-common 1:2.8.3-1 (nfs-common depends on rpcbind); chrony 4.6.1-3+deb13u2; tcpdump 4.99.5-2; partclone 0.3.36+repack-1; systemd-container 257.13; `ntp` not in trixie | https://packages.debian.org/trixie/nfs-common and the same page for each package | Package list |
| F4 | Pi 5 default boot order | 0xf461: SD, NVMe, USB, repeat; no network (2). Inferred: the docs state no factory value; rpi-eeprom's factory reset for Pi 5 uses the SD config | https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/master/imager/2712-config/boot-conf-sd.txt; https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/master/imager/README-2712.txt; https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/raspberry-pi/eeprom-bootloader.adoc | Readme §4 EEPROM step stays (D6) |
| F5 | Imager Network Boot image | Misc utility images → Bootloader (Pi 5 family) → Network Boot; writes `BOOT_ORDER=0xf21`; success: green LED flashes rapidly without stopping, HDMI screen green; red on failure | https://downloads.raspberrypi.com/os_list_imagingutility_v4.json; https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/master/imager/2712-config/boot-conf-network.txt; README-2712.txt above; https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/raspberry-pi/boot-eeprom.adoc | Readme §4 wording |
| F6 | PCIe connector on Pi 5 | Off unless a HAT+ is detected (by a detect pin, not an EEPROM); `dtparam=nvme` is an alias of `pciex1`; the firmware sets it itself after booting from NVMe | https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/raspberry-pi/pcie.adoc; https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.18.y/arch/arm/boot/dts/overlays/README; https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/master/firmware-2712/release-notes.md | Keep the conditional `dtparam=nvme` stage and Readme §2 sentence |
| F7 | NVMe boot, adapter not HAT+ | The bootloader enumerates PCIe at boot only with `PCIE_PROBE=1`; HAT+ devices are detected without it | eeprom-bootloader.adoc (F4), section PCIE_PROBE; pcie.adoc (F6) | 10-nvme.sh stage 4 |
| F8 | Geekworm X1012 | HAT+ status not stated; Geekworm tells users to add `dtparam=pciex1` and `PCIE_PROBE=1` | https://wiki.geekworm.com/X1012; https://wiki.geekworm.com/NVMe_SSD_boot_with_the_Raspberry_Pi_5 | Treat as not HAT+; check in Phase 2 |
| F9 | How EEPROM changes apply on Pi 5 | `rpi-eeprom-config --apply` calls `rpi-eeprom-update`, which on BCM2712 defaults to an immediate write with flashrom (in the image) | https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/pios/trixie/rpi-eeprom-update (BCM2712 block and immediate-update branch); boot-eeprom.adoc (F5) | `PCIE_PROBE` is set before the card is removed |
| F10 | TFTP layout | `TFTP_PREFIX=0` default: serial number, 8 lowercase hex digits; the prefix is dropped if the boot files are missing there (Pi 5 decides on `config.txt`); server address from DHCP siaddr; first request `<serial>/config.txt` | eeprom-bootloader.adoc (F4), TFTP_PREFIX; release-notes.md (F6), 2026-09-10 entry; https://github.com/raspberrypi/rpi-eeprom/issues/687 | Keep per-serial links (D16); serial from the first RRQ |
| F11 | Official netboot tutorial | Pi 3/4 clients, dnsmasq in proxy mode with `port=0`, `enable-tftp`, `tftp-root`, `pxe-service=0,"Raspberry Pi Boot"`; cmdline `root=/dev/nfs nfsroot=…,vers=3 rw ip=dhcp rootwait` | https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/remote-access/network-boot-raspberry-pi.adoc | Keep `pxe-service`; real static range, since the head is the only DHCP server |
| F12 | What a Pi 5 loads | `kernel_2712.img` and, with `auto_initramfs=1` (in the stock config.txt), `initramfs_2712` | https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/config_txt/boot.adoc; https://raw.githubusercontent.com/RPi-Distro/pi-gen/2026-09-15-raspios-trixie-arm64/stage1/00-boot-files/files/config.txt | TFTP serves both from the image |
| F13 | raspi-firmware hooks | Copy `/boot/vmlinuz-V` and `/boot/initrd.img-V` to `kernel_2712.img` and `initramfs_2712` (plus v8 names, DTBs, overlays). The mount-point check is skipped when `systemd-detect-virt` detects a container, which nspawn is | https://raw.githubusercontent.com/RPi-Distro/firmware/pios/trixie/debian/kernel/postinst.d/z50-raspi-firmware; https://raw.githubusercontent.com/RPi-Distro/firmware/pios/trixie/debian/initramfs/post-update.d/z50-raspi-firmware; https://raw.githubusercontent.com/systemd/systemd/v257.13/src/nspawn/nspawn.c | No sync step: TFTP serves what the image installs |
| F14 | `MODULES=dep` in the image | pi-gen sets it; inside nspawn mkinitramfs finds no block device for `/` and fails; the kernel hooks stop there, so the firmware copy never runs | https://raw.githubusercontent.com/RPi-Distro/pi-gen/2026-09-15-raspios-trixie-arm64/export-image/05-finalise/01-run.sh (line 23); https://github.com/RPi-Distro/repo/issues/382; https://archive.raspberrypi.com/debian/pool/main/i/initramfs-tools/ (0.148.4+rpt2 hook-functions) | C9, before any `apt` in the image |
| F15 | initramfs-tools | `MODULES=netboot` = base (NFS included) plus network drivers, no block drivers; `conf.d/` files override `initramfs.conf` (names `^[[:alnum:]][[:alnum:]._-]*$`); `-u -k all` updates every kernel that has an initramfs | https://manpages.debian.org/trixie/initramfs-tools-core/initramfs.conf.5.en.html; https://salsa.debian.org/kernel-team/initramfs-tools/-/raw/v0.148.4/mkinitramfs; https://manpages.debian.org/trixie/initramfs-tools/update-initramfs.8.en.html | C9 |
| F16 | cgroups for Slurm | The Pi 5 device tree adds `cgroup_disable=memory`; cmdline.txt comes after it, so `cgroup_enable=memory` wins; cpuset is on by default; `cgroup_memory=1` unknown since 4.14; `swapaccount=1` does nothing; `systemd.unified_cgroup_hierarchy` deprecated since systemd 252, cgroup v1 removed in 258 | https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.18.y/arch/arm64/boot/dts/broadcom/bcm2712-rpi.dtsi; https://github.com/raspberrypi/linux/issues/6980; https://github.com/raspberrypi/linux/commit/86099deff5abf5f63643eecaedb4c11ae77474ce; https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html; https://raw.githubusercontent.com/systemd/systemd/main/NEWS; https://slurm.schedmd.com/archive/slurm-24.11.5/cgroup_v2.html | C8 |
| F17 | NFS root via initramfs | `root=/dev/nfs` selects the NFS boot script; klibc nfsmount speaks v2 and v3 only, TCP and nolock by default, honours `ro`; the kernel's own `ip=dhcp` runs first and the initramfs asks again, harmlessly; `rootwait` is unused | https://salsa.debian.org/kernel-team/initramfs-tools/-/raw/v0.148.4/scripts/nfs; https://salsa.debian.org/kernel-team/initramfs-tools/-/raw/v0.148.4/init; https://git.kernel.org/pub/scm/libs/klibc/klibc.git/plain/usr/kinit/nfsmount/main.c?h=klibc-2.0.14 | `nfsroot=…,vers=3` |
| F18 | Pi 5 kernel config | `IP_PNP`, `IP_PNP_DHCP`, `ROOT_NFS`, `NFS_FS`, `NFS_V3`, `NFS_V4`, `MACB`, `MFD_RP1` built in; `NFS_V2=y` | https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.18.y/arch/arm64/configs/bcm2712_defconfig | `vers=3` also guards a boot without initramfs (the kernel would try v2, which trixie's server no longer offers, F36) |
| F19 | Hostname | Kernel `ip=dhcp` and klibc ipconfig set it from DHCP option 12; systemd 257 keeps it when `/etc/hostname` is absent | https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.18.y/net/ipv4/ipconfig.c; https://raw.githubusercontent.com/systemd/systemd/v257.13/src/shared/hostname-setup.c; https://manpages.debian.org/trixie/systemd/hostname.5.en.html | Remove `/etc/hostname` from the image |
| F20 | `/` in fstab | systemd-remount-fs applies fstab options to the root file system | https://manpages.debian.org/trixie/systemd/systemd-remount-fs.service.8.en.html | C7 |
| F21 | `/tmp` | tmpfs by default in trixie; `tmp.mount` is statically enabled; pi-gen does not mask it | https://www.debian.org/releases/trixie/release-notes/issues.en.html#tmp-tmpfs; https://packages.debian.org/trixie/arm64/systemd/filelist | C7 |
| F22 | tmpfs `/var` | tmpfiles creates `/var/{log,cache,lib,spool,tmp}` and the `run`/`lock` links; `StateDirectory=` dirs appear at unit start (timesyncd); cron and man-db make their own; the Pi OS journal is volatile; sm-notify failures are ignored | https://sources.debian.org/data/main/s/systemd/257.13-1~deb13u1/tmpfiles.d/var.conf.in; https://manpages.debian.org/trixie/systemd/systemd.exec.5.en.html; https://raw.githubusercontent.com/RPi-Distro/raspberrypi-sys-mods/pios/trixie/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf; https://sources.debian.org/data/main/n/nfs-utils/1%3A2.8.3-1/systemd/rpc-statd-notify.service | No tmpfiles.d entries for the base image; timers needing `/var/lib/apt` or `/var/lib/dpkg` masked (C12); Phase 3 adds munge and slurmd |
| F23 | `/etc/mtab` | Debian's rule is `L+ /etc/mtab … ../proc/self/mounts` (also `/etc/default/locale`, `/etc/vconsole.conf`); a link with the right target is left alone; pi-gen links `/proc/mounts`, so a read-only root logs an error at every boot | https://sources.debian.org/data/main/s/systemd/257.13-1~deb13u1/debian/extra/tmpfiles.d/debian.conf; https://sources.debian.org/data/main/s/systemd/257.13-1~deb13u1/src/tmpfiles/tmpfiles.c; pi-gen finalise (F14), line 59 | C10 |
| F24 | machine-id | Empty file: not a first boot, a transient ID per boot. `uninitialized` (what pi-gen writes): a first boot at every boot of a read-only root. systemd's postinst fills an empty file on each upgrade (inside nspawn, with the container's UUID); PID 1 reads a non-link `/var/lib/dbus/machine-id` first | https://manpages.debian.org/trixie/systemd/machine-id.5.en.html; https://sources.debian.org/data/main/s/systemd/257.13-1~deb13u1/debian/systemd.postinst; https://sources.debian.org/data/main/d/dbus/1.16.2-2/debian/dbus-daemon.postinst | Stage 4m; C14 |
| F25 | First boot in the image | cloud-init runs at every boot (off with `/etc/cloud/cloud-init.disabled`); pi-gen's `rename-user` disables `getty@tty1` and enables `userconfig`; `regenerate_ssh_host_keys` and `rpi-resize` run on first boot; no ssh host keys shipped; `ssh.service` disabled | https://raw.githubusercontent.com/RPi-Distro/userconf-pi/pios/trixie/rename-user (lines 78-79); https://raw.githubusercontent.com/RPi-Distro/pi-gen/2026-09-15-raspios-trixie-arm64/stage2/01-sys-tweaks/01-run.sh; https://github.com/RPi-Distro/raspberrypi-sys-mods/tree/pios/trixie/debian; https://docs.cloud-init.io/en/latest/howto/disable_cloud_init.html | C12; stage 4j |
| F26 | Imager customisation on trixie | cloud-init user-data: hostname, `manage_etc_hosts: true`, user with hashed password and key, `sudo: null` (passwordless sudo off since 2026-04-13), `ssh_pwauth: false`; network-config also puts eth0 on DHCP; `/etc/hosts` rebuilt from cloud-init's template at every boot | https://raw.githubusercontent.com/raspberrypi/rpi-imager/v2.0.11.1/src/customization_generator.cpp; https://raw.githubusercontent.com/canonical/cloud-init/25.2/cloudinit/config/cc_update_etc_hosts.py; https://downloads.raspberrypi.com/raspios_lite_arm64/release_notes.txt | C2; stage 1 priority; Readme sudo wording |
| F27 | Imager 2.0.11.1 screens | Device → OS → Storage → Hostname → Localisation → User → Wi-Fi → Remote access → Raspberry Pi Connect → Writing; Lite 64-bit sits under "Raspberry Pi OS (other)" | https://github.com/raspberrypi/rpi-imager/tree/v2.0.11.1/src/wizard; https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/getting-started/install.adoc | Readme §1 |
| F28 | rpi-swap | Default `auto` is zram plus a writeback file at `/var/swap` | https://raw.githubusercontent.com/raspberrypi/rpi-swap/main/man/man5/swap.conf.5 | C17 |
| F29 | rpi-eeprom-update | The service applies new bootloader images at boot; `systemctl mask rpi-eeprom-update` stops it | boot-eeprom.adoc (F5), "Automatic updates" | C12 |
| F30 | systemd-nspawn 257 | Without `--boot` the command is PID 1 and `/run` is empty, so debhelper skips restarts, but `invoke-rc.d` runs init scripts unless policy-rc.d exits 101; `replace-host` overwrites the image's resolv.conf, `bind-host` only mounts over it; `--timezone=auto` copies the host's zone into the image | https://manpages.debian.org/trixie/systemd-container/systemd-nspawn.1.en.html; https://sources.debian.org/data/main/i/init-system-helpers/1.69~deb13u1/script/invoke-rc.d | C13, C14 |
| F31 | resolv.conf in the image | pi-gen installs a regular file with `nameserver 8.8.8.8` | https://raw.githubusercontent.com/RPi-Distro/pi-gen/2026-09-15-raspios-trixie-arm64/export-image/03-network/files/resolv.conf | C14, C17 |
| F32 | dnsmasq 2.91 | hostsfile lines `MAC,IP,NAME`, `#` comments at line start or after whitespace, re-read on SIGHUP; `dhcp-range=10.0.1.0,static` takes the /8 from eth0; `port=0` turns DNS off; `bind-interfaces` exits if eth0 has no address, `bind-dynamic` waits; `pxe-service` sends option 43 "Raspberry Pi Boot"; siaddr is its own address; option 12 sent when requested; the router option is sent unless emptied; exits if `tftp-root` is missing; follows symlinks; TFTP runs as user `dnsmasq`; DHCP and TFTP lines logged by default | https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html; https://sources.debian.org/data/main/d/dnsmasq/2.91-1+deb13u2/src/option.c; https://sources.debian.org/data/main/d/dnsmasq/2.91-1+deb13u2/src/tftp.c; https://sources.debian.org/data/main/d/dnsmasq/2.91-1+deb13u2/src/rfc2131.c | dnsmasq file; C3, C5, C6 |
| F33 | Debian dnsmasq packaging | Every file in `/etc/dnsmasq.d` is configuration (only `.dpkg-*`, dotfiles and `~` skipped); `ExecReload` sends SIGHUP; runs as `dnsmasq` | https://sources.debian.org/data/main/d/dnsmasq/2.91-1+deb13u2/debian/dnsmasq.default; https://sources.debian.org/data/main/d/dnsmasq/2.91-1+deb13u2/debian/readme.dnsmasq.d; https://sources.debian.org/data/main/d/dnsmasq/2.91-1+deb13u2/debian/dnsmasq.service | C1; `systemctl reload dnsmasq` |
| F34 | chrony 4.6.1 | Default config reads `/etc/chrony/conf.d/*.conf`; `allow` takes CIDR; an unsynchronised server answers with stratum 16, so clients wait; installing chrony removes systemd-timesyncd | https://sources.debian.org/data/main/c/chrony/4.6.1-3+deb13u2/debian/chrony.conf; https://chrony-project.org/doc/4.6.1/chrony.conf.html | conf.d drop-in; no `local stratum` |
| F35 | timesyncd | Per-link NTP servers come only from systemd-networkd; NetworkManager has no timesyncd hook in trixie | https://manpages.debian.org/trixie/systemd-timesyncd/timesyncd.conf.5.en.html; https://bugs.launchpad.net/ubuntu/+source/network-manager/+bug/1933828 | C17; keep the DHCP option too |
| F36 | NFS, nfs-utils 2.8.3 | `/etc/exports.d/*.exports` is read; v3 and v4.x on by default, v2 removed; v3 needs rpcbind; `showmount -e` works; `exportfs -ra` syncs | https://sources.debian.org/data/main/n/nfs-utils/1%3A2.8.3-1/utils/exportfs/exports.man; https://sources.debian.org/data/main/n/nfs-utils/1%3A2.8.3-1/utils/nfsd/nfsd.man | Stage 6; root v3, `/home` and `/opt` v4 |
| F37 | NetworkManager 1.52.1+rpt4 | An interface already configured when NM starts is marked external and left alone unless a profile matches, but NM has no NFS-root safeguard; `[keyfile] unmanaged-devices=interface-name:eth0` is strict; the nmcli command is valid, `ipv6.method disabled` exists since 1.20, higher `autoconnect-priority` wins; Pi OS's build carries netplan patches | https://sources.debian.org/data/main/n/network-manager/1.52.1-1/man/NetworkManager.conf.xml; https://archive.raspberrypi.com/debian/pool/main/n/network-manager/ | C17; stage 1; guard by `nmcli`, not by file path |
| F38 | Slurm in trixie | 24.11.5-4+deb13u1 | https://packages.debian.org/trixie/slurm-wlm | Phase 3 |
| F39 | tcpdump 4.99.5 output | DHCP requests print `BOOTP/DHCP, Request from <chaddr>`; TFTP prints `RRQ "<file>"` | https://raw.githubusercontent.com/the-tcpdump-group/tcpdump/tcpdump-4.99.5/print-bootp.c (lines 293-299); https://raw.githubusercontent.com/the-tcpdump-group/tcpdump/tcpdump-4.99.5/print-tftp.c (lines 114-122) | 30-add-node.sh parsing |
