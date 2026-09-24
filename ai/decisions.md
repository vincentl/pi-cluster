# Decisions

Open questions and settled decisions for the trixie refresh. Each open question has a default;
an unanswered question means "take the default and say so in the plan". Fill in `Answer:`
lines. Sessions append new questions at the bottom and record chat decisions here.

Must answer before Phase 1: D2, D3, D6, D9. The rest can ride on their defaults.

---

## D1. Target OS

Raspberry Pi OS Lite 64-bit, Debian 13 trixie (release 2026-09-15, kernel 6.18), for both the
head node and the compute image.
Default: yes.
Answer: yes (2026-09-22; it was the original goal).

## D2. Scope: does this refresh script Slurm?

`notes/slurm-mpi-shmem.md` covers munge, Slurm, mpich and portals4 by hand. Options:
(a) stop when compute nodes netboot, mount NFS, keep time and are reachable; Slurm is the
next refresh;
(b) also script munge and Slurm (`head/40-slurm.sh`, image side via `image-run.sh`,
`slurm.conf` generated from `cluster.env`); mpich and portals4 stay as notes;
(c) everything in the notes.
Default: (a), with (b) as Phase 3 once (a) is hardware-verified.
Answer: (b), 2026-09-22. Netboot first, then munge + Slurm as Phase 3. mpich and portals4 stay notes.

## D3. Hardware facts for the Parts and Assembly sections

Number of Pi 5s and RAM size; NVMe HAT model and SSD; switch model and port count; power
(PoE HAT, per-node supplies, other); case or rack; cooling; microSD card size; how the head
node reaches the internet (wifi assumed). `cluster.env` says `NODE_COUNT=32`: real count or
ceiling?
Default: none possible. The Parts table keeps its `TODO` cells until answered.
Answer (2026-09-22): all Raspberry Pi 5. Head node 4 GB; four compute nodes, 16 GB each.
Waveshare PoE HAT with active cooler on each node (a Raspberry Pi reference design built by
several vendors, per Vincent). RealHD 16-port PoE switch. Head node SSD: Inland TN320 512 GB
NVMe. No case yet. `NODE_COUNT=32` was a leftover ceiling and is dropped (D17). Head node
HAT and cooler: see D18.

## D4. DHCP/TFTP server

isc-dhcp-server is in trixie but labelled deprecated. dnsmasq does DHCP and TFTP in one
daemon and is what the Raspberry Pi netboot docs use; switching means rewriting the DHCP
config and `30-add-node.sh`.
Default: keep isc-dhcp-server + tftpd-hpa; the Readme notes the deprecation; revisit after Slurm.
Answer: switch to dnsmasq, 2026-09-22. One daemon for DHCP and TFTP, following the Raspberry
Pi netboot docs. isc-dhcp-server and tftpd-hpa are gone from the design.

## D5. Source of the compute image

Decided 2026-09-22 in chat: build `/image/pi5` on the head node from the official `.img.xz`
(`OS_IMAGE_URL` in `cluster.env`). No more moving the microSD back to the head node, and the
compute image no longer inherits head-node state (wifi credentials, hostname, password).
The microSD clone stays only for the head node's own move to NVMe.

## D6. Compute node boot order (EEPROM)

A Pi 5 is believed to ship with a boot order that excludes network boot (VERIFY in the rpi
docs). Which is true for your nodes?
(a) all compute nodes already have network boot enabled;
(b) each new node gets it once from an Imager bootloader card;
(c) each new node is booted from a microSD and set with `raspi-config`.
Determines whether Readme §4 keeps its EEPROM paragraph and figure 6.
Default: (b), as the Readme currently says.
Answer: (b), 2026-09-22. Readme §4 and figure 6 stay.

## D7. Head node Ethernet configuration

Decided 2026-09-22: NetworkManager connection via `nmcli`, no reboot. Replaces ifupdown.

## D8. Internet for compute nodes

Compute nodes cannot reach the internet. The head node could NAT the cluster network over wifi.
Default: no NAT. The Readme says software reaches nodes through the head node.
Answer: no NAT, 2026-09-22.

## D9. May the working session ssh into the cluster?

If yes, Claude runs `ssh pi-login …` from the workstation to deploy and verify, and writes
results to `ai/test-logs/`. If no, Claude prints commands and expected output and you paste
results.
Default: no.
Answer: no, 2026-09-22. Vincent runs every command and pastes output.

## D10. `manage.sh`

Decided 2026-09-22: delete in Phase 1. Its loop-mount pattern moves into `20-netboot.sh`.

## D11. Remote and CI

