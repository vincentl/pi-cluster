#!/bin/bash
# Add Slurm: the controller on the head node, slurmd in the compute image, and the cluster's key.
# Runs on the head node, after 20-netboot.sh: sudo bash pi-cluster/head/25-slurm.sh
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need_root
[[ -e $IMAGE/etc/os-release ]] || die "no image at $IMAGE; run 20-netboot.sh first"
key=/etc/slurm/slurm.key

# 1. Head node: the controller and the client tools, without recommended extras (munge comes along as a dependency).
need_packages --no-install-recommends slurmctld slurm-client

# 2. munge off on the head node: Slurm authenticates with its own key (auth/slurm).
if systemctl is-enabled --quiet munge 2>/dev/null; then
    systemctl disable --now --quiet munge
    log "turned off munge on the head node; Slurm uses its own key"
fi

# 3. The cluster's key, made once: 1024 random bytes that only slurm can read, renamed into place when complete.
if [[ ! -e $key ]]; then
    tmp=$(mktemp "$key.XXXXXX")
    dd if=/dev/random of="$tmp" bs=1024 count=1 status=none
    chown slurm:slurm "$tmp"
    mv "$tmp" "$key"
    log "made the cluster's key, $key"
fi

# 4. Image accounts: the head node's, so slurm and munge have the same IDs in the image.
copy_accounts

# 5. The compute image: slurmd, and the client tools that job scripts use to call srun.
if ! image_has slurmd || ! image_has slurm-client; then
    image_run apt-get update
    image_run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends slurmd slurm-client
fi

# 6. The key in the image, for slurmd.
if ! cmp -s "$key" "$IMAGE$key"; then
    install -m 0600 -o slurm -g slurm "$key" "$IMAGE$key"
    log "copied the key into the image"
fi

# 7. Image services: slurmd gets its settings from slurmctld and its spool directory in the RAM /var; munge stays off.
put "$IMAGE/etc/systemd/system/slurmd.service.d/pi-cluster.conf" <<EOF
$GENERATED
[Service]
# Settings from slurmctld ("configless"). The key is not among them, so say where it is.
Environment="SLURMD_OPTIONS=--conf-server $HEAD_IP"
Environment=SLURM_SACK_KEY=$key
# /var is empty RAM at every boot: make the spool directory each time slurmd starts.
StateDirectory=slurm/slurmd
EOF
systemctl --root="$IMAGE" --quiet mask munge.service
systemctl --root="$IMAGE" --quiet enable slurmd.service

# 8. slurm.conf and slurmctld, once a compute node is registered.
slurm_update

# 9. What next.
if systemctl is-active --quiet slurmctld; then
    sinfo
    log "done; compute nodes start slurmd at their next boot"
else
    log "done; slurmctld starts when you register the first compute node: sudo bash $(dirname "$0")/30-add-node.sh 1"
fi
