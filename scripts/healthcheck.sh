#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

failures=0

check_vm() {
  local name="$1"
  if virsh -c qemu:///system list --name | grep -Eq "(^|_)${name}$"; then
    printf '[ok]   %-8s running\n' "$name"
  else
    printf '[fail] %-8s not running\n' "$name"
    failures=1
  fi
}

check_port() {
  local label="$1"
  local host="$2"
  local port="$3"
  if nc -z -w 4 "$host" "$port" >/dev/null 2>&1; then
    printf '[ok]   %-22s %s:%s\n' "$label" "$host" "$port"
  else
    printf '[fail] %-22s %s:%s\n' "$label" "$host" "$port"
    failures=1
  fi
}

for vm_name in edge01 jump01 dc01 file01 ws01; do
  check_vm "$vm_name"
done

check_port "edge web" 172.22.10.10 8080
check_port "edge ssh" 172.22.10.10 22
check_port "jump repository" 10.60.10.20 8000
check_port "jump ssh" 10.60.10.20 22
check_port "domain kerberos" 10.60.20.10 88
check_port "domain ldap" 10.60.20.10 389
check_port "domain smb" 10.60.20.10 445
check_port "domain winrm" 10.60.20.10 5985
check_port "archive smb" 10.60.20.30 445
check_port "employee portal" 10.60.20.40 80

if curl -fsS --max-time 5 http://172.22.10.10:8080/healthz \
  | grep -q '"status":"ok"'; then
  echo "[ok]   edge application health"
else
  echo "[fail] edge application health"
  failures=1
fi

if (( failures != 0 )); then
  echo
  echo "One or more range checks failed." >&2
  exit 1
fi

echo
echo "All non-spoiling health checks passed."

