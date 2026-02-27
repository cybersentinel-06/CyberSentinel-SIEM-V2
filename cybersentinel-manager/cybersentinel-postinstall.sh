#!/usr/bin/env bash
################################################################################
# CyberSentinel Post-Install Script
#
# Purpose: Replaces configuration files, rules, decoders, and integrations
#          in the RUNNING cybersentinel-manager Docker container
#
# Requirements:
#   - Docker containers must be running (docker-compose up -d)
#   - GitHub Personal Access Token for private repo access
#
# Usage: ./cybersentinel-postinstall.sh
################################################################################

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ========================================
# Configuration Variables
# ========================================
CONTAINER_NAME="cybersentinel-manager"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO_OWNER="${REPO_OWNER:-cybersentinel-06}"
REPO_NAME="${REPO_NAME:-CyberSentinel-SIEM}"
BRANCH="${BRANCH:-main}"
TEMP_DIR="/tmp/cybersentinel-postinstall-$$"
DOWNLOAD_SUCCESS=0
DOWNLOAD_FAILED=0

# ========================================
# Helper Functions
# ========================================

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

banner() {
    echo -e "${BLUE}${BOLD}"
    cat << "EOF"
   ______      __              _____            __  _            __
  / ____/_  __/ /_  ___  _____/ ___/___  ____  / /_(_)___  ___  / /
 / /   / / / / __ \/ _ \/ ___/\__ \/ _ \/ __ \/ __/ / __ \/ _ \/ /
/ /___/ /_/ / /_/ /  __/ /   ___/ /  __/ / / / /_/ / / / /  __/ /
\____/\__, /_.___/\___/_/   /____/\___/_/ /_/\__/_/_/ /_/\___/_/
     /____/
        POST-INSTALL CONFIGURATION SCRIPT
EOF
    echo -e "${NC}"
}

cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log_info "Cleaned up temporary directory"
    fi
}

trap cleanup EXIT

# ========================================
# Validation Functions
# ========================================

validate_environment() {
    log_info "Validating environment..."

    # Check if running as root or with docker permissions
    if ! docker ps >/dev/null 2>&1; then
        log_error "Cannot access Docker. Run as root or add user to docker group."
        exit 1
    fi

    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_error "Container '${CONTAINER_NAME}' is not running!"
        log_info "Please start containers first: cd cybersentinel-manager && docker-compose up -d"
        exit 1
    fi

    # Check if container is healthy
    local health_status=$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "none")
    if [ "$health_status" = "unhealthy" ]; then
        log_warn "Container is unhealthy but running. Proceeding with caution..."
    fi

    # Validate GitHub token
    if [ -z "$GITHUB_TOKEN" ]; then
        log_error "GITHUB_TOKEN environment variable is not set!"
        log_info "Export it first: export GITHUB_TOKEN='your_github_pat'"
        exit 1
    fi

    log_success "Environment validation passed"
}

# ========================================
# GitHub Download Functions
# ========================================

download_from_github() {
    local github_path="$1"
    local destination="$2"

    local url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/${github_path}"

    if curl -sSfL -H "Authorization: token ${GITHUB_TOKEN}" "$url" -o "$destination" 2>/dev/null; then
        # Validate file has actual content (not empty / error page)
        if [ -s "$destination" ]; then
            DOWNLOAD_SUCCESS=$((DOWNLOAD_SUCCESS + 1))
            return 0
        else
            rm -f "$destination"
            log_warn "Downloaded empty file: $github_path"
            DOWNLOAD_FAILED=$((DOWNLOAD_FAILED + 1))
            return 1
        fi
    else
        rm -f "$destination"
        log_warn "Failed to download: $github_path"
        DOWNLOAD_FAILED=$((DOWNLOAD_FAILED + 1))
        return 1
    fi
}

