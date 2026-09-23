# Repo audit — 2026-09-22

> **Addendum, later the same day.** After this audit, Vincent decided to retire the Python
> generator and its templates in favour of `cluster.env` plus bash scripts in `head/`, with
> `Readme.md` written first as the spec. Section 2 below is therefore moot. Section 3 still
> matters: every finding there applies to the script logic being ported. Sections 1 and 4–8
> stand as the record of what was on disk before the change.

State of `pi-cluster` before the trixie refresh. Facts with `file:line` refer to the working
tree on this date (uncommitted changes included). Items marked VERIFY were not checked on
hardware or against a primary source.

## 1. Git state

- Last commit `c43582d` on 2025-02-01 ("just before removing wifi power management"). No remote.
- No `.gitignore`.
- Modified, uncommitted: `Readme.md`, `stage-1.py`, `templates/msgs/head-node-nvme-setup.txt`,
  `templates/msgs/network-boot.txt`, `templates/setup/{add-node.sh,network-boot.sh,nvme-setup.sh}`.
- Untracked: `__pycache__/`, `instructions.txt`, `setup/` (all generated output),
  `manage.sh` (helper, see §5), `templates/msgs/add-node.txt` (new step, must be tracked).
- `setup/` on disk is STALE: generated from older templates (still has "update hosts",
  lacks the mtab fix and the new fstab). Proof that it is output, not source.

What the uncommitted diff does (worth preserving in the snapshot commit message):
- Removes the wifi power-management unit from `network-boot.sh`.
- Moves the `/etc/hosts` copy from `network-boot.sh` to `nvme-setup.sh` (so it lands on the
  microSD before cloning) and enables `AllowAgentForwarding` there.
- Adds `ntp` install, cgroup kernel args on the netboot cmdline, the `/etc/mtab` symlink fix,
  tmpfs mounts for `/tmp /var /run /media`, an `/opt` NFS export and mount, and
  `FallbackNTP=10.0.0.1` in the compute image.
- Rewrites `add-node.sh` to take a plain integer, capture the node MAC from DHCP, restart dhcpd,
  then capture the Pi serial from the first TFTP RRQ and symlink `/srv/tftp/<serial> -> firmware`.
- Adds the `add-node.txt` instruction step to `stage-1.py`.
- Replaces the Readme's dead notes with munge/Slurm/mpich/portals4 working notes.

## 2. Generator (`stage-1.py`, `utils.py`)

- `stage-1.py:86-94` writes `dhcpd.conf` twice (copy-paste).
- `stage-1.py:62` and `:70` both `makedirs` the same dir.
- `stage-1.py:20` imports `re` but never uses it.
- `stage-1.py:1-16` docstring names `pi-cluster.toml` and is an unfinished outline.
- `utils.py:19` opens `templates/{kind}/{name}` relative to CWD: the generator only works from
  the repo root. Use `pathlib.Path(__file__).parent`.
- `utils.py:13` a missing key raises a bare `KeyError` with no template name or line.
- IPs (`10.0.0.1`, `10.0.1.N`, `/8`, `10.0.1.0/24`) are hard-coded across `stage-1.py:82-84`,
  `templates/setup/{add-node.sh,dhcpd.conf,network-boot.sh}`. Not in `cluster.toml`.
- `templates/msgs/compute-node-mac.txt` is not in the step list at `stage-1.py:51-57`. It
  describes the older flow (boot each node from microSD, record MAC into a `[node]` toml
  section, set boot order with `raspi-config`). No `[node]` section exists anywhere. It is dead
  unless the boot-order step is still needed (see decisions D6).
- Requires Python >= 3.11 (`tomllib`). The Mac has 3.14.6.

## 3. Templates: scripts

General: no script sets `set -euo pipefail`; all run via `sudo` on the head node.

### `templates/setup/nvme-setup.sh`
- `:8-15` appends `dtparam=nvme` and reboots; the user must ssh back and rerun. Could be avoided
  by editing `config.txt` on the freshly flashed card from the Mac before first boot (VERIFY the
  FAT partition mounts on macOS: it does for Imager-written cards).
- `:19` `rsync hosts /etc/hosts` needs `hosts` scp'd first (instructions do that).
- `:23-24` device detection by `df | grep /boot/firmware` and `basename … p1` trick. Fragile.
- `:41-43` clones the LIVE root partition with `partclone.ext4 -F`. Works on an idle system.
  Alternatives: write the NVMe from the Mac through a USB adapter, or `rpi-imager --cli` on the Pi.
