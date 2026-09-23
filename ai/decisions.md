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

## D12. Figures

Decided 2026-09-22: `docs/images/NN-name.ext` placeholders in the Readme, shot list in
`docs/images/README.md`. Vincent captures photos and screenshots; the session draws figure 1.

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
