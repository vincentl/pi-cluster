#!/bin/bash
# Register compute node N: its DHCP address and name, /etc/hosts, and its TFTP boot directory.
# Runs on the head node: sudo bash pi-cluster/head/30-add-node.sh N [--replace], then connect node N to the switch.
# --replace forgets the board registered as node N first, so a new board can take its number.
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
need_root

# 0. N is a node number from 1 to 254, optionally followed by --replace, and 20-netboot.sh has run.
replace=${2:-}
if [[ $# -lt 1 || $# -gt 2 || ! $1 =~ ^[0-9]+$ || ( -n $replace && $replace != --replace ) ]] ||
   (( 10#$1 < 1 || 10#$1 > 254 )); then
    die "usage: sudo bash $0 N [--replace], where N is a node number from 1 to 254"
fi
name=$(node_name "$1")
ip=$(node_ip "$1")
[[ -e $IMAGE/etc/os-release && -e $NODES ]] || die "run 20-netboot.sh first"
leases=/var/lib/misc/dnsmasq.leases
line=$(grep -E "^[0-9a-f:]{17},[0-9.]+,$name([[:space:]#]|$)" "$NODES" || true)

# 1. With --replace, forget the board registered as node N: its registry line, TFTP link and DHCP lease.
if [[ -n $replace && -n $line ]]; then
    old_serial=$(sed -n 's/.*# serial \([0-9a-f]\{8\}\).*/\1/p' <<< "$line")
    sed -i -E "/^[0-9a-f:]{17},[0-9.]+,$name([[:space:]#]|$)/d" "$NODES"
    if [[ -n $old_serial && -L $IMAGE/boot/$old_serial ]]; then
        rm "$IMAGE/boot/$old_serial"
    fi
    if grep -q " $ip " "$leases" 2>/dev/null; then
        systemctl stop dnsmasq
        sed -i "/ ${ip//./\\.} /d" "$leases"
        systemctl start dnsmasq
    fi
    log "forgot the board registered as $name (MAC ${line%%,*}); unplug it if it is still connected"
    line=
fi

# 2. The node's MAC address: from the registry, or from its first DHCP request.
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

# 3. Nothing more to do if the node's serial number is recorded and its TFTP link exists.
serial=$(sed -n "s/.*,${name}[[:space:]]*# serial \([0-9a-f]\{8\}\).*/\1/p" "$NODES")
if [[ -n $serial && -L $IMAGE/boot/$serial ]]; then
    log "$name boots from $IMAGE/boot/$serial"
else
    # 4. Watch for the node's first TFTP request, then give it its address and name.
    tftp=$(mktemp)
    tcpdump -l -n -i eth0 -c 1 "udp dst port 69 and src host $ip" > "$tftp" 2>/dev/null &
    capture=$!
    sleep 1
    grep -qE "^$mac,$ip,$name([[:space:]#]|$)" "$NODES" || echo "$mac,$ip,$name" >> "$NODES"
    put /etc/hosts < <(hosts_file)
    put "$IMAGE/etc/hosts" < <(hosts_file)
    systemctl reload dnsmasq
    log "waiting for $name to ask for its boot files"

    # 5. The first request names the serial number, as in RRQ "8baee41e/config.txt": link it to the image.
    wait "$capture"
    serial=$(sed -n 's/.*RRQ "\([0-9a-f]\{8\}\)\/.*/\1/p' "$tftp")
    rm -f "$tftp"
    [[ -n $serial ]] || die "could not read a serial number from $name's TFTP request"
    ln -sfn firmware "$IMAGE/boot/$serial"
    sed -i "s/^\($mac,$ip,$name\)\([[:space:]#].*\)\{0,1\}$/\1  # serial $serial/" "$NODES"
    log "$name boots from $IMAGE/boot/$serial"
fi

# 6. Summary.
cat <<EOF

$name  MAC $mac  serial $serial  address $ip
It is up about a minute after its first boot request. From your workstation:
  ssh $name uptime
EOF
