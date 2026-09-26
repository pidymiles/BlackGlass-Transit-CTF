#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run this installer with sudo." >&2
  exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
  echo "Run with sudo from the non-root account that will operate Vagrant." >&2
  exit 1
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
if [[ -z "$TARGET_HOME" ]]; then
  echo "Could not resolve the home directory for $TARGET_USER." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  apt-transport-https \
  bridge-utils \
  build-essential \
  ca-certificates \
  curl \
  dnsmasq-base \
  gnupg \
  jq \
  libguestfs-tools \
  libvirt-clients \
  libvirt-daemon-system \
  libvirt-dev \
  lsb-release \
  make \
  netcat-openbsd \
  nftables \
  nmap \
  openssh-client \
  ovmf \
  pkg-config \
  qemu-kvm \
  ruby-dev \
  unzip

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg \
  | gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg

DIST_CODENAME="$(. /etc/os-release && printf '%s' "$VERSION_CODENAME")"
printf 'deb [signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com %s main\n' \
  "$DIST_CODENAME" > /etc/apt/sources.list.d/hashicorp.list

apt-get update
apt-get install -y --no-install-recommends vagrant

usermod -aG libvirt,kvm "$TARGET_USER"
systemctl enable --now libvirtd 2>/dev/null \
  || systemctl enable --now virtqemud.socket

runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" \
  vagrant plugin install vagrant-libvirt

if [[ ! -e /dev/kvm ]]; then
  echo
  echo "WARNING: /dev/kvm is absent. Confirm CPU type 'host' and nested virtualization in Proxmox."
fi

echo
echo "Controller dependencies are installed."
echo "Reboot once so the libvirt and kvm group memberships take effect."
