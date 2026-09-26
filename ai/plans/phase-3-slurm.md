# Phase 3 plan: Slurm

Status: approved by Vincent on 2026-09-24 with the defaults for D30-D34 and auth/slurm for D35;
implemented the same day (`head/25-slurm.sh`, `lib.sh`, `20-netboot.sh`, `30-add-node.sh`,
`cluster.env`, Readme, `docs/testing.md`); `make check` clean; `slurm_update`'s output checked
with stubs under trixie's bash 5.2. On hardware (nodes 1-3, 2026-09-24): core and memory limits,
auth/slurm and configless slurmd work (`ai/test-logs/2026-09-24.md`). What is left is in
`ai/prompts/2026-09-26-handoff.md`.

Kickoff: `ai/prompts/2026-09-22-trixie-refresh.md`, "Phase 3: Slurm" (D2 answered b). Facts are
rows F1-F33 at the end; each was fetched on 2026-09-23 or 2026-09-24 from the source given,
nothing from memory. Decisions: D30-D35 in `ai/decisions.md`.

## The design in one paragraph

A new script, `head/25-slurm.sh`, runs once after `20-netboot.sh`. On the head node it installs
the Slurm controller and the client tools, and makes the cluster's key, `/etc/slurm/slurm.key`.
Slurm authenticates with that key itself (`auth/slurm`, D35): no munge daemon runs anywhere,
although Debian's packages still install munge, which the script turns off. The script copies
the head node's accounts and the key into the compute image, installs slurmd and the client
tools there, and adds one systemd drop-in for slurmd. Nodes carry no Slurm configuration:
slurmd fetches `slurm.conf` and `cgroup.conf` from slurmctld at boot ("configless").
`slurm.conf` lists the registered nodes, so it is written, and slurmctld started, once the
first node is registered; after that `30-add-node.sh` adds each new node and runs
`scontrol reconfigure`. Every node you register joins Slurm by itself, with no extra step.

## What the research changed

1. **munge is not needed with auth/slurm** (F26-F28). slurmctld and slurmd hold the key and
   answer client commands over a local socket; Debian's package has the plugin, with the
   credential half built into `auth_slurm.so`. munge comes in as a dependency of every Slurm
   package (F30), so the script disables it on pi-login and masks it in the image; left
   enabled in the image, it would fail at every node boot (F9, F10).
2. **slurmd would not start on a node as shipped** (F14). It creates its spool directory with a
   single `mkdir` and stops if the parent is missing; the nodes' `/var` is empty RAM at every
   boot. A drop-in with `StateDirectory=slurm/slurmd` creates `/var/lib/slurm/slurmd` at each
   start (F25).
3. **A configless slurmd looks for its key next to its cached config** (F29), where the key never
   is, whenever it restarts itself (`scontrol reconfigure` does that, F31). The drop-in sets
   `SLURM_SACK_KEY=/etc/slurm/slurm.key`.
4. **slurmctld refuses to start with no nodes** (F21). `slurm.conf` is written only once a node
   is registered, which also keeps slurmctld's `ConditionPathExists` from starting it early (F13).
5. **Debian's example `cgroup.conf` stops Slurm 24.11** (F17): it sets a removed key. The script
   writes its own.
6. **Recommends pull in database, HDF5, IPMI and GPU libraries** (F12). Every install uses
   `--no-install-recommends`.

## Changes to the kickoff (approved 2026-09-24)

