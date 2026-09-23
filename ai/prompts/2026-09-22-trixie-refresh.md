# Kickoff: trixie refresh

You are working in `/Users/vincent/pi-cluster`, a repo for building a Raspberry Pi 5 Slurm
cluster: a head node booting from NVMe that serves DHCP, TFTP, NFS and time to compute nodes
that network-boot a read-only NFS root. A planning session audited the repo on 2026-09-22 and,
with Vincent, decided to retire the Python generator and its templates in favour of one settings
file, `cluster.env`, and plain bash scripts in `head/`. The new `Readme.md` was written first
and is the specification. Your job is to make it true, phase by phase, committing at each
phase boundary.

## Read first, in this order

1. `CLAUDE.md`. Standing rules.
2. `Readme.md`. The spec. Every command, path, and behaviour it names is a requirement. Where
   you cannot make it true, change the Readme in the same commit and list the change in the
   plan file.
3. `ai/decisions.md`. Every question was answered on 2026-09-22. Treat them as settled and
   append new ones as they arise.
4. `ai/audit/2026-09-22-repo-audit.md`. Section 3 lists the bugs and trixie problems in the
   old scripts; every one of them applies to the logic you port. Section 2 is moot.
5. `cluster.env`, `notes/`, `docs/images/README.md`.
6. The code being retired, for the logic only: `templates/setup/*.sh`, `stage-1.py` (how it
   generated `hosts` and `dhcpd.conf`), `manage.sh` (the loop-mount pattern).

## Ground rules

- Never run anything from `head/` on this workstation.
- D9 is answered no: never ssh to the cluster. Give the exact commands, the expected output
  and a pass/fail criterion, then wait for the pasted result.
- Do not state Raspberry Pi bootloader, Imager, kernel, or Debian trixie behaviour from memory.
  Fetch the current doc or package page and cite the URL in the plan file. Phase 1 lists the
  places where this matters.
- Bash only. No new languages, no configuration-management frameworks. Any new package on the
  head node needs a one-line reason in the plan.
- Prefer deleting a step to adding one. Count the human steps in the Readme before and after
  each phase and keep the number in the plan.
- One commit per phase (Phase 0 makes two). Body: what changed, what was verified on
  hardware, or the words "not hardware-tested".
- Write `ai/plans/phase-N-<slug>.md` before editing, and get Vincent's OK on the Phase 1 plan
  before writing scripts. Record every decision he makes in chat in `ai/decisions.md`.
- Stop and ask when a blank decision turns out to matter, when a change would alter the
  network layout, and before anything destructive.

## Phase 0: commit the baseline. No behaviour changes.

Two commits so history shows what was on disk before the redesign.

1. Snapshot. Stage only `stage-1.py`, `templates/`, `manage.sh`. Commit
   "Snapshot: netboot from microSD clone, add-node serial capture" with the diff summary from
   audit §1 as the body.
2. Plan. Add `.gitignore` with `setup/`, `instructions.txt`, `__pycache__/`, `*.pyc`,
   `.DS_Store`, `*.img`, `*.img.xz`. Stage `.gitignore`, `Readme.md`, `CLAUDE.md`,
   `cluster.env`, `LICENSE`, `ai/`, `notes/`, `docs/`. Commit
   "Plan the trixie refresh: Readme as spec, cluster.env, AI docs".

3. Remote (D11, D19). `LICENSE` (MIT) is already in the tree. Confirm with Vincent that he is
   ready, then `gh repo create pi-cluster --public --source . --push`. Never force-push.

Done when `git status` is clean and `git remote -v` shows GitHub. Delete nothing yet.

## Phase 1: build `head/` to match the Readme

Plan file first: `ai/plans/phase-1-head-scripts.md`. For each script, its stages and the
guard for each; which lines of the old scripts it ports; and a table of trixie facts with
source URLs (list below). Get the OK, then write the scripts.

### `head/lib.sh`
Sourced by every script. `set -euo pipefail`; find the repo root from `$0`; source
`cluster.env`; `log`, `die`, `need_root`; derived values `IMAGE=/image/pi5`,
`NODE_NET=${NODE_SUBNET}.0/24`; `node_name N` (zero-padded to three digits) and `node_ip N`.

### `head/10-nvme.sh`
Runs from the microSD. Exit 0 with a message if `/` is already on NVMe. If no NVMe block
device is present, add `dtparam=nvme` to `/boot/firmware/config.txt`, tell the user to run the
script again after the reboot, and reboot. Install `partclone`. Detect the card and the NVMe
device with `lsblk`, not `df` and `basename` tricks. Confirm before overwriting. Port the
partition, clone, resize and PARTUUID logic from `templates/setup/nvme-setup.sh:34-58`. Finish
by printing the next two Readme commands.

