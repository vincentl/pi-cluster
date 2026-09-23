# Raspberry Pi 5 Cluster

A small [Slurm](https://slurm.schedmd.com/) cluster built from Raspberry Pi 5 boards.
One head node boots from an NVMe drive and provides everything else. Compute nodes have
no storage of their own: they boot over the network and share a single read-only operating
system, so adding a node is one command and one cable.

> **Status:** this guide describes the target procedure. The scripts in `head/` are being
> rewritten for Raspberry Pi OS trixie; see `ai/` for the plan.

![Figure 1: cluster overview](docs/images/01-overview.svg)

## How it works

|                 | Head node                                              | Compute node N                            |
|-----------------|--------------------------------------------------------|-------------------------------------------|
| Boots from      | NVMe                                                   | The network: TFTP, then an NFS root       |
| Root filesystem | NVMe, read-write                                       | `/image/pi5` on the head node, read-only  |
| `/home`         | Local                                                  | Shared from the head node, read-write     |
| `/opt`          | Local                                                  | Shared from the head node, read-only      |
| `/tmp`, `/var`  | Local                                                  | RAM                                       |
| Network         | Wifi to the internet; `eth0` at 10.0.0.1 to the switch | `eth0` at 10.0.1.N                        |
| Runs            | DHCP, TFTP, NFS, time, Slurm controller                | Slurm worker                              |

Because `/home` is shared, your files and your ssh key are the same on every node.
Compute nodes have no internet access; software reaches them through the head node.

Your workstation needs only Raspberry Pi Imager and an OpenSSH client, on macOS, Linux or
Windows. Everything else is a handful of bash scripts that run on the head node and read one
settings file, `cluster.env`. Every script can be run again safely: finished steps are skipped.

```
pi-cluster/
├── cluster.env          your settings: user, hostnames, addresses, OS image
├── head/
│   ├── 10-nvme.sh       copy the head node from microSD to NVMe
│   ├── 20-netboot.sh    turn the head node into a network boot server
│   ├── 30-add-node.sh   register one compute node
│   ├── image-run.sh     run a command inside the compute node image
│   └── lib.sh           shared by the scripts above
├── docs/                figures and the hardware test checklist
└── notes/               working notes not yet turned into scripts
```

## Parts

| Part                                          | Notes                                                            |
|-----------------------------------------------|------------------------------------------------------------------|
| Raspberry Pi 5, 4 GB                          | Head node                                                        |
| Raspberry Pi 5, 16 GB, × 4                    | Compute nodes                                                    |
| Geekworm X1012 PoE+ HAT with M.2 NVMe adapter | Head node: power from the switch, and the SSD slot               |
| Inland TN320 512 GB NVMe SSD                  | Head node system drive                                           |
| Geekworm H505 active cooler                   | Head node                                                        |
| Waveshare PoE HAT with active cooler, × 4     | Compute nodes: power from the switch, and cooling                |
| RealHD 16-port PoE switch                     | Connects and powers every node                                   |
| Ethernet cable, × 5                           |                                                                  |
| microSD card, 8 GB or more                    | Installs the head node, then sets each compute node's bootloader |
| Case or rack                                  | None yet                                                         |

## Assembly

1. Head node: fit the X1012 HAT with the SSD in its M.2 slot, and the cooler.
2. Compute nodes: fit a PoE HAT with cooler to each.
3. Power the switch. Nothing but the nodes connects to it, not even your home router; the head
   node reaches the internet over wifi.
4. Do not connect the nodes yet. A node powers on the moment it is plugged into the switch, and
   the steps below say when.

![Figure 2: assembled cluster](docs/images/02-assembled.jpg)
![Figure 3: head node with NVMe HAT](docs/images/03-head-node.jpg)

## Before you start

On the workstation:

1. Make an ssh key for the cluster.

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/pi-cluster
   ```

2. Add this to `~/.ssh/config` (on Windows, `C:\Users\<you>\.ssh\config`). It lets you type
   `ssh pi-login` or `ssh pi-001` from anywhere; compute nodes are reached through the head node.

   ```
   Host pi-login
       HostName pi-login.local
   Host pi-* !pi-login
       ProxyJump pi-login
   Host pi-*
       User pi
       IdentityFile ~/.ssh/pi-cluster
   ```

3. Clone or download this repository and edit `cluster.env`. The defaults give you user `pi`, head node
   `pi-login`, and compute nodes `pi-001`, `pi-002` and so on. If you change the user or hostnames,
   change them in the ssh config above and in Imager below as well.

## 1. Flash the head node card

Write the microSD card with [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Its
screens, in order:

| Screen               | Choose                                                                       |
|----------------------|------------------------------------------------------------------------------|
| Device               | Raspberry Pi 5                                                               |
| OS                   | Raspberry Pi OS (other) → Raspberry Pi OS Lite (64-bit)                      |
| Storage              | The microSD card                                                             |
| Hostname             | `pi-login`, the `HEAD_NODE` in `cluster.env`                                 |
| Localisation         | Your capital city, time zone and keyboard layout                             |
| User                 | `pi`, the `CLUSTER_USER` in `cluster.env`, and a password                    |
| Wi-Fi                | Your wifi network and its password. This is the head node's link to the internet |
| Remote access        | Enable SSH, use public key authentication, and add the contents of `~/.ssh/pi-cluster.pub` |
| Raspberry Pi Connect | Leave it off                                                                 |

![Figure 4: Imager User screen](docs/images/04-imager-user.png)
![Figure 5: Imager Remote access screen](docs/images/05-imager-remote-access.png)

Put the card in the head node and connect it to the switch, which powers it. After a minute
or two:

```bash
ssh pi-login uptime
```

If `pi-login.local` does not resolve on your network, find the head node's address in your
router and use it as `HostName` in the ssh config.

## 2. Move the head node to NVMe

Copy the repository to the head node and run the first script. It enables the NVMe slot
(if that needs a reboot, it reboots and asks you to run it again), tells the bootloader to
look for the NVMe drive, copies the running system to the drive, and grows the root partition
to fill it. It asks before it erases the drive, and `sudo` asks for the password you gave
Imager.

```bash
# workstation, from the directory that contains pi-cluster
scp -r pi-cluster pi-login:
ssh pi-login
```

```bash
# pi-login
sudo bash pi-cluster/head/10-nvme.sh
sudo shutdown now
```

Unplug the head node from the switch, remove the microSD card, and plug it back in. It now
boots from NVMe:

```bash
# workstation
ssh pi-login findmnt -n -o SOURCE /
```

prints a `/dev/nvme…` device.

## 3. Enable network boot

One script turns the head node into a boot server. It takes ten to twenty minutes, mostly
downloading and unpacking the operating system image. It

- configures `eth0` as 10.0.0.1, without a reboot,
- installs and configures DHCP, TFTP, NFS and a time server,
- downloads the current Raspberry Pi OS Lite image, checks it and unpacks it to `/image/pi5`,
- turns that copy into a network-boot image: NFS root, RAM for `/tmp` and `/var`, your user
  account, ssh host keys, no wifi,
- serves the image's `/boot` over TFTP and exports `/image/pi5`, `/home` and `/opt` over NFS,
- turns off cloud-init on the head node. Imager uses it to apply your settings on the first
  boot; after that it would rewrite `/etc/hosts` at every boot and drop the node names.

```bash
# pi-login
sudo bash pi-cluster/head/20-netboot.sh
```

When it finishes, `showmount -e` lists the three exports.

## 4. Add compute nodes

Out of the box, a Pi 5 tries the microSD card, NVMe and USB, but not the network. A bootloader
card changes that, once per node. Write it with Imager: Device **Raspberry Pi 5**, then
**Misc utility images → Bootloader (Pi 5 family) → Network Boot**, then the microSD card. For
each node, put the card in and connect the node to the switch. When the green LED flashes
rapidly without stopping (a connected screen turns green), unplug the node and remove the card.

![Figure 6: Imager bootloader image](docs/images/06-imager-bootloader.png)

Then, for node 1:

```bash
# pi-login
sudo bash pi-cluster/head/30-add-node.sh 1
```

Connect the node to the switch. The script sees the node ask for an address and records
its hardware address and name, then sees its first boot request and records its serial number.
About a minute later the node is up:

```bash
# workstation
ssh pi-001 uptime
```

Repeat with 2, 3, … for the other nodes. Node N is `pi-NNN` at 10.0.1.N.

## 5. Check the cluster

```bash
# workstation
ssh pi-login systemctl is-active dnsmasq nfs-server chrony
ssh pi-001 'findmnt -n -o TARGET,SOURCE,OPTIONS -t nfs,nfs4; timedatectl show -p NTPSynchronized'
```

Three lines of `active`; the node's `/` from `10.0.0.1:/image/pi5` read-only, `/home`
read-write, `/opt` read-only; and `NTPSynchronized=yes`.

## Maintenance

| Task                             | How                                                                    |
|----------------------------------|------------------------------------------------------------------------|
| Update the scripts               | `scp -r pi-cluster pi-login:` again, or `git pull` if you cloned on the head node |
| Update the compute image         | `sudo bash pi-cluster/head/image-run.sh apt update`, the same with `apt full-upgrade -y`, then reboot the nodes |
| Open a shell in the compute image | `sudo bash pi-cluster/head/image-run.sh`                              |
| Rebuild the compute image        | `sudo rm -rf /image/pi5`, then run `20-netboot.sh` again. Registered nodes keep booting |
| Re-run any script                | Always safe. Finished steps are skipped                                |

Power the compute nodes off before changing the image they run from.

## Troubleshooting

- **`ssh pi-login` cannot find the host.** `pi-login.local` is not resolving; use the address
  from your router as `HostName`.
- **`20-netboot.sh` says your wifi network already uses an address.** Your home network uses
  the cluster's addresses. Choose other `CLUSTER_NET`, `HEAD_IP` and `NODE_SUBNET` values in
  `cluster.env` and run the script again.
- **`30-add-node.sh` never sees the node.** Its bootloader is not set to network boot; repeat
  the Imager bootloader step. `journalctl -u dnsmasq -f` shows requests as they arrive.
- **The node gets an address but does not boot.** The same log shows what it asks for over
  TFTP. The serial-number link must exist in `/image/pi5/boot/`; the node's line in
  `/etc/pi-cluster/nodes` records its serial number.
- **The node boots without `/home`.** `exportfs -v` on the head node must list `/home` for
  10.0.1.0/24.

## Slurm

Not yet scripted. The working procedure is in [notes/slurm-mpi-shmem.md](notes/slurm-mpi-shmem.md).

## Notes

- **No microSD at all** is possible: a Pi 5 with no boot media can fetch Imager over the
  network and write the NVMe directly. That needs a monitor and keyboard, so this guide uses a card.
- **Security** assumes a private LAN. `/home` is exported without root squashing, so root on
  any node can read and change every user's files.

## References

- https://www.raspberrypi.com/documentation/computers/remote-access.html#network-boot-your-raspberry-pi
- https://aoterodelaroza.github.io/devnotes/diskless-rpi-cluster/
- https://glmdev.medium.com/building-a-raspberry-pi-cluster-784f0df9afbd
- https://medium.com/@hghcomphys/building-slurm-hpc-cluster-with-raspberry-pis-step-by-step-guide-ae84a58692d5
- https://ben.akrin.com/automated-headless-pi-imaging/
- https://forums.raspberrypi.com/viewtopic.php?t=315395
