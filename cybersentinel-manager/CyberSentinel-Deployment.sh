#!/usr/bin/env bash
set -euo pipefail

############################################
# CyberSentinel Unified Installer
# Target OS: Ubuntu 22.04+
############################################

# ===== CONFIG =====
INSTALL_DIR="/opt/cybersentinel-collector"
REPO_OWNER="cybersentinel-06"
REPO_NAME="CyberSentinel-SIEM"
BRANCH="main"
CONTAINER_NAME="cybersentinel-manager"

REQUIRED_RAM_MB=8192
REQUIRED_DISK_GB=50

REQUIRED_PORTS=(1514/udp 1515/tcp 514/udp 5140/tcp 12201/udp 55000/tcp 9000/tcp)

# ===== UTILS =====
die() { echo "[FATAL] $1"; exit 1; }
info() { echo "[INFO] $1"; }
ok() { echo "[OK] $1"; }

# ===== PHASE 0: OS & RESOURCE CHECK =====
info "Validating OS"
source /etc/os-release
[[ "$ID" == "ubuntu" ]] || die "Ubuntu required"
(( ${VERSION_ID%%.*} >= 22 )) || die "Ubuntu 22.04+ required"

info "Checking resources"
RAM_MB=$(free -m | awk '/Mem:/ {print $2}')
DISK_GB=$(df -BG / | awk 'NR==2 {print $4}' | tr -d G)

(( RAM_MB >= REQUIRED_RAM_MB )) || die "Insufficient RAM"
(( DISK_GB >= REQUIRED_DISK_GB )) || die "Insufficient disk"

ok "System requirements met"

# ===== PHASE 1: DOCKER =====
if ! command -v docker >/dev/null; then
  info "Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi

if ! docker compose version >/dev/null 2>&1; then
  info "Installing Docker Compose v2"
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

systemctl enable --now docker
ok "Docker ready"

# ===== PHASE 2: FIREWALL =====
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  info "Configuring UFW"
  for p in "${REQUIRED_PORTS[@]}"; do
    ufw allow "$p"
  done
  ufw reload
  ok "Firewall configured"
else
  info "UFW inactive or missing, skipping firewall changes"
fi

# ===== PHASE 3: CLONE =====
[[ -n "${GITHUB_TOKEN:-}" ]] || die "GITHUB_TOKEN required"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

if [[ -d .git ]]; then
  echo ""
  echo "⚠️ EXISTING INSTALLATION DETECTED"
  echo "Type EXACTLY: DESTROY_AND_REDEPLOY"
  read -r CONFIRM
  [[ "$CONFIRM" == "DESTROY_AND_REDEPLOY" ]] || die "Aborted"

  docker compose down -v || true
  rm -rf ./*
fi

info "Cloning repository"
git clone https://${GITHUB_TOKEN}@github.com/${REPO_OWNER}/${REPO_NAME}.git .
git checkout "$BRANCH"

# ===== PHASE 4: DEPLOY =====
cd cybersentinel-manager
docker compose build --no-cache
docker compose up -d

info "Waiting for container health"
timeout 300 bash -c "
until docker inspect -f '{{.State.Health.Status}}' $CONTAINER_NAME | grep -q healthy; do
  sleep 5
done
"

ok "Container healthy"

# ===== PHASE 5: POST-INSTALL =====
cd "$INSTALL_DIR/cybersentinel-manager"
chmod +x cybersentinel-postinstall.sh
./cybersentinel-postinstall.sh

# ===== PHASE 6: BRANDING =====
docker cp cybersentinel-control "$CONTAINER_NAME:/usr/local/bin/cybersentinel-control"
docker exec "$CONTAINER_NAME" chmod 755 /usr/local/bin/cybersentinel-control

docker exec "$CONTAINER_NAME" cybersentinel-control restart
docker exec "$CONTAINER_NAME" cybersentinel-control restart 2>&1 | grep -i wazuh && \
  die "Branding violation detected"

ok "Branding enforced"

# ===== DONE =====
echo ""
echo "======================================"
echo " CyberSentinel INSTALLATION COMPLETE"
echo "======================================"
echo ""
echo "Usage:"
echo " docker exec $CONTAINER_NAME cybersentinel-control status"
echo " docker exec $CONTAINER_NAME cybersentinel-control restart"