download_configurations() {
    log_info "Downloading CyberSentinel configurations from GitHub..."

    mkdir -p "$TEMP_DIR"/{config,rules,decoders,integrations}

    # Main configuration — this is critical, fail hard if it doesn't download
    log_info "  → Downloading ossec.conf"
    if ! download_from_github "SERVER/ossec.conf" "$TEMP_DIR/config/ossec.conf"; then
        log_error "CRITICAL: Failed to download ossec.conf — cannot proceed"
        exit 1
    fi

    log_success "Configuration files downloaded"
}

download_rules() {
    log_info "Downloading custom rules..."

    local rules=(
        "local_rules.xml"
        "misp_threat_intel.xml"
        "chavecloak_rules.xml"
        "alienOTX.xml"
        "0015-ossec_rules.xml"
        "0016-wazuh_rules.xml"
        "0475-IDS_IPS_rules.xml"
        "0490-virustotal_rules.xml"
        "mikrotik_rules.xml"
        "mikrotik_rules_2.xml"
        "hp_router_rules.xml"
        "cisco_rules.xml"
        "fim_rules.xml"
        "corelation_rules.xml"
        "sysmon_rules.xml"
    )

    for rule in "${rules[@]}"; do
        log_info "  → Downloading $rule"
        download_from_github "SERVER/RULES/$rule" "$TEMP_DIR/rules/$rule" || log_warn "  ✗ Skipping $rule"
    done

    log_success "Rule files downloaded ($DOWNLOAD_SUCCESS succeeded so far, $DOWNLOAD_FAILED failed)"
}

download_decoders() {
    log_info "Downloading custom decoders..."

    local decoders=(
        "local_decoder.xml"
        "mikrotik_decoders.xml"
        "mikrotik_decoders_2.xml"
        "hp_router_decoders.xml"
        "cisco_decoders.xml"
        "0005-wazuh_decoders.xml"
    )

    for decoder in "${decoders[@]}"; do
        log_info "  → Downloading $decoder"
        download_from_github "SERVER/DECODERS/$decoder" "$TEMP_DIR/decoders/$decoder" || log_warn "  ✗ Skipping $decoder"
    done

    log_success "Decoder files downloaded ($DOWNLOAD_SUCCESS succeeded so far, $DOWNLOAD_FAILED failed)"
}

download_integrations() {
    log_info "Downloading integration scripts..."

    local integrations=(
        "custom-abuseipdb.py"
        "custom-alienvault"
        "custom-alienvault.py"
        "get_malicious.py"
    )

    for integration in "${integrations[@]}"; do
        log_info "  → Downloading $integration"
        download_from_github "SERVER/INTEGRATIONS/$integration" "$TEMP_DIR/integrations/$integration" || log_warn "  ✗ Skipping $integration"
    done

    log_success "Integration scripts downloaded ($DOWNLOAD_SUCCESS succeeded so far, $DOWNLOAD_FAILED failed)"
}

# ========================================
# Container File Operations
# ========================================

deploy_configurations() {
    log_info "Deploying configurations to container..."

    if [ -f "$TEMP_DIR/config/ossec.conf" ]; then
        # Backup existing ossec.conf before overwriting
        docker exec "${CONTAINER_NAME}" bash -c \
            "cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak 2>/dev/null || true"
        log_info "  → Backed up existing ossec.conf to ossec.conf.bak"

        docker cp "$TEMP_DIR/config/ossec.conf" "${CONTAINER_NAME}:/var/ossec/etc/ossec.conf"
        log_success "  → Deployed ossec.conf"
    fi
}