### `head/20-netboot.sh`
Runs from NVMe; refuse if `/` is on the microSD. Stages, each guarded:

1. Network. A NetworkManager connection on `eth0` with `$HEAD_IP/8`, no gateway,
   `ipv4.never-default yes`, IPv6 disabled. No reboot.
2. Packages: `dnsmasq nfs-kernel-server chrony tcpdump xz-utils curl rsync systemd-container`.
   Drop `ntp` (not in trixie), `ifupdown`, `net-tools`, and the old `isc-dhcp-server` and
   `tftpd-hpa` (D4: dnsmasq does DHCP and TFTP).
3. Head node config, written with heredocs from `cluster.env`, each with a generated-by
   header: `/etc/hosts` (head node only; `30-add-node.sh` appends compute nodes);
   `/etc/dnsmasq.d/cluster.conf` with `interface=eth0`, `bind-interfaces`, `port=0` (no DNS),
   a static-only `dhcp-range` for `$NODE_SUBNET`, the options a Pi 5 needs to netboot taken
   from the rpi docs (vendor class "Raspberry Pi Boot", TFTP server), `dhcp-option=option:ntp-server,$HEAD_IP`,
   `enable-tftp`, `tftp-root=$IMAGE/boot`, and `dhcp-hostsfile=/etc/dnsmasq.d/cluster-nodes.hosts`
   so `30-add-node.sh` appends one `dhcp-host`-format line per node and reloads with SIGHUP
   while this script can rewrite `cluster.conf` freely; `/etc/chrony/conf.d/cluster.conf` with
   `allow $CLUSTER_NET`. Enable and restart the services.
4. Image. If `$IMAGE/etc/os-release` is missing: download `$OS_IMAGE_URL` to
   `/var/cache/pi-cluster/` (`curl -L -C -`, skip if present), decompress, `losetup -P`, mount
   the second partition and then the first at `boot/firmware` inside it, rsync into `$IMAGE`,
   unmount and detach under a `trap`. This replaces the microSD clone and the physical card
   juggling.
