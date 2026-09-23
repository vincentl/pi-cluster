#!/bin/bash
# Run a command inside the compute node image, or open a shell there when no command is given.
# Runs on the head node: sudo bash pi-cluster/head/image-run.sh [command...]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need_root
[[ -e $IMAGE/etc/os-release ]] || die "no image at $IMAGE; run 20-netboot.sh first"

# 1. Nodes read the image live over NFS: say which ones are running from it.
nodes=$(ss -H -t -n state established '( sport = :2049 )' | awk '{ sub(/:[0-9]+$/, "", $4); print $4 }' | sort -u)
[[ -z $nodes ]] || log "warning: compute nodes are running from the image: ${nodes//$'\n'/ }"

# 2. The command, with /opt shared and the head node's DNS for the session only.
status=0
systemd-nspawn -q -D "$IMAGE" --bind=/opt --resolv-conf=bind-host "$@" || status=$?

# 3. Package scripts may have written a machine ID: keep it empty so each node makes its own.
: > "$IMAGE/etc/machine-id"
ln -sfn /etc/machine-id "$IMAGE/var/lib/dbus/machine-id"
exit "$status"
