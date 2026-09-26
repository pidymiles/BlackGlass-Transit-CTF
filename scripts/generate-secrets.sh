#!/usr/bin/env bash
set -euo pipefail
umask 077

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GENERATED_DIR="$PROJECT_ROOT/.generated"
FORCE="${1:-}"

mkdir -p "$GENERATED_DIR"

if [[ -f "$GENERATED_DIR/organizer-secrets.txt" && "$FORCE" != "--force" ]]; then
  echo "Using existing generated challenge state."
  exit 0
fi

if [[ "$FORCE" == "--force" ]]; then
  find "$GENERATED_DIR" -maxdepth 1 -type f ! -name '.gitkeep' -delete
fi

random_hex() {
  openssl rand -hex "$1"
}

FLAG1="flag{relay_path_$(random_hex 10)}"
FLAG2="flag{history_never_forgets_$(random_hex 10)}"
FLAG3="flag{plugins_run_with_the_caller_$(random_hex 10)}"
FLAG4="flag{service_accounts_cross_boundaries_$(random_hex 10)}"
FLAG5="flag{delegation_reaches_the_crown_$(random_hex 10)}"

OPS_PASSWORD="Transit-Aa9!$(random_hex 6)"
AUDIT_PASSWORD="Survey-Aa9!$(random_hex 7)"
SQL_PASSWORD="Blackglass2026!"
DEPLOY_PASSWORD="Deploy-Aa9!$(random_hex 7)"
DOMAIN_ADMIN_PASSWORD="Crown-Aa9!$(random_hex 10)"
DSRM_PASSWORD="Restore-Aa9!$(random_hex 10)"
DC_MGMT_PASSWORD="Manage-Aa9!$(random_hex 10)"
FILE_MGMT_PASSWORD="Manage-Aa9!$(random_hex 10)"
WS_MGMT_PASSWORD="Manage-Aa9!$(random_hex 10)"

ssh-keygen -q -t ed25519 -N '' -C 'blackglass-range-management' \
  -f "$GENERATED_DIR/mgmt_ed25519"

cat > "$GENERATED_DIR/edge.env" <<EOF
FLAG1=$FLAG1
EOF

cat > "$GENERATED_DIR/jump.env" <<EOF
FLAG2=$FLAG2
FLAG3=$FLAG3
OPS_PASSWORD=$OPS_PASSWORD
AUDIT_USER=audit.reader
AUDIT_PASSWORD=$AUDIT_PASSWORD
EOF

cat > "$GENERATED_DIR/dc.env" <<EOF
DOMAIN_FQDN=BLACKGLASS.LAB
DOMAIN_NETBIOS=BLACKGLASS
DOMAIN_ADMIN_PASSWORD=$DOMAIN_ADMIN_PASSWORD
DSRM_PASSWORD=$DSRM_PASSWORD
MGMT_PASSWORD=$DC_MGMT_PASSWORD
AUDIT_PASSWORD=$AUDIT_PASSWORD
SQL_PASSWORD=$SQL_PASSWORD
DEPLOY_PASSWORD=$DEPLOY_PASSWORD
FLAG5=$FLAG5
EOF

cat > "$GENERATED_DIR/file.env" <<EOF
DOMAIN_FQDN=BLACKGLASS.LAB
DOMAIN_NETBIOS=BLACKGLASS
DOMAIN_ADMIN_PASSWORD=$DOMAIN_ADMIN_PASSWORD
MGMT_PASSWORD=$FILE_MGMT_PASSWORD
FLAG4=$FLAG4
EOF

cat > "$GENERATED_DIR/ws.env" <<EOF
DOMAIN_FQDN=BLACKGLASS.LAB
DOMAIN_NETBIOS=BLACKGLASS
DOMAIN_ADMIN_PASSWORD=$DOMAIN_ADMIN_PASSWORD
MGMT_PASSWORD=$WS_MGMT_PASSWORD
EOF

cat > "$GENERATED_DIR/organizer-secrets.txt" <<EOF
BLACKGLASS TRANSIT - ORGANIZER SECRETS
Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

Flag 1: $FLAG1
Flag 2: $FLAG2
Flag 3: $FLAG3
Flag 4: $FLAG4
Flag 5: $FLAG5

ops password: $OPS_PASSWORD
BLACKGLASS\\audit.reader password: $AUDIT_PASSWORD
BLACKGLASS\\svc_sql password: $SQL_PASSWORD
Initial BLACKGLASS\\svc_deploy password: $DEPLOY_PASSWORD
BLACKGLASS\\Administrator password: $DOMAIN_ADMIN_PASSWORD
DSRM password: $DSRM_PASSWORD
dc01 Vagrant management password: $DC_MGMT_PASSWORD
file01 Vagrant management password: $FILE_MGMT_PASSWORD
ws01 Vagrant management password: $WS_MGMT_PASSWORD
EOF

chmod 600 "$GENERATED_DIR"/*.env "$GENERATED_DIR/organizer-secrets.txt" "$GENERATED_DIR/mgmt_ed25519"
chmod 644 "$GENERATED_DIR/mgmt_ed25519.pub"
echo "Generated fresh flags and credentials."
