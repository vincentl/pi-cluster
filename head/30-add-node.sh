#!/bin/bash
# Register compute node N: its DHCP address and name, /etc/hosts, and its TFTP boot directory.
# Runs on the head node: sudo bash pi-cluster/head/30-add-node.sh N, then connect node N to the switch.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need_root

# 0. N is a node number from 1 to 254, and 20-netboot.sh has run.
if [[ $# -ne 1 || ! $1 =~ ^[0-9]+$ ]] || (( 10#$1 < 1 || 10#$1 > 254 )); then
    die "usage: sudo bash $0 N, where N is a node number from 1 to 254"
fi
name=$(node_name "$1")
ip=$(node_ip "$1")
[[ -e $IMAGE/etc/os-release && -e $NODES ]] || die "run 20-netboot.sh first"

# 1. The node's MAC address: from the registry, or from its first DHCP request.
line=$(grep -E "^[0-9a-f:]{17},[0-9.]+,$name([[:space:]#]|$)" "$NODES" || true)
if [[ -n $line ]]; then
    mac=${line%%,*}
    log "$name is registered with MAC $mac"
else
    filter="udp dst port 67"
    while read -r known; do
        filter+=" and not ether src $known"
    done < <(sed -n 's/^\([0-9a-f:]\{17\}\),.*/\1/p' "$NODES")
    log "connect node $((10#$1)) to the switch now; waiting for its DHCP request"
    mac=$(tcpdump -l -n -i eth0 -c 1 "$filter" 2>/dev/null | sed -n 's/.*Request from \([0-9a-f:]\{17\}\).*/\1/p')
    [[ -n $mac ]] || die "no DHCP request seen"
    log "$name has MAC $mac"
fi

# 2. Nothing more to do if the node's serial number is recorded and its TFTP link exists.
serial=$(sed -n "s/.*,${name}[[:space:]]*# serial \([0-9a-f]\{8\}\).*/\1/p" "$NODES")
if [[ -n $serial && -L $IMAGE/boot/$serial ]]; then
    log "$name boots from $IMAGE/boot/$serial"
else
    # 3. Watch for the node's first TFTP request, then give it its address and name.
    tftp=$(mktemp)
    tcpdump -l -n -i eth0 -c 1 "udp dst port 69 and src host $ip" > "$tftp" 2>/dev/null &
    capture=$!
    sleep 1
    grep -qE "^$mac,$ip,$name([[:space:]#]|$)" "$NODES" || echo "$mac,$ip,$name" >> "$NODES"
    put /etc/hosts < <(hosts_file)
    put "$IMAGE/etc/hosts" < <(hosts_file)
    systemctl reload dnsmasq
    log "waiting for $name to ask for its boot files"

    # 4. The first request names the serial number, as in RRQ "8baee41e/config.txt": link it to the image.
    wait "$capture"
    serial=$(sed -n 's/.*RRQ "\([0-9a-f]\{8\}\)\/.*/\1/p' "$tftp")
    rm -f "$tftp"
    [[ -n $serial ]] || die "could not read a serial number from $name's TFTP request"
    ln -sfn firmware "$IMAGE/boot/$serial"
    sed -i "s/^\($mac,$ip,$name\)\([[:space:]#].*\)\{0,1\}$/\1  # serial $serial/" "$NODES"
    log "$name boots from $IMAGE/boot/$serial"
fi

# 5. Summary.
cat <<EOF

$name  MAC $mac  serial $serial  address $ip
It is up about a minute after its first boot request. From your workstation:
  ssh $name uptime
EOF
