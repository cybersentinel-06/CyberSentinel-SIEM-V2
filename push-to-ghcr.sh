#!/usr/bin/env bash
################################################################################
# CyberSentinel — Manual Build & Push to GHCR
#
# Builds all 3 images locally and pushes them to GitHub Container Registry.
#
# Prerequisites:
#   1. Run fetch-configs.sh first to download configs (for manager image)
#   2. Have a GitHub token with write:packages scope
#
# Usage:
#   GITHUB_TOKEN='ghp_xxx' ./push-to-ghcr.sh
#
# This script does NOT require GitHub Actions — it runs directly on your machine.
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANAGER_DIR="$SCRIPT_DIR/cybersentinel-manager"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GHCR_OWNER="${GHCR_OWNER:-cybersentinel-06}"

MANAGER_IMAGE="ghcr.io/${GHCR_OWNER}/cybersentinel-siem/manager:4.14.0"
NORMALIZER_IMAGE="ghcr.io/${GHCR_OWNER}/cybersentinel-siem/normalizer:6.3.9"
FORWARDER_IMAGE="ghcr.io/${GHCR_OWNER}/cybersentinel-siem/forwarder:1.0"

# ========================================
# Validate
# ========================================
if [ -z "$GITHUB_TOKEN" ]; then
    log_error "GITHUB_TOKEN is required (needs write:packages scope)"
    echo "  Usage: GITHUB_TOKEN='ghp_xxx' ./push-to-ghcr.sh"
    exit 1
fi

if [ ! -f "$MANAGER_DIR/config/ossec.conf" ]; then
    log_error "Config files not found! Run fetch-configs.sh first:"
    echo "  cd $MANAGER_DIR && GITHUB_TOKEN='ghp_xxx' ./fetch-configs.sh"
    exit 1
fi

# ========================================
# Login to GHCR
# ========================================
log_info "Logging into GHCR as ${GHCR_OWNER}..."
echo "$GITHUB_TOKEN" | docker login ghcr.io -u "${GHCR_OWNER}" --password-stdin
log_success "GHCR login successful"
echo ""

# ========================================
# Build images
# ========================================
log_info "Building CyberSentinel Manager..."
docker build -t "$MANAGER_IMAGE" -t "ghcr.io/${GHCR_OWNER}/cybersentinel-siem/manager:latest" "$MANAGER_DIR"
log_success "Manager image built: $MANAGER_IMAGE"
echo ""

log_info "Building CyberSentinel Normalizer..."
docker build -t "$NORMALIZER_IMAGE" -t "ghcr.io/${GHCR_OWNER}/cybersentinel-siem/normalizer:latest" "$MANAGER_DIR/normalizer"
log_success "Normalizer image built: $NORMALIZER_IMAGE"
echo ""

log_info "Building CyberSentinel Forwarder..."
docker build -t "$FORWARDER_IMAGE" -t "ghcr.io/${GHCR_OWNER}/cybersentinel-siem/forwarder:latest" "$MANAGER_DIR/fluent-bit"
log_success "Forwarder image built: $FORWARDER_IMAGE"
echo ""

# ========================================
# Push to GHCR
# ========================================
log_info "Pushing images to GHCR..."
echo ""

for img in \
    "$MANAGER_IMAGE" "ghcr.io/${GHCR_OWNER}/cybersentinel-siem/manager:latest" \
    "$NORMALIZER_IMAGE" "ghcr.io/${GHCR_OWNER}/cybersentinel-siem/normalizer:latest" \
    "$FORWARDER_IMAGE" "ghcr.io/${GHCR_OWNER}/cybersentinel-siem/forwarder:latest"; do
    log_info "  Pushing $img..."
    docker push "$img"
    log_success "  Pushed: $img"
done

echo ""
echo -e "${GREEN}${BOLD}============================================${NC}"
echo -e "${GREEN}${BOLD}  All images pushed to GHCR!${NC}"
echo -e "${GREEN}${BOLD}============================================${NC}"
echo ""
echo -e "  ${BOLD}Images:${NC}"
echo -e "    $MANAGER_IMAGE"
echo -e "    $NORMALIZER_IMAGE"
echo -e "    $FORWARDER_IMAGE"
echo ""
echo -e "  ${BOLD}Deploy on a fresh server:${NC}"
echo -e "    GITHUB_TOKEN='ghp_xxx' ./cybersentinel-deploy-ghcr.sh"
echo ""
