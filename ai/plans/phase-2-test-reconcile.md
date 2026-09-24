# Phase 2 plan: test and reconcile

Status: done 2026-09-23, closed by the Phase 2 commit. The hardware run on nodes 1-3 is logged in
`ai/test-logs/2026-09-22.md`. Carried into Phase 3: node 4 (section 4, then 5.x and 5.10), the new
cluster photo, and M.6 with the first public release (D29). Human steps: 21 (+2 if the NVMe slot
needs enabling), 5 for each further node, the same as after Phase 1: Phase 2 changed wording,
order and output in the Readme but added no step. D9: Vincent runs every command and pastes
the output.

## Workstation part

- `Makefile`: `make check` runs `shellcheck` (reads `.shellcheckrc`) and `bash -n` over
  `head/*.sh`. shellcheck 0.11.0 was installed with Homebrew for Phase 1.
- `.github/workflows/check.yml`: `make check` on every push, on `ubuntu-latest`, with
  `actions/checkout@v7` (latest release v7.0.1, 2026-07-20, from `gh api
  repos/actions/checkout/releases/latest`). It runs once the repo is pushed; D11 says "not yet".
- `docs/testing.md`: one checklist per Readme section, each item a command, the expected
  output, a pass criterion and a rough time. It also covers the Phase 1 plan's
  "check on hardware" list and ends with the test-log template.
- `CLAUDE.md`: the "planned: Phase 2" markers go.

Facts behind checklist items and Readme changes:

| Item | Fact | Source |
|------|------|--------|
| 3.6 TFTP fetch from the head node itself | With `--interface`, dnsmasq adds the loopback interface automatically, so a request from the head node to 10.0.0.1 is answered | https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html (`--interface`) |
| 3.6 `curl tftp://…` | Debian's curl 8.14.1 does not disable TFTP in its build flags | https://sources.debian.org/data/main/c/curl/8.14.1-2+deb13u5/debian/rules |
| 5.8 alsa lines | alsa-utils 1.2.14's udev rule jumps to `alsa_restore_std` (lines 18, 22) but defines `alsa_restore_go` twice (lines 6, 26) and no `alsa_restore_std`; the image has 1.2.14-1+rpt1 | https://sources.debian.org/data/main/a/alsa-utils/1.2.14-1/alsactl/90-alsa-restore.rules.in; the image's `.info` package list (plan 1, F2) |
| 5.10 fan | The Pi 5 device tree ships `cooling_fan` disabled; the firmware enables it | https://raw.githubusercontent.com/raspberrypi/linux/rpi-6.18.y/arch/arm/boot/dts/overlays/README (`cooling_fan`) |
| Readme Troubleshooting, dnsmasq log | dnsmasq 2.91 logs "file not found" and every error packet from a client at `LOG_ERR`; `quiet-tftp` drops only the "not found" lines | https://sources.debian.org/data/main/d/dnsmasq/2.91-1+deb13u2/src/tftp.c (lines 718, 786); https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html (`--quiet-tftp`) |
| Readme Troubleshooting, `pieeprom.sig` | With `ENABLE_SELF_UPDATE` (default 1) the bootloader looks for `.sig`/`.upd` update files in the TFTP boot file system at every boot | https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/raspberry-pi/eeprom-bootloader.adoc (`ENABLE_SELF_UPDATE`) |
| Readme Troubleshooting, `armstub8-2712.bin` | The default Arm stub is stored in the firmware | https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/config_txt/boot.adoc (`armstub`) |
| Readme Troubleshooting, first requests | When the files are missing from the serial-number directory, the bootloader clears the prefix and asks for them in the TFTP root | https://raw.githubusercontent.com/raspberrypi/documentation/master/documentation/asciidoc/computers/raspberry-pi/eeprom-bootloader.adoc (`TFTP_PREFIX`) |
| Readme Parts, switch | RealHD PSW16-2GV3: 16 PoE+ ports and 2 gigabit uplinks, 802.3af/at, up to 30 W per port, 300 W total PoE budget. The listing says the PoE ports are 100 Mbps, but pi-login and pi-001 both report `1000` in `/sys/class/net/eth0/speed`, so the Readme gives the measured 1 Gbit/s | Product listing title and text pasted by Vincent, 2026-09-23; model from the label in his photos IMG_6845 and IMG_6864; the speed check, 2026-09-23 |
| Readme Parts and Notes, HATs | Nodes 1-3 carry Waveshare `PoE HAT (F)`; node 3's also reads `Rev1.2`, and its fan is the one the Pi drives (5.10) | Vincent, 2026-09-23 |
| M.2, EEPROM | rpi-eeprom 28.31's postinst stages no bootloader update; only `rpi-eeprom-update.service`, masked in the image, runs `rpi-eeprom-update -s -a` | https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/pios/trixie/debian/rpi-eeprom.postinst; https://raw.githubusercontent.com/raspberrypi/rpi-eeprom/pios/trixie/debian/rpi-eeprom.rpi-eeprom-update.service |
| M.2, masks | Package upgrades run `deb-systemd-helper unmask` (debhelper 13.24.2 postinst), which removes only masks it made itself, so the image's masks stay | https://sources.debian.org/data/main/d/debhelper/13.24.2/autoscripts/postinst-systemd-enable (line 3); https://sources.debian.org/data/main/i/init-system-helpers/1.69~deb13u1/script/deb-systemd-helper (`unmask_service`, lines 543-568) |

## Hardware part (Vincent)

1. Run `docs/testing.md` top to bottom and paste each section's output.
2. The session writes `ai/test-logs/YYYY-MM-DD.md` from the pastes.
3. Failures go back to Phase 1: fix, re-run the item, update the log.
4. Deploy path (D20): once the repo is public, `git clone` on the head node and one script run
   from the clone (item M.6).

## Reconcile, after the run

- Real output into Readme §5 and Troubleshooting; drop the Status note.
- Finalise `docs/images/README.md` against the figures Vincent captured.
- Human steps: 21 (+2 if the NVMe slot needs enabling) before this phase; recount after.

Commit at the end of the phase, saying what was hardware-verified.

## Handoff to Phase 3 (2026-09-23)

Phase 2 is committed and pushed to the private `pi-cluster-dev` (D29). What happened, in order,
is in the test log; the decisions it produced are D23-D29.

Carried into Phase 3:
1. Node 4, when it arrives: section 4, then 5.x and 5.10 on it. A used board could fail like
   the first node 3; the Readme's Troubleshooting covers the 8-flash code.
2. The new cluster photo with every node, as `docs/images/01-cluster.jpg` (now a 640 px copy of
   the 2025 photo), converted with the `magick` line in `docs/images/README.md`.
3. The first public release, near the end (D29): copy the public files into `vincentl/pi-cluster`,
   then M.6 (`git clone` on the head node, D20), CI there, and a look at the Mermaid diagrams as
   GitHub draws them.
4. Known hosts: the nodes share one host key (5.9), yet ssh asks once per node name. Jobs that
   ssh between nodes (D23) need them known in advance; a system-wide known_hosts line with a
   `pi-*` pattern would cover every node at once (check `sshd(8)`, SSH_KNOWN_HOSTS FILE FORMAT,
   before relying on it).
5. The `20-netboot.sh` output of the two second-session deploys was not pasted; their effects
   are verified either way.

Phase 3 kickoff: `Read ai/prompts/2026-09-22-trixie-refresh.md (Phase 3) and
ai/plans/phase-3-slurm.md, and continue Phase 3.`
