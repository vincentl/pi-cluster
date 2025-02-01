#!/bin/bash

# Ensure the script is run with exactly one argument
if [[ $# -ne 1 || ! $1 =~ ^0*[0-9]+$ ]]; then
    echo "Usage: $0 <integer (with or without leading zeros)>"
    exit 1
fi

# Convert argument to integer (removes leading zeros)
HOST=$1
HOST_ID=$((10#$HOST))

# Define network interface (modify as needed)
INTERFACE="eth0"

echo "Listening for DHCP requests on $INTERFACE..."

# Run tcpdump to capture a DHCP Discover/Request packet and extract the MAC address
MAC=$(tcpdump -l -i eth0 -c 1 udp port 67 and port 68 2>/dev/null | sed -E 's|^.*([0-9a-f:]{17}).*$|\1|')

# Ensure a MAC address was captured
if [[ -z "$MAC" ]]; then
    echo "Error: No DHCP packets captured. Ensure a device is requesting an IP."
    exit 2
fi

echo "Captured MAC Address: $MAC"

# Generate the DHCP static lease entry
LEASE_ENTRY="    host {{cluster.node-prefix}}$HOST {
      hardware ethernet $MAC;
      fixed-address 10.0.1.$HOST_ID;
      option host-name "'"'"{{cluster.node-prefix}}$HOST"'"'";
      option root-path "'"'"10.0.0.1:/image/pi5,v3,tcp,hard,rsize=8192,wsize=8192"'"'";
    }"

# Add to dhcpd.conf
ed -s /etc/dhcp/dhcpd.conf <<EOF
/# compute-nodes/a
$LEASE_ENTRY
.
w
EOF

echo "DHCP static lease entry added:"
echo "$LEASE_ENTRY"

# Restart DHCP service to apply changes
sudo systemctl restart isc-dhcp-server

echo "DHCP service restarted. The device should now receive $IP_PREFIX.$IP_SUFFIX"

# Now wait for a packet with the serial number & create a link in 