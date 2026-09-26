#!/usr/bin/env bash
set -euo pipefail

SECRETS_FILE="${1:-/tmp/bg-edge.env}"
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "Missing edge secrets file." >&2
  exit 1
fi

set -a
source "$SECRETS_FILE"
set +a

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  nftables \
  openssh-server \
  python3
rm -rf /var/lib/apt/lists/*

id relay >/dev/null 2>&1 || useradd --create-home --shell /bin/bash relay
id relayweb >/dev/null 2>&1 || useradd --system --home-dir /srv/relay --shell /usr/sbin/nologin relayweb
passwd -l relay >/dev/null 2>&1 || true

install -d -m 0755 -o root -g root /opt/blackglass
install -m 0755 -o root -g root /tmp/edge_app.py /opt/blackglass/edge_app.py

install -d -m 0755 -o relayweb -g relayweb /srv/relay
install -d -m 0755 -o relayweb -g relayweb /srv/relay/public
install -d -m 0750 -o root -g relayweb /srv/relay/secrets

cat > /srv/relay/public/release-manifest.txt <<'EOF'
BLACKGLASS RELAY MANIFEST 4.7
storage_root=/srv/relay
release_documents=public/
artifact_owner=relay
signing_identity=secrets/relay_id_ed25519
operator_note=secrets/operator-note.txt
compatibility_decoder=legacy-v2
EOF

cat > /srv/relay/secrets/operator-note.txt <<'EOF'
The relay identity is still accepted for the external SSH maintenance endpoint.
User: relay
The transit synchronizer moved to 10.60.10.20 after the segmentation project.
Do not copy the private identity into release bundles again.
EOF

install -d -m 0700 -o relay -g relay /home/relay/.ssh
if [[ ! -f /srv/relay/secrets/relay_id_ed25519 ]]; then
  ssh-keygen -q -t ed25519 -N '' -C 'relay@edge01' \
    -f /srv/relay/secrets/relay_id_ed25519
fi

install -m 0600 -o relay -g relay \
  /srv/relay/secrets/relay_id_ed25519.pub \
  /home/relay/.ssh/authorized_keys
chown root:relayweb /srv/relay/secrets/relay_id_ed25519
chmod 0640 /srv/relay/secrets/relay_id_ed25519
chown root:relayweb /srv/relay/secrets/relay_id_ed25519.pub
chmod 0640 /srv/relay/secrets/relay_id_ed25519.pub
chown root:relayweb /srv/relay/secrets/operator-note.txt
chmod 0640 /srv/relay/secrets/operator-note.txt

printf '%s\n' "$FLAG1" > /home/relay/flag1.txt
cat > /home/relay/TRANSIT-NOTE.txt <<'EOF'
The old synchronizer was moved behind the transit interface.
Inventory records should be queried from the network instead of trusted blindly.
Remember that SOCKS requests originate from the SSH server that owns the tunnel.
EOF
chown relay:relay /home/relay/flag1.txt /home/relay/TRANSIT-NOTE.txt
chmod 0400 /home/relay/flag1.txt
chmod 0444 /home/relay/TRANSIT-NOTE.txt

install -d -m 0700 -o vagrant -g vagrant /home/vagrant/.ssh
install -m 0600 -o vagrant -g vagrant /tmp/bg-mgmt.pub /home/vagrant/.ssh/authorized_keys
passwd -l vagrant >/dev/null 2>&1 || true

cat > /etc/systemd/system/blackglass-relay.service <<'EOF'
[Unit]
Description=Blackglass Artifact Relay
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=relayweb
Group=relayweb
WorkingDirectory=/srv/relay
ExecStart=/usr/bin/python3 /opt/blackglass/edge_app.py
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/srv/relay

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/ssh/sshd_config.d/blackglass.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers relay vagrant
X11Forwarding no
AllowTcpForwarding yes
PermitTunnel no
EOF

cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet blackglass_guest {
  chain input {
    type filter hook input priority 0; policy drop;
    iifname "lo" accept
    ct state established,related accept
    ip protocol icmp accept
    ip saddr 172.22.10.0/24 tcp dport { 22, 8080 } accept
    ip saddr 192.168.121.0/24 tcp dport { 22, 8080 } accept
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
EOF

rm -f "$SECRETS_FILE" /tmp/edge_app.py /tmp/bg-mgmt.pub
systemctl daemon-reload
systemctl enable --now blackglass-relay
systemctl restart ssh
systemctl enable --now nftables

echo "edge01 provisioning complete"
