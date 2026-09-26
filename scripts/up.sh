#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

./scripts/preflight.sh
./scripts/generate-secrets.sh

export VAGRANT_DEFAULT_PROVIDER=libvirt

echo
echo "[1/4] Starting the Linux perimeter and transit nodes..."
vagrant up edge01 jump01 --provider=libvirt --no-parallel
touch .generated/edge.ready .generated/jump.ready

echo
echo "[2/4] Building the BLACKGLASS.LAB domain controller..."
vagrant up dc01 --provider=libvirt
touch .generated/dc.ready

echo
echo "[3/4] Joining the Windows member server..."
vagrant up file01 --provider=libvirt
touch .generated/file.ready

echo
echo "[4/4] Joining the Windows workstation..."
vagrant up ws01 --provider=libvirt
touch .generated/ws.ready

echo
./scripts/healthcheck.sh
echo
echo "Provisioning is complete."
echo "Run sudo ./scripts/expose.sh to publish TCP 8080 and TCP 2222."
echo "Organizer secrets are stored in .generated/organizer-secrets.txt."