deploy_rules() {
    log_info "Deploying rules to container..."

    # Deploy to /var/ossec/etc/rules/
    for rule_file in "$TEMP_DIR/rules"/*.xml; do
        if [ -f "$rule_file" ]; then
            local filename=$(basename "$rule_file")
            docker cp "$rule_file" "${CONTAINER_NAME}:/var/ossec/etc/rules/$filename"
            log_info "  → Deployed $filename to /var/ossec/etc/rules/"
        fi
    done

    # Deploy to /var/ossec/ruleset/rules/ (specific files)
    local ruleset_rules=(
        "0016-wazuh_rules.xml"
        "0015-ossec_rules.xml"
        "0490-virustotal_rules.xml"
    )

    for rule in "${ruleset_rules[@]}"; do
        if [ -f "$TEMP_DIR/rules/$rule" ]; then
            docker cp "$TEMP_DIR/rules/$rule" "${CONTAINER_NAME}:/var/ossec/ruleset/rules/$rule"
            log_info "  → Deployed $rule to /var/ossec/ruleset/rules/"
        fi
    done

    # Special case: 0475-IDS_IPS_rules.xml → 0475-suricata_rules.xml
    if [ -f "$TEMP_DIR/rules/0475-IDS_IPS_rules.xml" ]; then
        docker cp "$TEMP_DIR/rules/0475-IDS_IPS_rules.xml" "${CONTAINER_NAME}:/var/ossec/ruleset/rules/0475-suricata_rules.xml"
        log_info "  → Deployed 0475-IDS_IPS_rules.xml as 0475-suricata_rules.xml"
    fi

    log_success "Rules deployed successfully"
}

deploy_decoders() {
    log_info "Deploying decoders to container..."

    # Deploy to /var/ossec/etc/decoders/
    for decoder_file in "$TEMP_DIR/decoders"/*.xml; do
        if [ -f "$decoder_file" ]; then
            local filename=$(basename "$decoder_file")
            # Skip 0005-wazuh_decoders.xml from etc/decoders
            if [ "$filename" != "0005-wazuh_decoders.xml" ]; then
                docker cp "$decoder_file" "${CONTAINER_NAME}:/var/ossec/etc/decoders/$filename"
                log_info "  → Deployed $filename to /var/ossec/etc/decoders/"
            fi
        fi
    done

    # Deploy to /var/ossec/ruleset/decoders/ (specific files)
    if [ -f "$TEMP_DIR/decoders/0005-wazuh_decoders.xml" ]; then
        docker cp "$TEMP_DIR/decoders/0005-wazuh_decoders.xml" "${CONTAINER_NAME}:/var/ossec/ruleset/decoders/0005-wazuh_decoders.xml"
        log_info "  → Deployed 0005-wazuh_decoders.xml to /var/ossec/ruleset/decoders/"
    fi

    log_success "Decoders deployed successfully"
}

deploy_integrations() {
    log_info "Deploying integration scripts to container..."

    # Ensure integrations directory exists
    docker exec "${CONTAINER_NAME}" mkdir -p /var/ossec/integrations 2>/dev/null || true

    for integration_file in "$TEMP_DIR/integrations"/*; do
        if [ -f "$integration_file" ]; then
            local filename=$(basename "$integration_file")
            docker cp "$integration_file" "${CONTAINER_NAME}:/var/ossec/integrations/$filename"
            log_info "  → Deployed $filename"
        fi
    done

    log_success "Integration scripts deployed successfully"
}

# ========================================
# Permission Functions
# ========================================

fix_permissions() {
    log_info "Fixing ownership and permissions inside container..."

    # Fix ownership for all deployed files
    docker exec "${CONTAINER_NAME}" bash -c "
        chown root:wazuh /var/ossec/etc/ossec.conf 2>/dev/null || true
        chown root:wazuh /var/ossec/etc/rules/*.xml 2>/dev/null || true
        chown root:wazuh /var/ossec/etc/decoders/*.xml 2>/dev/null || true
        chown root:wazuh /var/ossec/ruleset/rules/*.xml 2>/dev/null || true
        chown root:wazuh /var/ossec/ruleset/decoders/*.xml 2>/dev/null || true
        chown root:wazuh /var/ossec/integrations/* 2>/dev/null || true
    "

    # Fix permissions for XML files (640)
    docker exec "${CONTAINER_NAME}" bash -c "
        chmod 640 /var/ossec/etc/ossec.conf 2>/dev/null || true
        chmod 640 /var/ossec/etc/rules/*.xml 2>/dev/null || true
        chmod 640 /var/ossec/etc/decoders/*.xml 2>/dev/null || true
        chmod 640 /var/ossec/ruleset/rules/*.xml 2>/dev/null || true
        chmod 640 /var/ossec/ruleset/decoders/*.xml 2>/dev/null || true
    "

    # Fix permissions for integration scripts (750 - executable)
    docker exec "${CONTAINER_NAME}" bash -c "
        chmod 750 /var/ossec/integrations/* 2>/dev/null || true
    "

    log_success "Permissions fixed successfully"
}

# ========================================
# Service Management
# ========================================

restart_manager() {
    log_info "Restarting CyberSentinel Manager inside container..."

    # Restart using wazuh-control
    docker exec "${CONTAINER_NAME}" /var/ossec/bin/wazuh-control restart

    # Wait for manager to stabilize
    sleep 5

    # Verify service is running
    if docker exec "${CONTAINER_NAME}" /var/ossec/bin/wazuh-control status | grep -q "is running"; then
        log_success "CyberSentinel Manager restarted successfully"
    else
        log_warn "CyberSentinel Manager status check returned unexpected result"
    fi
}

verify_deployment() {
    log_info "Verifying deployment..."

    local verified=0
    local missing=0

    # Check critical files inside container
    local critical_files=(
        "/var/ossec/etc/ossec.conf"
        "/var/ossec/etc/rules/local_rules.xml"
        "/var/ossec/etc/rules/mikrotik_rules.xml"
        "/var/ossec/etc/decoders/local_decoder.xml"
        "/var/ossec/etc/decoders/cisco_decoders.xml"
        "/var/ossec/ruleset/rules/0016-wazuh_rules.xml"
        "/var/ossec/ruleset/decoders/0005-wazuh_decoders.xml"
        "/var/ossec/integrations/custom-abuseipdb.py"
    )

    for file in "${critical_files[@]}"; do
        if docker exec "${CONTAINER_NAME}" test -s "$file" 2>/dev/null; then
            log_success "  ✓ $file"
            verified=$((verified + 1))
        else
            log_warn "  ✗ $file not found or empty"
            missing=$((missing + 1))
        fi
    done

    echo ""
    log_info "Verification: ${verified} files confirmed, ${missing} missing"
    log_info "Downloads: ${DOWNLOAD_SUCCESS} succeeded, ${DOWNLOAD_FAILED} failed"

    if [ "$DOWNLOAD_FAILED" -gt 0 ]; then
        log_warn "Some files failed to download. Check your GITHUB_TOKEN and repository access."
    fi
}

# ========================================
# Main Execution
# ========================================

main() {
    banner

    log_info "Starting CyberSentinel post-installation configuration..."
    echo ""

    # Phase 1: Validation
    log_info "========== Phase 1: Validating Environment =========="
    validate_environment
    echo ""

    # Phase 2: Download from GitHub
    log_info "========== Phase 2: Downloading Files from GitHub =========="
    download_configurations
    download_rules
    download_decoders
    download_integrations
    echo ""

    # Phase 3: Deploy to container
    log_info "========== Phase 3: Deploying Files to Container =========="
    deploy_configurations
    deploy_rules
    deploy_decoders
    deploy_integrations
    echo ""

    # Phase 4: Fix permissions
    log_info "========== Phase 4: Fixing Permissions =========="
    fix_permissions
    echo ""

    # Phase 5: Restart services
    log_info "========== Phase 5: Restarting Services =========="
    restart_manager
    echo ""

    # Phase 6: Verification
    log_info "========== Phase 6: Verification =========="
    verify_deployment
    echo ""

    log_success "============================================"
    log_success "   CyberSentinel post-install complete!"
    log_success "============================================"
    echo ""
    log_info "Next steps:"
    log_info "  1. Access CyberSentinel Manager API: https://localhost:55000"
    log_info "  2. Access Graylog UI: http://localhost:9000"
    log_info "  3. Check container logs: docker logs cybersentinel-manager"
    echo ""
}

# Execute main function
main "$@"