No git remote exists. A GitHub remote would allow a `shellcheck` workflow on push, `git clone`
on the head node instead of `scp`, and a public home for the Readme.
Default: local only; `make check` covers the same checks.
Answer: public GitHub repo, 2026-09-22. Opus creates it in Phase 0 after Vincent confirms the
name and license (D19), and adds a `make check` workflow in Phase 2. Deploy path per D20.
Update 2026-09-22, Phase 0: asked to create and push, Vincent said "not yet". The repo stays
local; ask again later, before the Phase 2 workflow at the latest. Still open at that point:
the eight commits carry his gmail address as author; a noreply rewrite is only possible before
the first push.
Update 2026-09-23, Phase 2: Vincent: "vincent.lucarelli@gmail.com is fine". The history keeps
it; no rewrite. The same day he chose D29 (a): this repo pushes to the private
`vincentl/pi-cluster-dev`, and the public `vincentl/pi-cluster` comes later with only the public
files.

## D12. Figures

Decided 2026-09-22: `docs/images/NN-name.ext` placeholders in the Readme, shot list in
`docs/images/README.md`. Vincent captures photos and screenshots; the session draws figure 1.
Update 2026-09-23, Vincent: both diagrams are Mermaid in the Readme, which GitHub renders (the
cluster overview, which replaces the planned SVG, and a new one of how a compute node boots).
Six photos from the 2025 build are used; Imager's User and bootloader screenshots are dropped;
Imager's Remote access screenshot stays. The files were renumbered, since none had been
committed; the list is in `docs/images/README.md`.

## D13. Settings file

Decided 2026-09-22: `cluster.toml` and the Python generator are retired. `cluster.env`
(KEY=value, sourced by bash) is tracked with real values; it holds no secrets.

## D14. Workstation platforms

Decided 2026-09-22: macOS, Linux and Windows 10+ are all supported. The workstation needs only
Raspberry Pi Imager and an OpenSSH client (`ssh`, `scp`, `ssh-keygen`). No scripts run on the
workstation; the repo is copied to the head node with `scp -r`.

## D15. Pi 5 network install

Decided 2026-09-22: a Pi 5 with no boot media can fetch Imager over the network and write the
NVMe directly, removing the microSD from the head node build. It needs a monitor and keyboard,
so it is mentioned in the Readme's Notes and not used.

## D16. TFTP root

Design decision, VERIFY in Phase 1: dnsmasq's `tftp-root` is `/image/pi5/boot`, with
per-serial symlinks to `firmware` inside it, so a kernel update in the image needs no sync
step. Fallback if the symlinks are refused: bind-mount `/image/pi5/boot` at `/srv/tftp`.

## D17. Node count

Decided 2026-09-22: no `NODE_COUNT`. `30-add-node.sh` registers each node in DHCP, in
`/etc/hosts` on the head node and in the image, and in the TFTP directory. The only ceiling is
254 addresses in `${NODE_SUBNET}.0/24`. Slurm's node list (Phase 3) is generated from the
registered nodes.

## D18. Head node HAT and power

Decided 2026-09-22: Geekworm X1012 PoE+ HAT with PCIe-to-M.2 NVMe adapter carries the Inland
TN320 and powers the head node from the PoE switch. Geekworm H505 active cooler. Compute nodes
use the Waveshare PoE HAT with active cooler. Every node powers on when plugged into the switch,
so the Readme says "connect to the switch" instead of "power on".

## D19. License

Decided 2026-09-22: MIT. `LICENSE` is in the tree, copyright Vincent Lucarelli.

## D20. Deploy path to the head node

Decided 2026-09-22: `scp -r` from the workstation during development. Near release, test
`git clone` of the public repo on the head node and running a script from the clone; the
Readme's Maintenance table already mentions `git pull` for that case.

## D21. Repo name

Decided 2026-09-22: `pi-cluster`, public, on Vincent's GitHub account.

## D22. Phase 1 plan

Decided 2026-09-22: Vincent approved `ai/plans/phase-1-head-scripts.md` as written, including
its changes C1–C20 to the kickoff prompt. The ones that are choices rather than facts:
cloud-init turned off on the head node so `/etc/hosts` keeps the node names (C2); the node
registry at `/etc/pi-cluster/nodes` (C1); no default route for compute nodes (C6); `PCIE_PROBE=1`
set by 10-nvme.sh (C16); rpi-swap zram only on the nodes (C17); Readme §5 run from the
workstation (C19). D16 is settled: dnsmasq follows the per-serial symlinks, so no bind mount.

