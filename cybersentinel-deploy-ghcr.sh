#!/usr/bin/env bash
################################################################################
# CyberSentinel GHCR Deployment Script
#
# Deploys CyberSentinel SIEM from pre-built GHCR images.
# No git clone, no build — just pull and run.
#
# Usage:
#   sudo ./cybersentinel-deploy-ghcr.sh
#   OR: GITHUB_TOKEN='ghp_xxx' sudo ./cybersentinel-deploy-ghcr.sh
#
# What this script does:
#   1. Installs Docker + Docker Compose (if missing)
#   2. Logs in to GHCR
#   3. Downloads docker-compose.ghcr.yml and .env.example
#   4. Pulls all pre-built images from GHCR
#   5. Starts all containers
#   6. Waits for health checks
#   7. Configures Graylog Raw TCP input
#
# Author: CyberSentinel Security Team
# Version: 1.0.0
################################################################################

set -euo pipefail

# ========================================
# Color Definitions
# ========================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ========================================
# Configuration
# ========================================
DEPLOY_DIR="/opt/cybersentinel-manager"
CONTAINER_NAME="cybersentinel-manager"
NORMALIZER_CONTAINER="cybersentinel-normalizer"
MAX_WAIT_TIME=300
HEALTH_CHECK_INTERVAL=10
GRAYLOG_WAIT_TIME=180
COMPOSE_CMD=""

# GitHub / GHCR configuration
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GHCR_OWNER="${GHCR_OWNER:-cybersentinel-06}"
REPO_OWNER="${REPO_OWNER:-cybersentinel-06}"
REPO_NAME="${REPO_NAME:-CyberSentinel-SIEM-V2}"
BRANCH="${BRANCH:-main}"

# Image references
MANAGER_IMAGE="ghcr.io/${GHCR_OWNER}/cybersentinel-siem/manager:4.14.0"
NORMALIZER_IMAGE="ghcr.io/${GHCR_OWNER}/cybersentinel-siem/normalizer:6.3.9"
FORWARDER_IMAGE="ghcr.io/${GHCR_OWNER}/cybersentinel-siem/forwarder:1.0"

# ========================================
# Helper Functions
# ========================================
log_info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${MAGENTA}${BOLD}[STEP]${NC} $1"; }

separator() {
    echo -e "${BLUE}========================================================================${NC}"
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
        GHCR DEPLOYMENT v1.0  (Pre-built Images)
EOF
    echo -e "${NC}"
}

detect_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif docker-compose --version >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        COMPOSE_CMD=""
    fi
}

# ========================================
# Phase 0: Prompt for GitHub Token
# ========================================
prompt_github_token() {
    log_step "Phase 0: GitHub Token (for GHCR access)"
    separator

    if [ -n "$GITHUB_TOKEN" ]; then
        log_success "GitHub Token: Set (from environment)"
        return 0
    fi

    log_info "A GitHub Personal Access Token is REQUIRED to pull images from GHCR."
    log_info "Get a token at: https://github.com/settings/tokens"
    log_info "Required scope: read:packages"
    echo ""

    while true; do
        read -r -p "$(echo -e "${YELLOW}Enter your GitHub token: ${NC}")" token_input
        echo ""
        if [ -n "$token_input" ]; then
            GITHUB_TOKEN="$token_input"
            log_success "GitHub Token: Set"
            break
        else
            log_error "GitHub token is required for GHCR access."
        fi
    done
    echo ""
}

# ========================================
# Phase 1: System Preparation
# ========================================
prepare_system() {
    log_step "Phase 1: System Preparation"
    separator

    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root!"
        exit 1
    fi
    log_success "Running as root: OK"

    # Install curl
    if ! command -v curl >/dev/null 2>&1; then
        log_info "Installing curl..."
        apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 \
            || yum install -y -q curl >/dev/null 2>&1 \
            || { log_error "Failed to install curl"; exit 1; }
    fi

    # Install Docker
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
        log_success "Docker installed"
    else
        log_success "Docker: $(docker --version | awk '{print $3}' | tr -d ',')"
    fi

    if ! docker ps >/dev/null 2>&1; then
        systemctl start docker
        sleep 3
    fi

    # Install Docker Compose
    detect_compose_cmd
    if [ -z "$COMPOSE_CMD" ]; then
        log_info "Installing Docker Compose..."
        apt-get update -qq && apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 \
            || curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
                -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
        detect_compose_cmd
    fi
    log_success "Docker Compose: $($COMPOSE_CMD version --short 2>/dev/null || echo 'installed')"

    # Elasticsearch requirement
    local current_max_map
    current_max_map=$(sysctl -n vm.max_map_count 2>/dev/null || echo "0")
    if [ "$current_max_map" -lt 262144 ]; then
        sysctl -w vm.max_map_count=262144 >/dev/null 2>&1
        grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null \
            || echo "vm.max_map_count=262144" >> /etc/sysctl.conf
        log_success "vm.max_map_count set to 262144"
    fi

    echo ""
}