| # | Change | Why |
|---|--------|-----|
| C1 | `head/25-slurm.sh`, run in section 3 right after `20-netboot.sh`, instead of `40-slurm.sh` after the nodes (D30). | Nodes registered after it join Slurm by themselves. A script run after the nodes would need every node unplugged and plugged in again: two physical steps per node. |
| C2 | Configless: nodes fetch `slurm.conf` and `cgroup.conf` from slurmctld; the image holds only `--conf-server` and the key (D31). | Adding a node changes only the head node's files (F18, F19). |
| C3 | A systemd drop-in for slurmd in the image (`StateDirectory=`, environment) instead of tmpfiles.d entries. | systemd creates the directory, parents included, each time slurmd starts (F25). |
| C4 | The node list comes from the registry; `NODE_CPUS` and `NODE_MEMORY` are added to `cluster.env` (D32, D34). | Slurm drains a node configured with more memory than it has (F20). |
| C5 | `30-add-node.sh` updates `slurm.conf` and runs `scontrol reconfigure` when Slurm is installed. | Slurm 24.11 adds nodes on reconfigure and pushes the new files to configless nodes (F19, F22). |
| C6 | `/etc/slurm/slurm-local.conf`, created once and never overwritten, included at the end of the generated `slurm.conf`. | CLAUDE.md: anything the user adds lives in a separate include file (F19). |
| C7 | The copy of the head node's accounts into the image, and `image_run`/`image_has`, move into `lib.sh`. | `25-slurm.sh` needs them too. |
| C8 | `auth/slurm` and `cred/slurm` with `/etc/slurm/slurm.key` instead of munge (D35). | No munge daemon, key or UID handling (F27). The kickoff's "munge key generated on the head node and copied into the image" becomes the same for `slurm.key`. |

Not in this phase, from the old notes (D33): MPI (`MpiDefault=pmi2`, PMIx, mpich), UCX, and the
prolog/epilog scripts that made a per-job `SLURM_TMPDIR`. D2 keeps MPI as notes.

## `cluster.env`

```
NODE_CPUS=4          # cores on each compute node, for Slurm
NODE_MEMORY=15000    # MiB of each compute node's memory that jobs may use (D34)
```

`NODE_MEMORY` is set from a node's real memory once it is known (`MemTotal`, or RealMemory from
`slurmd -C`), minus about 1 GiB for the system, whose `/var` and `/tmp` also live in RAM.

## `head/lib.sh`

- `need_packages`: leading arguments that start with `-` go to `apt-get install`.
- `image_run`, `image_has` (from `20-netboot.sh`) and `copy_accounts` (its stage 4a loop).
- `registered_nodes`: the node names in `$NODES`, sorted.
- `slurm_update`: if slurmctld is installed and a node is registered, write
  `/etc/slurm/cgroup.conf`, `/etc/slurm/slurm.conf` and (if missing) `slurm-local.conf`, with
  fixed headers so either script can write them; then start slurmctld if it is not running, or
  run `scontrol reconfigure` if a file changed.

`slurm.conf`, generated:

```
ClusterName=pi-cluster
SlurmctldHost=pi-login(10.0.0.1)
SlurmctldParameters=enable_configless
SlurmUser=slurm
AuthType=auth/slurm
CredType=cred/slurm
StateSaveLocation=/var/lib/slurm/slurmctld
SlurmdSpoolDir=/var/lib/slurm/slurmd
ReturnToService=2
ProctrackType=proctrack/cgroup
TaskPlugin=task/cgroup,task/affinity
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory
DefMemPerCPU=3750
NodeName=pi-001,pi-002,pi-003 CPUs=4 RealMemory=15000
PartitionName=main Nodes=ALL Default=YES MaxTime=INFINITE State=UP
Include slurm-local.conf
```

- `StateSaveLocation` and `SlurmdSpoolDir` are Debian's directories; the built-in defaults are
  `/var/spool` and `/var/spool/slurmd`, which Debian does not create (F16).
- `ReturnToService=2`: a node that reboots comes back by itself when it registers (F20).
- `DefMemPerCPU` is `NODE_MEMORY / NODE_CPUS`; without it a job that does not ask for memory
  gets the whole node (F20).
- No accounting and no `MpiDefault` (F20). Tokens keep auth/slurm's 60 s lifetime (F29).