## D23. Agent forwarding to the head node

Decided 2026-09-22: the Readme's ssh config sets `ForwardAgent yes` for `Host pi-login` only, so
`ssh pi-001` works from the head node while the key is in the workstation's agent, and
`AddKeysToAgent yes` for `Host pi-*`, so the key is in the agent after the first connection. Compute
nodes are still reached with ProxyJump, which needs no forwarding. A key made on the head node,
for jobs that ssh between nodes, is left for Phase 3.

## D24. EEPROM write in 10-nvme.sh

Decided 2026-09-22, during the Phase 2 hardware test: 10-nvme.sh sets `PCIE_PROBE=1` only when
the PCIe slot had to be enabled in `config.txt`, meaning the adapter is not HAT+. The X1012 is
detected as HAT+ (test log 2.1), and the old setup booted from NVMe without `PCIE_PROBE`, so on
this hardware the EEPROM is left alone. This changes C16 of the Phase 1 plan.

## D25. How 10-nvme.sh copies the card

Decided 2026-09-22, during the Phase 2 hardware test: 10-nvme.sh makes fresh file systems on the
NVMe drive and copies the running system with rsync. This replaces partclone's block copy of the
mounted root, which partclone refuses without `-F` and which needed e2fsck repairs afterwards.
Vincent chose this over writing the SSD with Imager through a USB adapter, a part he would use
only once. `--force` copies again when the drive already holds a finished copy of the same
system.

## D26. Replacing a node's board

Added 2026-09-23, after Vincent asked how to swap the board behind a node number:
`30-add-node.sh N --replace` forgets the registered board (registry line, serial link, DHCP
lease) and registers the new one under the same number and address. It is documented in the
Readme's Maintenance table and in checklist item 4.8.

## D27. NFS client helpers in the image

Decided 2026-09-23, during the Phase 2 hardware test: 20-netboot.sh masks nfs-common's
`rpc-statd-notify` and `nfs-blkmap` in the image. Each logged an error at every node boot (test
log, 5.8). sm-notify tells NFS servers that this client restarted, so they drop its NFSv3 locks;
the nodes hold none (the root is mounted `nolock`, `/home` and `/opt` are NFSv4.2), and its list
lives in `/var/lib/nfs`, which is empty RAM on a node. blkmapd serves pNFS block layouts, which
the head node's exports do not offer. The other lines in the same check, two udev warnings from a
typo in the stock alsa-utils rule, are left alone and listed as expected in `docs/testing.md`.
The Phase 1 plan (F22) expected the sm-notify failure and relied on systemd ignoring it; the mask
also keeps it out of the error log. Sources: Phase 1 plan, stage 4i. Verified on nodes 1-3 the
same day: both units `masked`, and 5.8 shows only the alsa lines.

## D28. Which nodes image-run.sh reports as running

Decided 2026-09-23, before item M.2: `image-run.sh` still finds nodes by their established NFS
connections (C15), and now names only the addresses that also answer one ping. After a node is
unplugged, the head node's NFS server keeps its connection until two 6-minute idle sweeps have
passed, so the old check warned about unplugged nodes for up to 12 minutes, exactly when the
Readme says to power them off. Sources: Phase 1 plan, `head/image-run.sh`.

## D29. What is published, and how

Raised 2026-09-23 by Vincent: `docs/testing.md`, `notes/` and `ai/` are for us, not readers.
Public: `Readme.md`, `LICENSE`, `cluster.env`, `head/`, the figures in `docs/images/`,
`Makefile`, `.shellcheckrc`, `.github/`, `.gitignore`. Private: `ai/`, `notes/`,
`docs/testing.md`, `CLAUDE.md`, `docs/images/README.md`. The public files no longer link to
private ones (Readme Status line, file tree, section 5, Slurm section; the Makefile comment).
The history already holds `ai/`, `notes/` and `CLAUDE.md` (from `2e628cb`), so pushing this
repo as it is would publish them. Options:
(a) keep this repo private with its full history (a private GitHub repo gives a backup and
runs CI), and create the public `vincentl/pi-cluster` fresh from the public files, copying
them over at each release;
(b) one public repo: rewrite the history to drop the private paths before the first push, and
keep the private files in a separate private repo beside it.
Default: (a), with the first public release after Phase 3 (Slurm), since the Readme's first
line promises a Slurm cluster.
Answer: (a), 2026-09-23. This repo's remote is the private
`git@github.com:vincentl/pi-cluster-dev.git`, which Vincent created. The public repo comes when
the whole setup is nearly complete, after Phase 3; there is no hurry.