- `:52-58` patches PARTUUIDs in `fstab` and `cmdline.txt`. Fine.

### `templates/setup/network-boot.sh`
- `:10` uses `ifconfig` (net-tools). Prefer `ip -o link`. net-tools exists in trixie
  (2.10-1.3) but VERIFY it is installed by default on Lite.
- `:11-26` configures `eth0` with ifupdown and REBOOTS. Raspberry Pi OS has used NetworkManager
  since bookworm; `nmcli con add type ethernet ifname eth0 ipv4.method manual
  ipv4.addresses 10.0.0.1/8 …` needs no reboot. Removes one reboot-and-rerun cycle.
- `:29` and `:37` `if ! $(dpkg-query … | grep -q …)` executes the (empty) output of the
  substitution; it works by accident. Use `if ! dpkg-query … | grep -q …`.
- `:43` `apt install -y ntp`. The `ntp` package is not in trixie (packages.debian.org:
  "not available in this suite", 2026-09-22); `ntpsec` 1.2.3 is. Pick `ntpsec` or `chrony`
  explicitly and configure it to serve `10.0.0.0/8`.
- `:46-49` seeds `/srv/tftp` from the head node's `/boot` (ext4 `/boot` plus the mounted
  `firmware/`). Invariant, undocumented: `/srv/tftp/firmware` must match the kernel/modules in
  `/image/pi5`. The nspawn recipe in the Readme keeps it true by binding `/srv/tftp` to `/boot`
  inside the container. Make this explicit (bind mount in the head node fstab, or a documented
  `sync-image.sh`).
- `:48` cmdline has `systemd.unified_cgroup_hierarchy=1` (obsolete on systemd >= 256; trixie
  ships 257) and `cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 swapaccount=1`
  (VERIFY still needed on kernel 6.18 for Slurm cgroup constraints).
- `:56-57` mounts the microSD FAT partition at `/mnt/microsd/boot`. Since bookworm the FAT
  partition belongs at `/boot/firmware`. Result: FAT contents land in `/image/pi5/boot/` instead
  of `/image/pi5/boot/firmware/`, and the ext4 `/boot` files (`vmlinuz-*`, `initrd.img-*`) are
  hidden by the mount and never copied. Masked at netboot because the kernel comes from tftp,
  but the image's own `/boot` is wrong. VERIFY on hardware.
- `:66` `MODULES=netboot` in initramfs.conf. Correct for NFS root; VERIFY trixie's
  `initramfs-tools` still honours it and that `update-initramfs` is run afterwards (it is only
  run in the Readme's manual nspawn recipe).
- `:75-76` `ASYNCMOUNTNFS`/`RAMTMP` are sysvinit-era knobs; systemd ignores `RAMTMP`. The fstab
  tmpfs lines at `:99-110` already do the job. Drop.
- `:94-95` removes rpcbind symlinks by hand. Use `systemctl --root=/image/pi5 disable rpcbind`.
- `:99-110` fstab: root is `nfs … v4` while cmdline uses `nfsroot=…,vers=3`. Cosmetic but
  confusing. `/var` is tmpfs, so every service needing `/var/lib/*` or `/var/log/*` (munge,
  slurmd, ntp) needs a `tmpfiles.d` entry; the Readme notes cover munge only.
- `:113` appends `FallbackNTP=` to `timesyncd.conf`. Handing out `option ntp-servers 10.0.0.1;`
  in `dhcpd.conf` is cleaner and makes the image OS-agnostic.
- `:117-125` exports `/home` rw with `no_root_squash` to the cluster subnet. Acceptable for a
  home lab; say so in the Readme.
- Compute nodes have no route to the internet (no NAT on the head node). Packages reach the
  image through nspawn on the head node, so this is fine unless jobs need the internet (D8).

### `templates/setup/add-node.sh`
- `:14` `INTERFACE` is defined and never used; `:19` and `:56` hard-code `eth0`.
- `:49` calls `sudo` inside a script that already runs as root.
- `:51` prints `$IP_PREFIX.$IP_SUFFIX`, both undefined.
- Not idempotent: re-running for the same node appends a second `host` block (dhcpd then fails
  to start) and `ln -s` at `:57` errors if the link exists.
- Race: the serial capture at `:56` starts after dhcpd restarts; if the node's first TFTP
  request beats tcpdump, the script waits for the retry (Pi bootloader retries, so usually fine).
- Does not touch `/etc/hosts` (pre-generated for all `node-count` nodes: fine) or any future
  `slurm.conf` node list.
- Depends on the compute node's EEPROM boot order including network boot. Pi 5 default
  BOOT_ORDER is believed to be SD, NVMe, USB only. VERIFY at
  https://www.raspberrypi.com/documentation/computers/raspberry-pi.html#BOOT_ORDER (fetch
  failed on 2026-09-22; read it in a browser). See D6.