`cgroup.conf`, generated: `ConstrainCores=yes`, `ConstrainRAMSpace=yes`, `ConstrainSwapSpace=yes`.
`CgroupPlugin` stays at autodetect, which picks cgroup v2 (F17). A job that runs out of memory is
stopped instead of swapping into zram (D34). `ConstrainDevices` is left off (GPUs; eBPF on v2).

## `head/25-slurm.sh`

- 0. Checks: root, a Pi (lib.sh), the image exists.
- 1. Head packages: `need_packages --no-install-recommends slurmctld slurm-client`. munge comes
  along (F30) and its postinst starts it; slurmctld's postinst enables slurmctld, which does not
  start while `slurm.conf` is missing (F13).
- 2. munge off on pi-login: `systemctl disable --now munge` if enabled.
- 3. The key, made once: 1024 random bytes, `slurm:slurm`, mode 0600 (F27, F33), written to a
  temporary file and renamed, so an interrupted run leaves no short key.
- 4. `copy_accounts`: slurm (UID 64030, F15) and munge now exist in the image with the head
  node's IDs before anything is installed there.
- 5. Image packages, guarded by `image_has`: `apt-get update`, then
  `apt-get install -y --no-install-recommends slurmd slurm-client`. policy-rc.d stops anything
  from starting (F13). slurm-client lets job scripts call `srun` on the nodes.
- 6. The key into the image, `install -m 0600 -o slurm -g slurm`, unless `cmp -s` matches.
- 7. Image services: `etc/systemd/system/slurmd.service.d/pi-cluster.conf` with
  `Environment="SLURMD_OPTIONS=--conf-server 10.0.0.1"`,
  `Environment=SLURM_SACK_KEY=/etc/slurm/slurm.key` and `StateDirectory=slurm/slurmd`; then
  `systemctl --root=/image/pi5 mask munge.service` and `enable slurmd.service`. A drop-in
  rather than an edit of `/etc/default/slurmd`, the package's conffile, which would make a later
  `apt full-upgrade` in the image stop at a conffile question.
- 8. `slurm_update`: nothing yet on a fresh build; on a cluster with nodes, it writes the files
  and starts slurmctld.
- 9. `sinfo` if slurmctld runs, else the next step: register node 1.

Every stage checks real state: dpkg status, `cmp`, `put`, `systemctl`. A rerun changes nothing.

## `head/30-add-node.sh`

New stage 6, before the summary: `slurm_update`. It runs on every call and does nothing when Slurm
is not installed or nothing changed. A node needs about 45 s from its first boot request to reach
slurmd (Phase 2 test log, 4.5), so slurmctld knows it before its slurmd asks for the config.

## `head/20-netboot.sh`

Stage 4a calls `copy_accounts`; `image_run` and `image_has` come from `lib.sh`. No change in
behaviour. A rebuilt image has no Slurm until `25-slurm.sh` runs again; the Maintenance table
says so.

## Readme

- Section 3 gets a second command, `sudo bash pi-cluster/head/25-slurm.sh`, and what it does.
- Section 4 says a registered node also joins Slurm.
- Section 5 adds `sinfo` and `srun -N1 hostname`, with real output once tested.
- Maintenance: "Rebuild the compute image" adds `25-slurm.sh`; a new row "Change Slurm
  settings" (`/etc/slurm/slurm-local.conf`, then `sudo scontrol reconfigure`).
- Troubleshooting: a node down or drained in `sinfo`.
- The Slurm section at the end describes the partition and memory defaults; the Status line goes
  once Slurm is tested (kickoff: no Status note).
- Security note: the key is in the compute image, so any machine on the cluster network that can
  mount `/image/pi5` can read it.

Human steps: 21 (+2) now; 23 (+2) after this plan (one script, one check command); 5 for each
further node, unchanged.

## `docs/testing.md`

- 3.12-3.14: `25-slurm.sh`; a rerun changes nothing; the key on pi-login and in the image is
  identical, `slurm:slurm` 0600; munge disabled on pi-login and masked in the image.