# ========================================
# Phase 2: GHCR Login & Pull
# ========================================
setup_ghcr() {
    log_step "Phase 2: Logging into GHCR & Pulling Images"
    separator

    # Login to GHCR
    log_info "Logging into GitHub Container Registry..."
    echo "$GITHUB_TOKEN" | docker login ghcr.io -u "${GHCR_OWNER}" --password-stdin 2>/dev/null
    log_success "GHCR login successful"
    echo ""

    # Create deploy directory
    mkdir -p "$DEPLOY_DIR"

    # Download docker-compose.ghcr.yml
    log_info "Downloading docker-compose.ghcr.yml..."
    local compose_url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/cybersentinel-manager/docker-compose.ghcr.yml"
    if curl -sSfL -H "Authorization: token ${GITHUB_TOKEN}" "$compose_url" -o "$DEPLOY_DIR/docker-compose.yml" 2>/dev/null; then
        log_success "docker-compose.yml downloaded"
    else
        log_error "Failed to download docker-compose.yml"
        exit 1
    fi

    # Download normalizer.sh
    log_info "Downloading normalizer.sh..."
    local normalizer_url="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/normalizer.sh"
    curl -sSfL -H "Authorization: token ${GITHUB_TOKEN}" "$normalizer_url" -o "$DEPLOY_DIR/normalizer.sh" 2>/dev/null \
        && chmod +x "$DEPLOY_DIR/normalizer.sh" \
        && log_success "normalizer.sh downloaded" \
        || log_warn "Could not download normalizer.sh — configure Graylog manually"

    # Generate .env if missing
    if [ ! -f "$DEPLOY_DIR/.env" ]; then
        log_info "Generating .env with secure defaults..."
        local password_secret
        password_secret=$(openssl rand -hex 48 2>/dev/null || < /dev/urandom tr -dc 'a-zA-Z0-9' 2>/dev/null | head -c 96)

        cat > "$DEPLOY_DIR/.env" << ENVEOF
# CyberSentinel Environment Configuration (auto-generated)
INDEXER_PASSWORD=SecurePassword123!
GRAYLOG_PASSWORD_SECRET=${password_secret}
GRAYLOG_ROOT_PASSWORD_SHA2=fa50a35e0407a4b40e738d862e46e9b96f95f5e27207f3b049341f441d7ec7de
GRAYLOG_HTTP_EXTERNAL_URI=http://127.0.0.1:9000/
GHCR_OWNER=${GHCR_OWNER}
ENVEOF
        chmod 600 "$DEPLOY_DIR/.env"
        log_success ".env generated (default Graylog password: Virtual%09)"
    fi

    echo ""

    # Pull images
    log_info "Pulling CyberSentinel images from GHCR..."
    for img in "$MANAGER_IMAGE" "$NORMALIZER_IMAGE" "$FORWARDER_IMAGE"; do
        log_info "  Pulling $img..."
        if docker pull "$img" 2>&1 | tail -1; then
            log_success "  $img"
        else
            log_error "  Failed to pull $img"
            exit 1
        fi
    done

    # Also pull infrastructure images
    log_info "Pulling infrastructure images..."
    docker pull mongo:8.0.5 2>&1 | tail -1
    docker pull docker.elastic.co/elasticsearch/elasticsearch-oss:7.10.2 2>&1 | tail -1
    log_success "All images pulled"
    echo ""
}

# ========================================
# Phase 3: Start Containers
# ========================================
start_containers() {
    log_step "Phase 3: Starting Containers"
    separator

    cd "$DEPLOY_DIR"

    # Create host bind mount directories
    mkdir -p /var/ossec/{etc,integrations,logs}
    mkdir -p /var/ossec/logs/{archives,alerts,firewall,wazuh,api,cluster}

    log_info "Starting all containers..."
    if $COMPOSE_CMD up -d; then
        log_success "All containers started"
    else
        log_error "Failed to start containers"
        exit 1
    fi

    # Fix bind mount permissions
    chown -R root:999 /var/ossec/etc /var/ossec/integrations /var/ossec/logs 2>/dev/null || true
    chmod -R g+w /var/ossec/etc /var/ossec/integrations /var/ossec/logs 2>/dev/null || true

    echo ""
    $COMPOSE_CMD ps
    echo ""
}