### `templates/setup/dhcpd.conf`, `isc-dhcp-server`, `hosts`
- Static leases only, `/8` subnet, Pi netboot vendor options. Fine.
- isc-dhcp-server 4.4.3-P1-8 is in trixie, description "(deprecated)". Still works. dnsmasq
  would replace both it and tftpd-hpa (D4).
- `hosts` gets `node-count` entries (`10.0.1.N pi-NNN`) regardless of which nodes exist.

## 4. Templates: messages

- `head-node-nvme-setup.txt:9` typo "nvem-setup.sh". `network-boot.txt:12` typo "NMVe".
  `ssh-key-missing.txt:2` "At least on".
- `network-boot.txt:5` still scp's `hosts` although `network-boot.sh` no longer uses it.
- `rpi-imager.txt` describes the pre-2025 Imager UI ("Edit Settings"). Imager 2.x renamed and
  reordered the customisation screens. VERIFY against the installed Imager and re-screenshot.
- `ssh-config.txt` relies on the home router resolving `pi-login`; `pi-login.local` (mDNS) is
  the portable form. Mention both.
- The step list has no verification step ("how do I know it worked?") anywhere.

## 5. `manage.sh`

Untracked, unreferenced. Adapted from `sdm`'s nspawn helper: loop-mounts a Raspberry Pi `.img`
(`p1` on `boot` or `boot/firmware`, `p2` on `/`) and `systemd-nspawn`s into it. Useful only if
the compute image is built from a downloaded `.img.xz` instead of the physical microSD (D5, D10).
`:50` reads `$(tty)` which breaks when run non-interactively.

## 6. `Readme.md`

- Skeleton headings with no content: Introduction, Parts (one item), Physical Assembly,
  Preliminary Configuration, "Create a cluster.toml file".
- `:28` opens a `bash` fence that only closes at `:160`, so the References section renders as
  code.
- `:28-152` are working notes, not a procedure: munge key + Slurm install on head and image,
  `slurm.conf` via `include /opt/slurm/…` (the conf itself is never written: "slurm configurator"
  placeholder at `:58`), prolog/epilog scripts (`/opt/slurm/scripts` is never `mkdir`'d), the
  nspawn command that configures the compute image, `update-initramfs -u`, mpich, portals4 build.
  A stray `scontrol update NodeName=b02` at `:133`.
- Nothing states the architecture, the network layout, what runs where, or how to verify.

## 7. Environment facts checked on 2026-09-22

| Fact | Value | Source |
|------|-------|--------|
| Raspberry Pi OS Lite 64-bit | Debian 13 trixie, released 2026-09-15, kernel 6.18 | raspberrypi.com/software/operating-systems |
| `isc-dhcp-server` in trixie | 4.4.3-P1-8, "(deprecated)" | packages.debian.org/trixie |
| `tftpd-hpa` in trixie | 5.2+20240610-3 | packages.debian.org/trixie |
| `ntp` in trixie | not available | packages.debian.org/trixie |
| `ntpsec` in trixie | 1.2.3+dfsg1-8 | packages.debian.org/trixie |
| `net-tools` in trixie | 2.10-1.3 (exists; default-installed status unknown) | packages.debian.org/trixie |
| Pi 5 default BOOT_ORDER | VERIFY (fetch failed) | rpi docs, `#BOOT_ORDER` |
| Workstation Python | 3.14.6 | `python3 --version` |

## 8. Gaps the next phase must close

1. `.gitignore`, snapshot commit, notes out of the Readme.
2. trixie corrections: network config, time service, cgroup args, `/boot/firmware` layout in the
   image copy, Imager UI.
3. Reboot-and-rerun cycles: two today (`dtparam=nvme`, ifupdown). Both avoidable.
4. Card juggling: microSD goes Mac -> head node -> removed -> re-inserted for the image copy.
5. Idempotency and error handling in all three scripts.
6. A Readme that a competent stranger can follow, with a figure list.
7. Any automated test at all, plus a hardware checklist.
8. Slurm remains unscripted (scope: D2).