- 5.11-5.16: `sinfo` and `srun`; memory and core limits in a job; a node that is unplugged and
  plugged back returns to `idle` by itself; `slurmd -C` on a node; the node's journal.
- 4.9: node 4, registered after Slurm, appears in `sinfo` as `idle` without other steps.
- M.2 and M.3 after Slurm: the image upgrade leaves slurmd starting.

## Check on hardware

- `apt-cache policy slurmctld slurmd` on pi-login picks 24.11.5-4+deb13u1 (F1).
- Pi OS does not turn off Recommends or disable units by preset in a way that changes the above.
- munge's postinst in the image (it runs `mungekey` through `su`) completes inside nspawn.
- On a node: slurmd does not stop with "Scope init timed out" (`SystemdTimeout`, 1000 ms by
  default, F17); dbus is running; the only slurmd warning is `/run/slurm` owned by root (F31).
- The node's clock starts at the image's build date until timesyncd sets it (Phase 2, 5.8), and
  auth/slurm tokens last 60 s. slurmd retries its config fetch every 10 s (F18), so it should get
  through once the clock is set; if not, `systemd-time-wait-sync.service` (F24) can hold slurmd
  until then.
- `srun` from pi-login reaches the nodes, although pi-login also has a wifi address:
  `/etc/hosts` maps `pi-login` to 10.0.0.1 and has no `127.0.1.1` line (F23).
- `scontrol reconfigure` (when node 4 is added) leaves every slurmd running: it restarts them,
  and they find the key through `SLURM_SACK_KEY` (F29, F31).
- Debian's `plugstack.conf`, which includes an empty `plugstack.conf.d/`, is served to the nodes
  without error.

## Facts

S = `https://sources.debian.org/src/slurm-wlm/24.11.5-4+deb13u1/`,
M = `https://sources.debian.org/src/munge/0.5.16-1.1~deb13u1/`,
A = `https://slurm.schedmd.com/archive/slurm-24.11.5/`. Line numbers are in those files.

