#!/usr/bin/env bash
set -euo pipefail

vagrant box add debian/bookworm64 \
  --box-version 12.20260519.1 \
  --provider libvirt

vagrant box add gusztavvargadr/windows-server-2022-standard \
  --box-version 2607.0.0 \
  --provider libvirt

vagrant box add gusztavvargadr/windows-11 \
  --box-version 2607.1.0 \
  --provider libvirt

echo "All pinned Blackglass Transit base boxes are cached locally."
