#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ "${1:-}" != "--force" ]]; then
  echo "This destroys all five nested guests and permanently replaces every flag and password."
  read -r -p "Type RESET to continue: " confirmation
  if [[ "$confirmation" != "RESET" ]]; then
    echo "Reset cancelled."
    exit 0
  fi
fi

vagrant destroy -f

if command -v nft >/dev/null 2>&1; then
  sudo nft delete table ip blackglass 2>/dev/null || true
fi

find "$PROJECT_ROOT/.generated" -maxdepth 1 -type f ! -name '.gitkeep' -delete
./scripts/generate-secrets.sh --force

echo "The old range was destroyed and fresh challenge state was generated."
echo "Run ./scripts/up.sh to deploy it."