| # | Question | Finding | Source | Consequence |
|---|----------|---------|--------|-------------|
| F1 | Slurm in trixie | 24.11.5-4 in trixie, 24.11.5-4+deb13u1 in trixie-security (7 CVEs, 2026-09-07); every binary package built for arm64; the Raspberry Pi archive has no slurm or munge packages | https://packages.debian.org/trixie/slurm-wlm ; S debian/changelog L1-26 ; http://archive.raspberrypi.com/debian/dists/trixie/main/binary-arm64/Packages | Debian's packages; check the version on pi-login |
| F2 | Package split | slurmctld (depends slurm-client, basic-plugins, munge); slurmd (does not depend on slurm-client); slurm-client (sinfo, srun, scontrol...); slurm-wlm-basic-plugins holds the cgroup v2, task, proctrack, munge and cons_tres plugins; slurm-wlm pulls in all three daemons' packages | S debian/control L44-113, L214-227 | Head: munge slurmctld slurm-client. Image: munge slurmd slurm-client |
| F3 | Config location | `--sysconfdir=/etc/slurm` | S debian/rules L39 | `/etc/slurm/slurm.conf` |
| F4 | No config shipped | No slurm.conf or cgroup.conf; examples under `/usr/share/doc/*/examples/`; `/etc/slurm/plugstack.conf` includes `plugstack.conf.d/*.conf` | S debian/plugstack.conf L1 ; the .deb file lists | The script writes both files |
| F5 | Purge | Purging slurm-wlm-basic-plugins runs `rm -rf /etc/slurm` | S debian/slurm-wlm-basic-plugins.postrm L22-44 | Only a note: no procedure here purges Slurm; a rerun rewrites the generated files, but `slurm-local.conf` would be gone |
| F6 | munge in trixie | 0.5.16-1.1~deb13u1 (security fix); munge, libmunge2, libmunge-dev for arm64 | https://packages.debian.org/source/trixie/munge ; M debian/changelog L1-14 | |
| F7 | munge key at install | postinst runs `mungekey -c` as munge if `/etc/munge/munge.key` is missing, keeps an existing key, and on every configure sets it to munge:munge 0400 | M debian/munge.postinst L20-43 | Head key made by the install; the image gets it before munge is installed there |
| F8 | munge user | `adduser --system --group ... munge` if missing: dynamic UID | M debian/munge.postinst L22-29 | Copy accounts to the image first |
| F9 | munge.service | `Type=forking`, `User=munge`, `ExecStart=/usr/sbin/munged $OPTIONS`, `EnvironmentFile=-/etc/default/munge` (comments only), `RuntimeDirectory=munge`; no StateDirectory or LogsDirectory; no tmpfiles.d shipped | M src/etc/munge.systemd.service.in L1-20 ; M src/etc/munge.systemd.sysconfig.in L1-4 ; M debian/changelog L72-78 | Drop-in in the image |
| F10 | munged at start | Missing `/var/log/munge` or `/var/lib/munge` is fatal, `--force` or not; key must be owned by munged's UID, not group- or world-readable; parents owned by root or munge, not group/world-writable; recommended modes 0711 `/var/lib/munge`, 0700 `/var/log/munge` | M src/munged/munged.c L119-128 ; M src/munged/random.c L278-282 ; M src/munged/conf.c L1025-1093 ; M QUICKSTART L198-234 ; M src/munged/munged.8.in L73-77 | StateDirectory= and LogsDirectory= with those modes |
| F11 | Credentials and time | Default TTL 300 s; a credential decodes only within the TTL of the encoder's clock | M src/libcommon/munge_defs.h L79-85 ; M src/munged/dec.c L970-1003 | Nodes must have the time from pi-login before munge works |
| F12 | Recommends | slurm-wlm-basic-plugins recommends slurm-wlm-plugins, which pulls in HDF5, MariaDB, FreeIPMI and ROCm SMI libraries | S debian/control L222, L243-259 | `--no-install-recommends` |
| F13 | Units and postinst | slurmctld.service: `User=slurm`, `ConditionPathExists=/etc/slurm/slurm.conf`. slurmd.service: root, `RuntimeDirectory=slurm`, `Delegate=yes`, `EnvironmentFile=-/etc/default/slurmd`, `$SLURMD_OPTIONS`, `ConditionPathExists` commented out. Each postinst enables its unit; inside nspawn with policy-rc.d nothing starts; `/etc/default/slurmd` is a conffile containing only a comment | S debian/slurmctld.service L3-15 ; S debian/slurmd.service L3-20 ; S debian/slurmd.default L1-2 ; the slurmd and slurmctld .deb postinsts | slurmctld waits for slurm.conf; the image uses a drop-in |
| F14 | slurmd spool directory | slurmd makes SlurmdSpoolDir and `conf-cache` in it with one `mkdir(0755)` each and stops unless the directory exists or can be made | S src/slurmd/slurmd/slurmd.c L2310-2326, L2800-2809 | `StateDirectory=slurm/slurmd` |
| F15 | slurm user | basic-plugins postinst: `adduser --system --group --uid 64030 ... slurm`, and sysusers `u! slurm 64030` | the slurm-wlm-basic-plugins .deb postinst L21-22, L67-70 ; S debian/slurm-wlm-basic-plugins.sysusers L1 | Same UID on head and image |
| F16 | Built-in defaults | StateSaveLocation `/var/spool`, SlurmdSpoolDir `/var/spool/slurmd`, SlurmUser root; Debian creates `/var/lib/slurm/slurmctld` and `/var/lib/slurm/slurmd` and its example uses them with `SlurmUser=slurm`; slurmctld exits if it cannot write StateSaveLocation | S src/common/read_config.h L78, L129-142 ; S debian/slurmctld.dirs L1-3 ; S debian/slurmd.dirs L1-5 ; S debian/examples/slurm.conf.simple L138, L154, L164 ; S src/slurmctld/controller.c L3537-3546 | Set both paths and SlurmUser |
| F17 | cgroup.conf in 24.11 | CgroupPlugin defaults to autodetect; Constrain* default no; AllowedSwapSpace 0; SystemdTimeout 1000 ms; `CgroupAutomount` defunct; Debian's example sets `ConstrainKmemSpace`, removed in 23.11, which is fatal | S doc/man/man5/cgroup.conf.5 L28-160 ; S src/interfaces/cgroup.c L134-141, L284-345 ; S NEWS L1894, L1909-1910 | Own cgroup.conf |
| F18 | Configless | `SlurmctldParameters=enable_configless`; `slurmd --conf-server host[:port]` wins over a local file; slurmd retries every 10 s; files served to slurmd include slurm.conf, cgroup.conf, plugstack.conf; cached in `<SlurmdSpoolDir>/conf-cache` with `/run/slurm/conf`; client commands on a node use the cache | A configless_slurm.html ; S src/slurmd/slurmd/slurmd.c L2272-2303 ; S src/common/fetch_config.c L54-64 ; S src/common/read_config.c L3340-3406 | No config in the image |
| F19 | Included files and pushes | An `Include` or Prolog/Epilog file is shipped only when named without a path and next to slurm.conf; relative names are found in slurm.conf's directory; `scontrol reconfigure` pushes new files to configless nodes | S doc/man/man5/slurm.conf.5 L4944-4952, L8076-8081 ; S doc/html/configless_slurm.shtml L98-102 | `Include slurm-local.conf` |
| F20 | slurm.conf semantics | cons_tres implies CR_Core_Memory; without DefMemPerCPU a job without `--mem` takes the node's memory ("strongly recommended"); ReturnToService=2 returns any DOWN node on a valid registration, 1 does not after a reboot; RealMemory above the node's own drains it ("Low RealMemory"); no accounting when AccountingStorageType is unset | S doc/man/man5/slurm.conf.5 L3668-3697, L4541, L4577 ; S src/slurmctld/job_mgr.c L9649-9657 ; S src/slurmctld/node_mgr.c L3262-3287 ; S src/common/read_config.c L4305-4316 | The generated slurm.conf |
| F21 | No nodes | slurmctld's config read fails with "no nodes configured" | S src/slurmctld/read_config.c L1549-1553 | slurm.conf only once a node is registered (C1) |
| F22 | Adding nodes in 24.11 | Edit slurm.conf, then `scontrol reconfigure` is enough in 24.11 and newer | A faq.html#add_nodes (S doc/html/faq.shtml L1584-1646) | `30-add-node.sh` runs reconfigure |
| F23 | Multi-homed hosts | A `127.0.1.1 <hostname>` line in /etc/hosts makes commands advertise 127.0.1.1 | S doc/html/faq.shtml L1566-1582 | `hosts_file` writes no such line |
| F24 | Waiting for the clock | trixie's systemd-timesyncd ships `systemd-time-wait-sync.service`; `After=time-sync.target` (munge has it) waits only when that service is enabled | https://packages.debian.org/trixie/arm64/systemd-timesyncd/filelist ; https://manpages.debian.org/trixie/systemd/systemd.special.7.en.html | Fallback if F11 bites at boot |
| F25 | StateDirectory=, LogsDirectory= | At each start, systemd creates the named directories, parents included, below `/var/lib` and `/var/log`; the innermost is owned by the unit's `User=`/`Group=` and gets `StateDirectoryMode=`/`LogsDirectoryMode=`; they stay when the unit stops | https://manpages.debian.org/trixie/systemd/systemd.exec.5.en.html (RuntimeDirectory=, StateDirectory=, ..., LogsDirectory=) | The two drop-ins (C3) |

