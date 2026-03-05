#!/usr/bin/env bash
################################################################################
# CyberSentinel Config Fetcher
#
# Downloads custom configuration files from the CyberSentinel-SIEM repository
# into the local config/ directory for Docker image baking.
#
# Usage:
#   GITHUB_TOKEN='ghp_xxx' ./fetch-configs.sh
#   OR: export GITHUB_TOKEN='ghp_xxx' && ./fetch-configs.sh
#
# The downloaded files are used by the Dockerfile to bake configs into the image.
################################################################################

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO_OWNER="${REPO_OWNER:-cybersentinel-06}"
REPO_NAME="${REPO_NAME:-CyberSentinel-SIEM}"
BRANCH="${BRANCH:-main}"
CONFIG_DIR="$(cd "$(dirname "$0")" && pwd)/config"

DOWNLOAD_SUCCESS=0
DOWNLOAD_FAILED=0

log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

download_file() {
    local github_path="$1"
    local destination="$2"

    local url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/${github_path}"

    if curl -sSfL -H "Authorization: token ${GITHUB_TOKEN}" "$url" -o "$destination" 2>/dev/null; then
        if [ -s "$destination" ]; then
            DOWNLOAD_SUCCESS=$((DOWNLOAD_SUCCESS + 1))
            log_success "  $github_path"
            return 0
        else
            rm -f "$destination"
            log_warn "  Empty file: $github_path"
            DOWNLOAD_FAILED=$((DOWNLOAD_FAILED + 1))
            return 1
        fi
    else
        rm -f "$destination"
        log_warn "  Failed: $github_path"
        DOWNLOAD_FAILED=$((DOWNLOAD_FAILED + 1))
        return 1
    fi
}

# Validate token
if [ -z "$GITHUB_TOKEN" ]; then
    log_error "GITHUB_TOKEN is required!"
    log_info "Usage: GITHUB_TOKEN='ghp_xxx' ./fetch-configs.sh"
    exit 1
fi

log_info "Downloading CyberSentinel configs from ${REPO_OWNER}/${REPO_NAME}@${BRANCH}"
log_info "Target directory: ${CONFIG_DIR}"
echo ""

# Create directories
mkdir -p "$CONFIG_DIR"/{rules,decoders,integrations,ruleset/rules,ruleset/decoders}

# ========================================
# Main configuration
# ========================================
log_info "Downloading main configuration..."
if ! download_file "SERVER/ossec.conf" "$CONFIG_DIR/ossec.conf"; then
    log_error "CRITICAL: Failed to download ossec.conf"
    exit 1
fi

# ========================================
# Custom Rules (etc/rules/)
# ========================================
log_info "Downloading custom rules..."
RULES=(
    "local_rules.xml"
    "misp_threat_intel.xml"
    "chavecloak_rules.xml"
    "alienOTX.xml"
    "mikrotik_rules.xml"
    "mikrotik_rules_2.xml"
    "hp_router_rules.xml"
    "cisco_rules.xml"
    "fim_rules.xml"
    "corelation_rules.xml"
    "sysmon_rules.xml"
)

for rule in "${RULES[@]}"; do
    download_file "SERVER/RULES/$rule" "$CONFIG_DIR/rules/$rule" || true
done

# ========================================
# Ruleset Overrides (ruleset/rules/ - replace default Wazuh rules)
# ========================================
log_info "Downloading ruleset overrides..."
RULESET_RULES=(
    "0015-ossec_rules.xml"
    "0016-wazuh_rules.xml"
    "0475-IDS_IPS_rules.xml"
    "0490-virustotal_rules.xml"
)

for rule in "${RULESET_RULES[@]}"; do
    download_file "SERVER/RULES/$rule" "$CONFIG_DIR/ruleset/rules/$rule" || true
done

# ========================================
# Custom Decoders (etc/decoders/)
# ========================================
log_info "Downloading custom decoders..."
DECODERS=(
    "local_decoder.xml"
    "mikrotik_decoders.xml"
    "mikrotik_decoders_2.xml"
    "hp_router_decoders.xml"
    "cisco_decoders.xml"
)

for decoder in "${DECODERS[@]}"; do
    download_file "SERVER/DECODERS/$decoder" "$CONFIG_DIR/decoders/$decoder" || true
done

# ========================================
# Ruleset Decoder Overrides (ruleset/decoders/)
# ========================================
log_info "Downloading ruleset decoder overrides..."
download_file "SERVER/DECODERS/0005-wazuh_decoders.xml" "$CONFIG_DIR/ruleset/decoders/0005-wazuh_decoders.xml" || true

# Also place in config/decoders/ where Dockerfile picks it up for baking
if [ -f "$CONFIG_DIR/ruleset/decoders/0005-wazuh_decoders.xml" ]; then
    cp "$CONFIG_DIR/ruleset/decoders/0005-wazuh_decoders.xml" "$CONFIG_DIR/decoders/0005-wazuh_decoders.xml"
    log_success "  Copied 0005-wazuh_decoders.xml to config/decoders/ (for Dockerfile)"
fi

# ========================================
# Integration Scripts
# ========================================
log_info "Downloading integration scripts..."
INTEGRATIONS=(
    "custom-abuseipdb.py"
    "custom-alienvault"
    "custom-alienvault.py"
    "get_malicious.py"
)

for integration in "${INTEGRATIONS[@]}"; do
    download_file "SERVER/INTEGRATIONS/$integration" "$CONFIG_DIR/integrations/$integration" || true
done

# ========================================
# Summary
# ========================================
echo ""
log_info "============================================"
log_info "Download Summary"
log_info "============================================"
log_success "  Succeeded: $DOWNLOAD_SUCCESS"
[ "$DOWNLOAD_FAILED" -gt 0 ] && log_warn "  Failed:    $DOWNLOAD_FAILED" || log_success "  Failed:    $DOWNLOAD_FAILED"
echo ""

# List downloaded files
log_info "Files in config/:"
find "$CONFIG_DIR" -type f | sort | while read -r f; do
    echo "  $(echo "$f" | sed "s|${CONFIG_DIR}/||")"
done
echo ""

if [ "$DOWNLOAD_FAILED" -gt 0 ]; then
    log_warn "Some files failed to download. The Dockerfile will skip missing files."
fi

log_success "Config fetch complete! You can now build the Docker image."
log_info "Build: docker build -t cybersentinel-manager:4.14.0 ."
