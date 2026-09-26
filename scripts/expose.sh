#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this script with sudo." >&2
  exit 1
fi

UPLINK_INTERFACE="${UPLINK_INTERFACE:-$(ip route show default | awk 'NR==1 {print $5}')}"
if [[ -z "$UPLINK_INTERFACE" ]]; then
  echo "Could not determine the controller uplink interface." >&2
  exit 1
fi

BIND_IP="${BIND_IP:-$(ip -4 -o addr show dev "$UPLINK_INTERFACE" scope global | awk 'NR==1 {split($4,a,"/"); print a[1]}')}"
if [[ -z "$BIND_IP" ]]; then
  echo "Could not determine the controller IPv4 address. Set BIND_IP explicitly." >&2
  exit 1
fi

OUTSIDE_BRIDGE="$(virsh -c qemu:///system net-info bg-outside | awk '/^Bridge:/ {print $2}')"
if [[ -z "$OUTSIDE_BRIDGE" ]]; then
  echo "The bg-outside libvirt network is not running." >&2
  exit 1
fi

sysctl -q -w net.ipv4.ip_forward=1
nft delete table ip blackglass 2>/dev/null || true

nft -f - <<EOF
table ip blackglass {
  chain input_guard {
    type filter hook input priority -5; policy accept;
    iifname "$UPLINK_INTERFACE" tcp dport 50000-60000 drop
  }

  chain prerouting {
    type nat hook prerouting priority dstnat; policy accept;
    iifname "$UPLINK_INTERFACE" ip daddr $BIND_IP tcp dport 8080 dnat to 172.22.10.10:8080
    iifname "$UPLINK_INTERFACE" ip daddr $BIND_IP tcp dport 2222 dnat to 172.22.10.10:22
  }

  chain forward_guard {
    type filter hook forward priority -5; policy accept;
    ct state established,related accept
    iifname "$UPLINK_INTERFACE" ip daddr 172.22.10.10 tcp dport { 22, 8080 } accept
    iifname "$UPLINK_INTERFACE" ip daddr { 172.22.10.0/24, 10.60.10.0/24, 10.60.20.0/24 } drop
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
    oifname "$OUTSIDE_BRIDGE" ip daddr 172.22.10.10 tcp dport { 22, 8080 } masquerade
  }
}
EOF

echo "Blackglass Transit is exposed at:"
echo "  Web: http://$BIND_IP:8080/"
echo "  SSH: $BIND_IP:2222"
echo
echo "Only the intended entry services are published."

