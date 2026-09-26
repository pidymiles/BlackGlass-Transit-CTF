#!/usr/bin/env bash
set -euo pipefail

SECRETS_FILE="${1:-/tmp/bg-jump.env}"
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "Missing jump secrets file." >&2
  exit 1
fi

set -a
source "$SECRETS_FILE"
set +a

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  git \
  iputils-ping \
  nftables \
  openssh-server \
  python3 \
  sudo
rm -rf /var/lib/apt/lists/*

id ops >/dev/null 2>&1 || useradd --create-home --shell /bin/bash ops
id transitweb >/dev/null 2>&1 || useradd --system --home-dir /srv/transit-web --shell /usr/sbin/nologin transitweb
printf 'ops:%s\n' "$OPS_PASSWORD" | chpasswd

printf '%s\n' "$FLAG2" > /home/ops/flag2.txt
cat > /home/ops/README.txt <<'EOF'
The route-audit helper was moved under sudo after the corporate ACL rollout.
The report formatter remains in the netops plugin directory so operators can
change report appearance without a full deployment.
EOF
chown ops:ops /home/ops/flag2.txt /home/ops/README.txt
chmod 0400 /home/ops/flag2.txt
chmod 0444 /home/ops/README.txt

install -d -m 0700 -o vagrant -g vagrant /home/vagrant/.ssh
install -m 0600 -o vagrant -g vagrant /tmp/bg-mgmt.pub /home/vagrant/.ssh/authorized_keys
passwd -l vagrant >/dev/null 2>&1 || true

rm -rf /srv/transit-web
install -d -m 0755 -o transitweb -g transitweb /srv/transit-web

cat > /srv/transit-web/index.html <<'EOF'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Transit Archive Mirror</title>
  <style>
    body { background:#111820; color:#d7e2ed; font-family:system-ui,sans-serif; }
    main { max-width:760px; margin:8vh auto; padding:2rem; border:1px solid #33465a; }
    h1 { color:#8fe0c4; }
    .muted { color:#91a1b2; }
  </style>
</head>
<body><main>
  <h1>Transit Archive Mirror</h1>
  <p>Configuration publishing completed successfully.</p>
  <p class="muted">Repository metadata is retained for rollback compatibility.</p>
</main></body></html>
EOF

pushd /srv/transit-web >/dev/null
git init -q
git config user.name "Transit Automation"
git config user.email "automation@blackglass.lab"
git add index.html
git commit -q -m "Publish archive mirror"

install -d -m 0755 inventory
cat > inventory/retired-sync.env <<EOF
TRANSIT_HOST=10.60.10.20
TRANSIT_USER=ops
TRANSIT_PASSWORD=$OPS_PASSWORD
COMMENT=temporary credential until key rollout
EOF
git add inventory/retired-sync.env
git commit -q -m "Add temporary synchronization credential"
git rm -q inventory/retired-sync.env
git commit -q -m "Remove temporary credential from working tree"
git update-server-info
popd >/dev/null

chown -R transitweb:transitweb /srv/transit-web
find /srv/transit-web -type d -exec chmod 0755 {} +
find /srv/transit-web -type f -exec chmod 0644 {} +

cat > /etc/systemd/system/transit-archive.service <<'EOF'
[Unit]
Description=Blackglass Transit Archive
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=transitweb
Group=transitweb
WorkingDirectory=/srv/transit-web
ExecStart=/usr/bin/python3 -m http.server 8000 --bind 0.0.0.0 --directory /srv/transit-web
Restart=on-failure
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/srv/transit-web

[Install]
WantedBy=multi-user.target
EOF

groupadd -f netops
usermod -aG netops ops
install -d -m 2775 -o root -g netops /opt/blackglass/netaudit/plugins
install -m 0755 -o root -g root /tmp/net-audit.py /usr/local/bin/net-audit
install -m 0644 -o root -g netops /tmp/formatter.py /opt/blackglass/netaudit/plugins/formatter.py

cat > /etc/sudoers.d/blackglass-net-audit <<'EOF'
Defaults:ops !requiretty
ops ALL=(root) NOPASSWD: /usr/local/bin/net-audit --target *
EOF
chmod 0440 /etc/sudoers.d/blackglass-net-audit
visudo -cf /etc/sudoers.d/blackglass-net-audit

printf '%s\n' "$FLAG3" > /root/flag3.txt
cat > /root/realm-sync.env <<EOF
DOMAIN=BLACKGLASS.LAB
DOMAIN_CONTROLLER=10.60.20.10
USERNAME=$AUDIT_USER
PASSWORD=$AUDIT_PASSWORD
NOTE=Read-only directory survey account used by transit inventory.
EOF
chmod 0400 /root/flag3.txt /root/realm-sync.env

cat > /etc/ssh/sshd_config.d/blackglass.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication yes
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers ops vagrant
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
    ip saddr 10.60.10.0/24 tcp dport { 22, 8000 } accept
    ip saddr 192.168.121.0/24 tcp dport { 22, 8000 } accept
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}
EOF

rm -f "$SECRETS_FILE" /tmp/net-audit.py /tmp/formatter.py /tmp/bg-mgmt.pub
systemctl daemon-reload
systemctl enable --now transit-archive
systemctl restart ssh
systemctl enable --now nftables

echo "jump01 provisioning complete"
