#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

required_commands=(vagrant virsh qemu-system-x86_64 nft curl jq nc openssl ssh-keygen)
missing=()

for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    missing+=("$command_name")
  fi
done

if (( ${#missing[@]} > 0 )); then
  printf 'Missing commands: %s\n' "${missing[*]}" >&2
  echo "Run sudo ./scripts/bootstrap-controller.sh first." >&2
  exit 1
fi

if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
  echo "The current user cannot access /dev/kvm." >&2
  echo "Confirm nested virtualization, group membership, and reboot after bootstrap." >&2
  exit 1
fi

if ! virsh -c qemu:///system list >/dev/null 2>&1; then
  echo "The current user cannot connect to system libvirt." >&2
  echo "Confirm membership in the libvirt group and reboot after bootstrap." >&2
  exit 1
fi

memory_kib="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
if (( memory_kib < 20 * 1024 * 1024 )); then
  echo "WARNING: Less than 20 GB RAM is visible. The balanced range expects 24 GB."
fi

free_kib="$(df -Pk "$PROJECT_ROOT" | awk 'NR==2 {print $4}')"
if (( free_kib < 90 * 1024 * 1024 )); then
  echo "WARNING: Less than 90 GB is free. Windows box downloads may exhaust storage."
fi

if ! vagrant plugin list | grep -q '^vagrant-libvirt '; then
  echo "The vagrant-libvirt plugin is not installed for the current user." >&2
  exit 1
fi

echo "Preflight checks passed."