| F26 | Who needs munge | With `AuthType=auth/munge` (the default) the key and a running munged are needed "on the machines running slurmctld, slurmdbd, slurmd and any submit hosts": munge signs every Slurm message, including slurmctld to slurmd, slurmd to slurmctld, and srun on pi-login to slurmd on a node | A authentication.html ("MUNGE", "Setup") | munged on every node, with auth/munge |
| F27 | Slurm's own auth (23.11+) | `AuthType=auth/slurm`, `CredType=cred/slurm`: a shared `slurm.key` (owned by SlurmUser, 0600) on the hosts running slurmctld, slurmdbd, slurmd or sackd; the SACK service inside slurmctld and slurmd serves client commands, so no extra daemon; sackd only for login nodes without a Slurm daemon | A authentication.html ("Slurm", "SACK") ; A sackd.html | D35 alternative: no munged anywhere |
| F28 | cred/slurm in Debian | Debian's basic-plugins ships `auth_slurm.so` and no `cred_slurm.so`; `cred_slurm.c` is compiled into `auth_slurm.so`, and `CredType=cred/slurm` loads the auth/slurm plugin | S src/plugins/auth/slurm/Makefile.am ; S src/interfaces/cred.c L142-148 ; the basic-plugins .deb file list | auth/slurm works with Debian's packages |
| F29 | auth/slurm details | Token lifetime 60 s by default (`AuthInfo=ttl=`; munge's is 300 s); the key is `slurm.key` next to the file `SLURM_CONF` names, or `$SLURM_SACK_KEY`. A configless slurmd sets `SLURM_CONF` to its cache, so it needs `SLURM_SACK_KEY=/etc/slurm/slurm.key` in its unit | S src/plugins/auth/slurm/auth_slurm.h L47 ; S src/plugins/auth/slurm/internal.c L66, L212-218, L242-243 ; S src/common/read_config.c L6472-6500 | Needed if D35 picks auth/slurm |
| F30 | munge as a dependency | slurmctld, slurmd and slurm-client all depend on munge, so it is installed with either auth type | S debian/control L58-113 | With auth/slurm, munge.service is masked in the image and disabled on pi-login |

| F31 | SACK sockets | slurmctld listens on `/run/slurmctld/sack.socket`, slurmd and sackd on `/run/slurm/sack.socket`; the directory must be owned by SlurmUser or root (root: a warning; anyone else: fatal); on reconfigure the socket passes to the restarted daemon through `SACK_RECONFIG_FD`. Client commands try `/run/slurm`, then `/run/slurmctld`, then `/run/slurmdbd` | S src/plugins/auth/slurm/sack.c L64-66, L79-120, L258-292 ; S src/common/sack_api.c L52-92 | pi-login's commands use slurmctld's socket; on a node, `/run/slurm` is root's (warning only) |
| F32 | Who reads the key | Only sackd, slurmd, slurmctld and slurmdbd load the key; client commands and slurmstepd run as clients of the local socket | S src/plugins/auth/slurm/auth_slurm.c L107-127 | The key is needed on pi-login and in the image, for the daemons only |
| F33 | Key checks | A key that cannot be stat'ed is fatal; any permission for others is fatal; an owner other than root or SlurmUser only warns | S src/plugins/auth/slurm/internal.c (`_check_key_permissions`) | `slurm:slurm` 0600 |

Also: cgroup v2 needs dbus on the node, since slurmd asks systemd for its scope over the system
bus and stops if that fails (S src/plugins/cgroup/v2/cgroup_dbus.c L265-273); `Delegate=yes` is
required and Debian's unit has it (S doc/html/cgroup_v2.shtml L214-221). The nodes' controllers
`cpuset cpu io memory pids` are enough (S src/plugins/cgroup/v2/cgroup_v2.c L83-89). Dynamic
nodes (`slurmd -Z`, D32's alternative) need `MaxNodeCount`, keep their first registration's
settings until deleted, and are not sorted (S doc/html/dynamic_nodes.shtml L46-57, L116-139).
