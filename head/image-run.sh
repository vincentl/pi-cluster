#!/bin/bash
# Run a command inside the compute node image, or open a shell there when no command is given.
# Runs on the head node: sudo bash pi-cluster/head/image-run.sh [command...]
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need_root
[[ -e $IMAGE/etc/os-release ]] || die "no image at $IMAGE; run 20-netboot.sh first"

# 1. Nodes read the image live over NFS: name those connected that answer a ping (an unplugged node's connection lingers for minutes).
running=()
for addr in $(ss -H -t -n state established '( sport = :2049 )' | awk '{ sub(/:[0-9]+$/, "", $4); print $4 }' | sort -u); do
    ping -c 1 -W 1 "$addr" >/dev/null 2>&1 && running+=("$addr")
done
[[ ${#running[@]} -eq 0 ]] || log "warning: compute nodes are running from the image: ${running[*]}"

# 2. The command, with /opt shared, the head node's DNS for the session only, and no terminal tint.
status=0
systemd-nspawn -q -D "$IMAGE" --bind=/opt --resolv-conf=bind-host --background= "$@" || status=$?

# 3. Package scripts may have written a machine ID: keep it empty so each node makes its own.
: > "$IMAGE/etc/machine-id"
ln -sfn /etc/machine-id "$IMAGE/var/lib/dbus/machine-id"
exit "$status"