# ========================================
# Phase 4: Health Checks
# ========================================
wait_for_healthy() {
    log_step "Phase 4: Waiting for Services to be Healthy"
    separator

    log_info "Waiting for CyberSentinel Manager (up to 5 minutes)..."
    local elapsed=0

    while [ $elapsed -lt $MAX_WAIT_TIME ]; do
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "none")

        if [ "$health_status" = "healthy" ]; then
            echo ""
            log_success "CyberSentinel Manager is HEALTHY!"
            break
        elif [ "$health_status" = "unhealthy" ]; then
            echo ""
            log_error "Manager is UNHEALTHY! Check: docker logs $CONTAINER_NAME"
            exit 1
        fi

        printf "\r${CYAN}[INFO]${NC} Waiting... [${elapsed}s/${MAX_WAIT_TIME}s] Status: ${health_status}     "
        sleep $HEALTH_CHECK_INTERVAL
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
    done

    if [ $elapsed -ge $MAX_WAIT_TIME ]; then
        echo ""
        log_error "Timeout waiting for Manager health check"
        exit 1
    fi

    # Check all containers
    log_info "Checking all containers..."
    for cname in cybersentinel-manager cybersentinel-normalizer cybersentinel-forwarder elasticsearch mongodb; do
        if docker ps --format '{{.Names}}' | grep -q "^${cname}$"; then
            log_success "  $cname: running"
        else
            log_warn "  $cname: NOT running"
        fi
    done
    echo ""
}

# ========================================
# Phase 5: Configure Graylog
# ========================================
setup_graylog_input() {
    log_step "Phase 5: Configuring Graylog Raw TCP Input (port 5555)"
    separator

    local graylog_pass="Virtual%09"
    local graylog_url="http://localhost:9000"
    local elapsed=0

    log_info "Waiting for Graylog API..."
    while [ $elapsed -lt $GRAYLOG_WAIT_TIME ]; do
        if curl -s -u "admin:${graylog_pass}" "${graylog_url}/api/system/lbstatus" 2>/dev/null | grep -qi "alive"; then
            log_success "Graylog API is ready!"
            break
        fi
        printf "\r${CYAN}[INFO]${NC} Waiting for Graylog... [${elapsed}s/${GRAYLOG_WAIT_TIME}s]     "
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo ""

    if [ $elapsed -ge $GRAYLOG_WAIT_TIME ]; then
        log_warn "Graylog not ready — configure manually later"
        return 1
    fi

    # Check if input already exists
    if curl -s -u "admin:${graylog_pass}" -H "X-Requested-By: CyberSentinel" \
        "${graylog_url}/api/system/inputs" 2>/dev/null | grep -q "5555"; then
        log_success "Raw TCP input on port 5555 already exists"
        return 0
    fi

    # Create input
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -u "admin:${graylog_pass}" \
        -X POST "${graylog_url}/api/system/inputs" \
        -H "Content-Type: application/json" \
        -H "X-Requested-By: CyberSentinel" \
        -d '{
            "title": "CyberSentinel Forwarder Input",
            "type": "org.graylog2.inputs.raw.tcp.RawTCPInput",
            "configuration": {
                "port": 5555,
                "bind_address": "0.0.0.0",
                "recv_buffer_size": 1048576,
                "number_worker_threads": 2,
                "override_source": null,
                "store_full_message": true
            },
            "global": true
        }' 2>/dev/null)

    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log_success "Graylog Raw TCP input created on port 5555"
    else
        log_warn "Could not create input (HTTP $http_code) — create manually"
    fi
    echo ""
}

# ========================================
# Summary
# ========================================
display_summary() {
    separator
    echo -e "${GREEN}${BOLD}"
    cat << "EOF"
    DEPLOYMENT COMPLETE!
    CyberSentinel SIEM is running from pre-built GHCR images.
EOF
    echo -e "${NC}"
    separator

    echo ""
    log_info "Access Information:"
    echo ""
    echo -e "  ${BOLD}Graylog Web UI:${NC}"
    echo -e "    URL:      http://localhost:9000"
    echo -e "    Username: admin"
    echo -e "    Password: Virtual%09"
    echo ""
    echo -e "  ${BOLD}CyberSentinel Manager API:${NC}"
    echo -e "    URL:      https://localhost:55000"
    echo ""
    echo -e "  ${BOLD}Host Bind Mounts (live editing):${NC}"
    echo -e "    /var/ossec/etc            configs"
    echo -e "    /var/ossec/integrations    integrations"
    echo -e "    /var/ossec/logs            logs"
    echo ""
    echo -e "  ${BOLD}Commands:${NC}"
    echo -e "    docker exec $CONTAINER_NAME cybersentinel-control status"
    echo -e "    docker logs $CONTAINER_NAME -f"
    echo -e "    cd $DEPLOY_DIR && $COMPOSE_CMD ps"
    echo ""
    echo -e "  ${BOLD}Next Steps:${NC}"
    echo -e "    1. Run normalizer.sh to configure Graylog pipelines (33 rules)"
    echo -e "    2. Configure API keys in /var/ossec/etc/ossec.conf"
    echo -e "    3. Deploy CyberSentinel agents to monitored systems"
    echo ""
    separator
    log_success "CyberSentinel SIEM Platform is ready!"
    separator
}

# ========================================
# Main
# ========================================
main() {
    banner

    prompt_github_token
    prepare_system
    setup_ghcr
    start_containers
    wait_for_healthy
    setup_graylog_input || true
    display_summary
}

main "$@"
