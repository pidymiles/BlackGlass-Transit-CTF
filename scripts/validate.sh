#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

find scripts provision/linux -type f -name '*.sh' -print0 \
  | while IFS= read -r -d '' script_path; do
      bash -n "$script_path"
    done

python3 -m py_compile provision/linux/*.py

if command -v ruby >/dev/null 2>&1; then
  ruby -c Vagrantfile >/dev/null
else
  echo "ruby is unavailable; Vagrantfile parser validation was skipped."
fi

if command -v pwsh >/dev/null 2>&1; then
  while IFS= read -r -d '' powershell_path; do
    pwsh -NoLogo -NoProfile -Command \
      "[void][System.Management.Automation.Language.Parser]::ParseFile('$powershell_path',[ref]$null,[ref]$null)"
  done < <(find provision/windows -type f -name '*.ps1' -print0)
else
  echo "pwsh is unavailable; PowerShell parser validation was skipped."
fi

echo "Static validation passed."
