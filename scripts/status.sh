#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

vagrant status
echo
./scripts/healthcheck.sh || true
echo

UPLINK_INTERFACE="$(ip route show default | awk 'NR==1 {print $5}')"
CONTROLLER_IP="$(ip -4 -o addr show dev "$UPLINK_INTERFACE" scope global | awk 'NR==1 {split($4,a,"/"); print a[1]}')"

if [[ -n "$CONTROLLER_IP" ]]; then
  echo "Player entry URL: http://$CONTROLLER_IP:8080/"
  echo "Player SSH entry: $CONTROLLER_IP:2222"
fi

echo "Organizer secrets: .generated/organizer-secrets.txt"