5. Image configuration, each guarded: fstab (NFS root ro, `/opt` ro, `/home` rw, tmpfs for
   `/tmp`, `/var`, `/media`; keep what trixie's systemd does not already mount); netboot
   `cmdline.txt` in `$IMAGE/boot/firmware/` without `systemd.unified_cgroup_hierarchy=1`;
   `MODULES=netboot` and wifi/bluetooth blacklist, then `image-run.sh update-initramfs -u`;
   copy `passwd`, `shadow`, `group`, `gshadow` from the head node so `$CLUSTER_USER` has the
   same uid and can sudo; disable the first-boot, user-config and ssh-host-key-regeneration
   services in the image and generate host keys once with `image-run.sh ssh-keygen -A`;
   remove `/etc/hostname` (DHCP supplies it); `/etc/hosts` matching the head node's; empty
   `/etc/machine-id`; `/etc/mtab` symlink and the tmpfiles `L+` fix from the old script;
   `systemctl --root=$IMAGE disable rpcbind`; time source for the nodes (see verification
   list); tmpfiles.d entries for anything that writes under tmpfs `/var`.
6. Exports for `$IMAGE`, `/opt`, `/home` to `$NODE_NET`; `exportfs -ra`; print `showmount -e`.

Serial-number boot directories are symlinks inside `$IMAGE/boot` pointing at `firmware`, so
TFTP serves the image's own `/boot` and nothing needs syncing when the image's kernel updates.

### `head/30-add-node.sh N`
Validate `1 <= N <= 254`. If the node is already in `cluster-nodes.hosts`, say so and
skip to the symlink check. Capture the MAC with `tcpdump` on `eth0`, ignoring MACs already
registered so a rebooting neighbour is not mistaken for the new node. Append the node's `dhcp-host` line to `cluster-nodes.hosts`,
add the node to `/etc/hosts` on the head node and in `$IMAGE/etc/hosts` (idempotent; the
image copy is live on running nodes over NFS), reload dnsmasq, capture the serial from the node's first TFTP RRQ, `ln -sfn firmware
$IMAGE/boot/<serial>`. No `sudo` inside; no undefined variables. Print the MAC, serial, name,
address, and `ssh <name> uptime`.

### `head/image-run.sh [command…]`
`systemd-nspawn -q -D $IMAGE` with `--bind=/opt`, `--resolv-conf=replace-host`, running the
command or an interactive shell. Without `--boot`; confirm `apt full-upgrade` and
`update-initramfs` work that way. Warn if any node currently holds an NFS lease. Under 30 lines.

### Delete
`git rm` `stage-1.py`, `utils.py`, `templates/`, `cluster.toml`, `manage.sh`; remove `setup/`,
`instructions.txt`, `__pycache__/`. Update the "being retired" line in `CLAUDE.md`.

### Verify with sources before writing (put the table in the plan)
- Pi 5 default `BOOT_ORDER` and whether it includes network boot; the Imager bootloader image
  name and the LED signal. Fix Readme §4 wording if needed.
- Whether trixie enables the PCIe connector automatically when an NVMe is present. If yes,
  delete the `dtparam=nvme` stage and the sentence in Readme §2.
- NetworkManager is the default on Lite; the `nmcli` form above; whether NetworkManager on a
  netbooted node fights `ip=dhcp` (mark `eth0` unmanaged if so).
- Which of `cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 swapaccount=1` the 6.18
  Pi kernel still needs for Slurm cgroup constraints.
- `initramfs-tools` honours `MODULES=netboot`; where `update-initramfs` writes on Pi OS trixie
  and that TFTP serves that file.
- Time on the nodes: `systemd-timesyncd` on trixie takes NTP servers from DHCP only through
  `systemd-networkd`, not NetworkManager. If that holds, a `timesyncd.conf.d` drop-in with
  `NTP=$HEAD_IP` is the reliable path; keep the DHCP option anyway.
- dnsmasq: the exact DHCP options a Pi 5 needs to netboot, from
  https://www.raspberrypi.com/documentation/computers/remote-access.html#network-boot-your-raspberry-pi;
  that its TFTP server follows the per-serial symlinks under `tftp-root`; that
  `dhcp-hostsfile` is re-read on SIGHUP and `systemctl reload dnsmasq` sends it.
- The Imager customisation screens match the Readme §1 table.
- `raspios_lite_arm64_latest` redirects to the current `.img.xz`.

Done when: `shellcheck head/*.sh` is clean; every Readme command exists and behaves as
written or the Readme was changed and the change is listed; the plan table has a source for
every row; the retired files are gone; the commit says what was hardware-verified.

## Phase 2: test and reconcile

- `Makefile` with `check` (`shellcheck` and `bash -n` over `head/*.sh`; install shellcheck
  with the workstation's package manager). Remove the "planned" marker in `CLAUDE.md`.
- `.github/workflows/check.yml` running `make check` on every push (D11).
- `docs/testing.md`: one checklist per Readme section, each item a command, expected output,
  pass criterion and rough duration. Cover: head node boots from NVMe with the card out;
  `eth0` has `$HEAD_IP`; the three services active; `showmount -e`; a TFTP fetch of
  `firmware/config.txt`; a new node gets its lease and symlink; the node's mounts,
  `timedatectl`, `/proc/cmdline`; a rerun of each script is a no-op; `image-run.sh apt
  full-upgrade -y` followed by a node reboot.
- `ai/test-logs/YYYY-MM-DD.md`: date, commit, image release date, checklist results, and the
  time from blank card to first compute node up.
- Run the full procedure once on the real hardware (per D9) and log it. Failures go back to
  Phase 1, get fixed, and the log is updated.
- Deploy path (D20): `scp` is the documented path during development. Before removing the
  Status note, have Vincent test `git clone` of the public repo on the head node and run one
  script from the clone; if it works, the Maintenance table's `git pull` row stays.
- Reconcile the Readme with the run: real output in section 5 and the troubleshooting section;
  remove the Status note at the top; finalise `docs/images/README.md`.

Done when `make check` passes, one hardware run is logged, and the Readme has no Status note.

## Phase 3: Slurm (D2 answered b)

`head/40-slurm.sh` on the head node and an image-side script run through `image-run.sh`,
from `notes/slurm-mpi-shmem.md`. `slurm.conf` and `cgroup.conf` generated from `cluster.env`
plus per-node CPU and memory values added to it. munge key generated on the head node and
copied into the image. tmpfiles.d entries for munge and slurmd. Add `sinfo` and
`srun -N1 hostname` to `docs/testing.md` and a Slurm section to the Readme. Plan, OK,
implement, commit.

## Definition of done for the whole refresh

- `git log` shows one commit per phase, each saying what was hardware-verified.
- `make check` passes locally and in GitHub Actions.
- The Readme has fewer human steps than the 2026-09-22 generated instructions (which had five
  numbered steps and two reboot-and-rerun cycles) and no Status note.
- Every figure in `docs/images/README.md` has a placeholder in the Readme.
- `ai/decisions.md` has an answer or an explicit "took default" for every question.
- One entry in `ai/test-logs/`, or a clear statement of which checklist items are unrun and why.
