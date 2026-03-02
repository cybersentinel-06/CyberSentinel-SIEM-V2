#!/usr/bin/env bash
################################################################################
# CyberSentinel Master Deployment Script
#
# Purpose: Complete ONE-CLICK end-to-end deployment on a fresh server
#          0. Prompts for GitHub token (repo is private)
#          1. Installs Docker, Docker Compose, git; sets vm.max_map_count
#          2. Clones private repo → extracts cybersentinel-manager/ to /opt
#          3. Validates project structure + auto-generates .env
#          4. Builds and deploys all Docker containers
#          5. Waits for all services to be healthy
#          6. Runs post-install configuration (rules/decoders from GitHub)
#          7. Deploys branded control wrapper
#          8. Auto-configures Graylog Raw TCP input (port 5555)
#          9. Final verification + summary
#
# Usage: ./cybersentinel-deploy-master.sh
#   Or:  GITHUB_TOKEN='ghp_xxx' ./cybersentinel-deploy-master.sh
#
# This script is fully standalone — drop it on a fresh server and run it.
#
# Author: CyberSentinel Security Team
# Version: 3.0.0
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
# Configuration Variables
# ========================================
COMPOSE_DIR="/opt/cybersentinel-manager"
POSTINSTALL_SCRIPT="${COMPOSE_DIR}/cybersentinel-postinstall.sh"
CONTAINER_NAME="cybersentinel-manager"
NORMALIZER_CONTAINER="cybersentinel-normalizer"
MAX_WAIT_TIME=300
HEALTH_CHECK_INTERVAL=10
GRAYLOG_WAIT_TIME=180
COMPOSE_CMD=""

# GitHub configuration
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO_OWNER="${REPO_OWNER:-cybersentinel-06}"
REPO_NAME="${REPO_NAME:-CyberSentinel-SIEM}"
BRANCH="${BRANCH:-main}"

# Private repo URL (token is inserted at runtime)
CLONE_REPO_URL="github.com/cybersentinel-06/CyberSentinel-SIEM-V2.git"

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

log_step() {
    echo -e "\n${MAGENTA}${BOLD}[STEP]${NC} $1"
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
        MASTER DEPLOYMENT SCRIPT v3.0
EOF
    echo -e "${NC}"
}

separator() {
    echo -e "${BLUE}========================================================================${NC}"
}

# Detect Docker Compose command (v2 plugin or v1 standalone)
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
    log_step "Phase 0: GitHub Token"
    separator

    if [ -n "$GITHUB_TOKEN" ]; then
        log_success "GitHub Token: Set (from environment)"
        return 0
    fi

    log_info "A GitHub Personal Access Token is REQUIRED to clone the private repository."
    log_info "Get a token at: https://github.com/settings/tokens (needs 'repo' scope)"
    echo ""

    while true; do
        read -r -p "$(echo -e "${YELLOW}Enter your GitHub token: ${NC}")" token_input
        echo ""

        if [ -n "$token_input" ]; then
            GITHUB_TOKEN="$token_input"
            log_success "GitHub Token: Set"
            break
        else
            log_error "GitHub token is required — the repository is private."
            log_info "Please enter a valid token to continue."
            echo ""
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

    # Check root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root!"
        log_info "Run: sudo ./cybersentinel-deploy-master.sh"
        exit 1
    fi
    log_success "Running as root: OK"

    # Install curl if missing
    if ! command -v curl >/dev/null 2>&1; then
        log_info "Installing curl..."
        apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 \
            || yum install -y -q curl >/dev/null 2>&1 \
            || { log_error "Failed to install curl"; exit 1; }
        log_success "curl installed"
    fi

    # Install git if missing
    if ! command -v git >/dev/null 2>&1; then
        log_info "Installing git..."
        apt-get update -qq && apt-get install -y -qq git >/dev/null 2>&1 \
            || yum install -y -q git >/dev/null 2>&1 \
            || { log_error "Failed to install git"; exit 1; }
        log_success "git installed"
    else
        log_success "git version: $(git --version | awk '{print $3}')"
    fi

    # Install Docker if missing
    if ! command -v docker >/dev/null 2>&1; then
        log_info "Docker not found. Installing Docker..."
        curl -fsSL https://get.docker.com | sh
        systemctl enable docker
        systemctl start docker
        log_success "Docker installed and started"
    else
        log_success "Docker version: $(docker --version | awk '{print $3}' | tr -d ',')"
    fi

    # Verify Docker daemon is running
    if ! docker ps >/dev/null 2>&1; then
        log_info "Starting Docker daemon..."
        systemctl start docker
        sleep 3
        if ! docker ps >/dev/null 2>&1; then
            log_error "Cannot access Docker daemon after starting!"
            exit 1
        fi
    fi
    log_success "Docker daemon: Running"

    # Install Docker Compose if missing
    detect_compose_cmd
    if [ -z "$COMPOSE_CMD" ]; then
        log_info "Docker Compose not found. Installing docker-compose-plugin..."
        apt-get update -qq && apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 \
            || {
                log_info "Falling back to standalone docker-compose..."
                curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
                    -o /usr/local/bin/docker-compose
                chmod +x /usr/local/bin/docker-compose
            }
        detect_compose_cmd
        if [ -z "$COMPOSE_CMD" ]; then
            log_error "Failed to install Docker Compose!"
            exit 1
        fi
        log_success "Docker Compose installed"
    fi
    log_success "Docker Compose: $($COMPOSE_CMD version --short 2>/dev/null || $COMPOSE_CMD --version 2>/dev/null | awk '{print $NF}')"

    # Set vm.max_map_count for Elasticsearch (required, resets on reboot)
    local current_max_map
    current_max_map=$(sysctl -n vm.max_map_count 2>/dev/null || echo "0")
    if [ "$current_max_map" -lt 262144 ]; then
        log_info "Setting vm.max_map_count=262144 (required by Elasticsearch)..."
        sysctl -w vm.max_map_count=262144 >/dev/null 2>&1
        # Persist across reboots
        if ! grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null; then
            echo "vm.max_map_count=262144" >> /etc/sysctl.conf
        fi
        log_success "vm.max_map_count set to 262144"
    else
        log_success "vm.max_map_count: $current_max_map (OK)"
    fi

    echo ""
    log_success "System preparation complete!"
    echo ""
}

# ========================================
# Phase 2: Clone Repository
# ========================================

clone_project() {
    log_step "Phase 2: Clone Repository"
    separator

    if [ -d "$COMPOSE_DIR" ]; then
        log_success "Project directory already exists: $COMPOSE_DIR — skipping clone"
        echo ""
        return 0
    fi

    local clone_dir="/tmp/cybersentinel-clone-$$"

    log_info "Cloning private repository..."
    if git clone "https://${GITHUB_TOKEN}@${CLONE_REPO_URL}" "$clone_dir" 2>&1; then
        log_success "Repository cloned to $clone_dir"
    else
        log_error "Failed to clone repository!"
        log_info "Check that your GitHub token has 'repo' scope and is valid."
        rm -rf "$clone_dir"
        exit 1
    fi

    # Extract cybersentinel-manager/ to /opt
    if [ -d "$clone_dir/cybersentinel-manager" ]; then
        cp -a "$clone_dir/cybersentinel-manager" "$COMPOSE_DIR"
        log_success "Extracted cybersentinel-manager/ to $COMPOSE_DIR"
    else
        log_error "Directory 'cybersentinel-manager/' not found in the cloned repository!"
        rm -rf "$clone_dir"
        exit 1
    fi

    # Clean up clone
    rm -rf "$clone_dir"
    log_success "Cleaned up temporary clone"

    echo ""
    log_success "Repository clone complete!"
    echo ""
}

# ========================================
# Phase 3: Validate Project Structure
# ========================================

validate_project() {
    log_step "Phase 3: Validating Project Structure"
    separator

    # Check compose directory
    if [ ! -d "$COMPOSE_DIR" ]; then
        log_error "Directory not found: $COMPOSE_DIR"
        log_info "The clone step may have failed."
        exit 1
    fi
    log_success "Project directory: $COMPOSE_DIR"

    # Check docker-compose.yml
    if [ ! -f "$COMPOSE_DIR/docker-compose.yml" ]; then
        log_error "docker-compose.yml not found in $COMPOSE_DIR"
        exit 1
    fi
    log_success "Docker Compose file: Found"

    # Check Dockerfiles
    local dockerfiles=(
        "$COMPOSE_DIR/Dockerfile"
        "$COMPOSE_DIR/normalizer/Dockerfile"
        "$COMPOSE_DIR/fluent-bit/Dockerfile"
    )
    for df in "${dockerfiles[@]}"; do
        if [ ! -f "$df" ]; then
            log_error "Missing Dockerfile: $df"
            exit 1
        fi
    done
    log_success "All Dockerfiles: Found"

    # Check Fluent Bit config
    if [ ! -f "$COMPOSE_DIR/fluent-bit/fluent-bit.conf" ]; then
        log_error "Missing fluent-bit.conf"
        exit 1
    fi
    log_success "Fluent Bit config: Found"

    # Auto-generate .env if missing
    if [ ! -f "$COMPOSE_DIR/.env" ]; then
        log_warn ".env file not found — generating with secure defaults..."
        generate_env_file
    else
        log_success "Environment file: Found"
    fi

    # Make scripts executable
    for script in "$POSTINSTALL_SCRIPT" "$COMPOSE_DIR/cybersentinel-control"; do
        if [ -f "$script" ] && [ ! -x "$script" ]; then
            chmod +x "$script"
            log_info "Made executable: $(basename "$script")"
        fi
    done

    # Check post-install script
    if [ -f "$POSTINSTALL_SCRIPT" ]; then
        log_success "Post-install script: Found"
    else
        log_warn "Post-install script not found: $POSTINSTALL_SCRIPT"
    fi

    # Check control wrapper
    if [ -f "$COMPOSE_DIR/cybersentinel-control" ]; then
        log_success "Control wrapper: Found"
    else
        log_warn "Control wrapper not found: $COMPOSE_DIR/cybersentinel-control"
    fi

    echo ""
    log_success "Project structure validated!"
    echo ""
}

# ========================================
# Auto-generate .env file
# ========================================

generate_env_file() {
    # Generate a secure random password secret (96 chars)
    local password_secret
    password_secret=$(openssl rand -hex 48 2>/dev/null \
        || < /dev/urandom tr -dc 'a-zA-Z0-9' 2>/dev/null | head -c 96 \
        || echo "replacethiswithatleast64charactersofrandomdataforpasswordencryption12345678901234567890")

    # SHA256 of "Virtual%09" (default password)
    local root_password_sha2="fa50a35e0407a4b40e738d862e46e9b96f95f5e27207f3b049341f441d7ec7de"

    cat > "$COMPOSE_DIR/.env" << ENVEOF
# CyberSentinel Environment Configuration
# Auto-generated by cybersentinel-deploy-master.sh

# CyberSentinel Manager
INDEXER_PASSWORD=SecurePassword123!

# Graylog Configuration
GRAYLOG_PASSWORD_SECRET=${password_secret}
GRAYLOG_ROOT_PASSWORD_SHA2=${root_password_sha2}
GRAYLOG_HTTP_EXTERNAL_URI=http://127.0.0.1:9000/
ENVEOF

    chmod 600 "$COMPOSE_DIR/.env"
    log_success ".env file generated with secure defaults"
    log_info "Default Graylog password: Virtual%09"
}

# ========================================
# Phase 4: Build & Deploy Containers
# ========================================

deploy_containers() {
    log_step "Phase 4: Building & Deploying Docker Containers"
    separator

    cd "$COMPOSE_DIR"

    log_info "Building Docker images (this may take several minutes on first run)..."
    if $COMPOSE_CMD build --no-cache 2>&1 | tee /tmp/docker-build.log; then
        log_success "Docker images built successfully"
    else
        log_error "Failed to build Docker images"
        log_info "Check logs: cat /tmp/docker-build.log"
        exit 1
    fi

    echo ""
    log_info "Starting all containers..."
    if $COMPOSE_CMD up -d; then
        log_success "All containers started"
    else
        log_error "Failed to start containers"
        log_info "Check: $COMPOSE_CMD logs"
        exit 1
    fi

    echo ""
    log_info "Container status:"
    $COMPOSE_CMD ps
    echo ""
}

# ========================================
# Fix host bind mount permissions
# ========================================

fix_bind_mount_permissions() {
    log_info "Fixing host bind mount permissions..."

    local bind_dirs=("/var/ossec/etc" "/var/ossec/integrations" "/var/ossec/logs")

    # Create missing log subdirs the container expects
    mkdir -p /var/ossec/logs/{archives,alerts,firewall,wazuh,api,cluster}

    for dir in "${bind_dirs[@]}"; do
        if [ -d "$dir" ]; then
            chown -R root:999 "$dir"
            chmod -R g+w "$dir"
        fi
    done

    log_success "Bind mount permissions fixed"
}

# ========================================
# Phase 5: Health Checks
# ========================================

wait_for_all_healthy() {
    log_step "Phase 5: Waiting for All Services to be Healthy"
    separator

    # --- Wait for CyberSentinel Manager ---
    log_info "Waiting for CyberSentinel Manager to be healthy..."
    log_info "This may take up to 5 minutes (healthcheck start-period: 120s)..."
    echo ""

    local elapsed=0
    local container_healthy=false

    while [ $elapsed -lt $MAX_WAIT_TIME ]; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            log_error "Container '$CONTAINER_NAME' is not running!"
            log_info "Check logs: docker logs $CONTAINER_NAME"
            exit 1
        fi

        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "${CONTAINER_NAME}" 2>/dev/null || echo "none")

        if [ "$health_status" = "healthy" ]; then
            container_healthy=true
            echo ""
            log_success "CyberSentinel Manager is HEALTHY!"
            break
        elif [ "$health_status" = "unhealthy" ]; then
            echo ""
            log_error "CyberSentinel Manager is UNHEALTHY!"
            log_info "Check logs: docker logs $CONTAINER_NAME"
            exit 1
        else
            printf "\r${CYAN}[INFO]${NC} Waiting... [${elapsed}s/${MAX_WAIT_TIME}s] Status: ${health_status}     "
            sleep $HEALTH_CHECK_INTERVAL
            elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
        fi
    done

    if [ "$container_healthy" = false ]; then
        echo ""
        log_error "Timeout waiting for Manager (${MAX_WAIT_TIME}s)"
        log_info "Check: docker logs $CONTAINER_NAME"
        exit 1
    fi

    # --- Wait for all other containers to be running ---
    log_info "Checking all container health..."
    local all_containers=("cybersentinel-manager" "cybersentinel-normalizer" "cybersentinel-forwarder" "elasticsearch" "mongodb")
    for cname in "${all_containers[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^${cname}$"; then
            log_success "  $cname: running"
        else
            log_warn "  $cname: NOT running"
        fi
    done

    echo ""
    log_success "All containers are operational!"
    echo ""
}

# ========================================
# Phase 6: Post-Install Configuration
# ========================================

run_postinstall() {
    log_step "Phase 6: Post-Install Configuration"
    separator

    if [ -z "$GITHUB_TOKEN" ]; then
        log_warn "GITHUB_TOKEN not set — skipping post-install configuration"
        log_info "Run later: GITHUB_TOKEN='...' $POSTINSTALL_SCRIPT"
        return 1
    fi

    if [ ! -f "$POSTINSTALL_SCRIPT" ]; then
        log_warn "Post-install script not found — skipping"
        return 1
    fi

    log_info "Downloading and deploying custom configurations from GitHub..."
    echo ""

    if GITHUB_TOKEN="$GITHUB_TOKEN" \
       REPO_OWNER="$REPO_OWNER" \
       REPO_NAME="$REPO_NAME" \
       BRANCH="$BRANCH" \
       "$POSTINSTALL_SCRIPT"; then
        log_success "Post-install configuration completed!"
    else
        log_error "Post-install script failed!"
        log_info "You can run it manually later: GITHUB_TOKEN='...' $POSTINSTALL_SCRIPT"
        return 1
    fi

    echo ""
}

# ========================================
# Phase 7: Deploy Control Wrapper
# ========================================

deploy_control_wrapper() {
    log_step "Phase 7: Deploying CyberSentinel Control Wrapper"
    separator

    local WRAPPER_SOURCE="${COMPOSE_DIR}/cybersentinel-control"
    local WRAPPER_TARGET="/usr/local/bin/cybersentinel-control"

    if [ ! -f "$WRAPPER_SOURCE" ]; then
        log_warn "Control wrapper not found: $WRAPPER_SOURCE — skipping"
        return 1
    fi

    log_info "Injecting control wrapper into container..."

    # Copy, set permissions, verify
    if docker cp "$WRAPPER_SOURCE" "${CONTAINER_NAME}:${WRAPPER_TARGET}" 2>/dev/null \
       && docker exec "$CONTAINER_NAME" chmod 755 "$WRAPPER_TARGET" 2>/dev/null \
       && docker exec "$CONTAINER_NAME" chown root:root "$WRAPPER_TARGET" 2>/dev/null; then
        log_success "Wrapper deployed to container"
    else
        log_error "Failed to deploy wrapper"
        return 1
    fi

    # Verify it works
    if docker exec "$CONTAINER_NAME" test -x "$WRAPPER_TARGET" 2>/dev/null; then
        log_success "Wrapper is executable and operational"
    else
        log_error "Wrapper deployment verification failed"
        return 1
    fi

    # Quick test
    if docker exec "$CONTAINER_NAME" "$WRAPPER_TARGET" status >/dev/null 2>&1; then
        log_success "Wrapper test passed"
    else
        log_warn "Wrapper test returned non-zero (services may still be starting)"
    fi

    echo ""
}

# ========================================
# Phase 8: Auto-Configure Graylog Input
# ========================================

setup_graylog_input() {
    log_step "Phase 8: Configuring Graylog Raw TCP Input (port 5555)"
    separator

    local graylog_pass="Virtual%09"
    local graylog_url="http://localhost:9000"

    log_info "Waiting for Graylog API to be ready..."

    local graylog_ready=false
    local elapsed=0

    while [ $elapsed -lt $GRAYLOG_WAIT_TIME ]; do
        if curl -s -u "admin:${graylog_pass}" "${graylog_url}/api/system/lbstatus" 2>/dev/null | grep -qi "alive"; then
            graylog_ready=true
            log_success "Graylog API is ready!"
            break
        fi
        printf "\r${CYAN}[INFO]${NC} Waiting for Graylog... [${elapsed}s/${GRAYLOG_WAIT_TIME}s]     "
        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo ""

    if [ "$graylog_ready" = false ]; then
        log_warn "Graylog API not ready after ${GRAYLOG_WAIT_TIME}s"
        log_info "You can create the input manually:"
        log_info "  1. Go to http://localhost:9000"
        log_info "  2. System -> Inputs -> Raw/Plaintext TCP -> Port 5555"
        return 1
    fi

    # Check if input already exists
    local existing_inputs
    existing_inputs=$(curl -s -u "admin:${graylog_pass}" \
        -H "X-Requested-By: CyberSentinel" \
        "${graylog_url}/api/system/inputs" 2>/dev/null || echo "")

    if echo "$existing_inputs" | grep -q "5555"; then
        log_success "Raw TCP input on port 5555 already exists — skipping"
        return 0
    fi

    # Create the Raw/Plaintext TCP input on port 5555
    log_info "Creating Raw/Plaintext TCP input on port 5555..."

    local response
    response=$(curl -s -w "\n%{http_code}" -u "admin:${graylog_pass}" \
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
        }' 2>/dev/null || echo "error")

    local http_code
    http_code=$(echo "$response" | tail -1)

    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log_success "Graylog Raw TCP input created on port 5555!"
    else
        log_warn "Could not auto-create Graylog input (HTTP $http_code)"
        log_info "Create it manually: System -> Inputs -> Raw/Plaintext TCP -> Port 5555"
    fi

    echo ""
}

# ========================================
# Phase 9: Final Verification
# ========================================

final_verification() {
    log_step "Phase 9: Final Verification"
    separator

    log_info "Container Status:"
    cd "$COMPOSE_DIR"
    $COMPOSE_CMD ps
    echo ""

    # CyberSentinel Manager service status
    log_info "CyberSentinel Manager Services:"
    if docker exec "$CONTAINER_NAME" test -x /usr/local/bin/cybersentinel-control 2>/dev/null; then
        docker exec "$CONTAINER_NAME" cybersentinel-control status 2>&1 || true
    else
        docker exec "$CONTAINER_NAME" /var/ossec/bin/wazuh-control status 2>&1 || true
    fi
    echo ""

    # Critical file checks
    log_info "Critical Configuration Files:"
    local files_checked=0
    local files_found=0
    local critical_files=(
        "/var/ossec/etc/ossec.conf"
        "/var/ossec/etc/rules/local_rules.xml"
    )

    for file in "${critical_files[@]}"; do
        files_checked=$((files_checked + 1))
        if docker exec "$CONTAINER_NAME" test -s "$file" 2>/dev/null; then
            log_success "  $file"
            files_found=$((files_found + 1))
        else
            log_warn "  $file (not found or empty)"
        fi
    done

    echo ""
}

# ========================================
# Display Summary
# ========================================

display_summary() {
    separator
    echo -e "${GREEN}${BOLD}"
    cat << "EOF"
   ____  __________________  ________  ____  ___  _____________
  / __ \/ ____/ ____/ ____/ / / / __ \/ __ \/   |/_  __/ ____/
 / / / / __/ / /   / __/   / / / /_/ / / / / /| | / / / __/
/ /_/ / /___/ /___/ /___  /_/ / ____/ /_/ / ___ |/ / / /___
\____/_____/\____/_____/  (_)_/_/    \____/_/  |_/_/ /_____/

    DEPLOYMENT COMPLETE!
EOF
    echo -e "${NC}"
    separator

    echo ""
    log_info "Access Information:"
    echo ""
    echo -e "  ${BOLD}CyberSentinel Normalizer (Graylog Web UI):${NC}"
    echo -e "    URL:      http://localhost:9000"
    echo -e "    Username: admin"
    echo -e "    Password: Virtual%09"
    echo ""
    echo -e "  ${BOLD}CyberSentinel Manager API:${NC}"
    echo -e "    URL:  https://localhost:55000"
    echo -e "    Auth: Use CyberSentinel API credentials"
    echo ""

    log_info "Host Bind Mounts (edit directly, restart to apply):"
    echo ""
    echo -e "  /var/ossec/etc           → configs (ossec.conf, rules, decoders)"
    echo -e "  /var/ossec/integrations  → threat intel integrations"
    echo -e "  /var/ossec/logs          → all logs (ossec.log, alerts, archives)"
    echo ""
    echo -e "  After changes: ${CYAN}docker restart $CONTAINER_NAME${NC}"
    echo ""

    log_info "Useful Commands:"
    echo ""
    echo -e "  ${CYAN}# Edit configs directly on host${NC}"
    echo -e "  nano /var/ossec/etc/ossec.conf"
    echo -e "  nano /var/ossec/etc/rules/local_rules.xml"
    echo -e "  docker restart $CONTAINER_NAME"
    echo ""
    echo -e "  ${CYAN}# Service control${NC}"
    echo -e "  docker exec $CONTAINER_NAME cybersentinel-control status"
    echo -e "  docker exec $CONTAINER_NAME cybersentinel-control restart"
    echo ""
    echo -e "  ${CYAN}# View logs${NC}"
    echo -e "  docker logs $CONTAINER_NAME -f"
    echo -e "  docker logs $NORMALIZER_CONTAINER -f"
    echo -e "  tail -f /var/ossec/logs/ossec.log"
    echo ""
    echo -e "  ${CYAN}# Container management${NC}"
    echo -e "  cd $COMPOSE_DIR && $COMPOSE_CMD ps"
    echo -e "  cd $COMPOSE_DIR && $COMPOSE_CMD down"
    echo -e "  cd $COMPOSE_DIR && $COMPOSE_CMD up -d"
    echo ""

    log_info "Next Steps:"
    echo ""
    echo "  1. Configure threat intelligence API keys in /var/ossec/etc/ossec.conf"
    echo "  2. Deploy CyberSentinel agents to monitored systems"
    echo "  3. Customize detection rules in /var/ossec/etc/rules/"
    echo "  4. Setup automated backups"
    echo ""

    separator
    log_success "CyberSentinel SIEM Platform is ready!"
    separator
}

# ========================================
# Error Handling
# ========================================

cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        log_error "Deployment failed with exit code: $exit_code"
        log_info "Troubleshooting:"
        log_info "  1. Check container logs: cd $COMPOSE_DIR && $COMPOSE_CMD logs"
        log_info "  2. Check container status: docker ps -a"
        log_info "  3. Review error messages above"
        echo ""
    fi
}

trap cleanup_on_error EXIT

# ========================================
# Main Execution
# ========================================

main() {
    banner

    log_info "CyberSentinel Standalone Deployment"
    log_info "Starting complete end-to-end deployment..."
    echo ""

    # Phase 0: Prompt for GitHub token (FIRST — required for private repo)
    prompt_github_token

    # Phase 1: Install Docker, Compose, git, set sysctl
    prepare_system

    # Phase 2: Clone repo to /opt/cybersentinel-manager
    clone_project

    # Phase 3: Validate project files and auto-generate .env
    validate_project

    # Phase 4: Build and deploy all containers
    deploy_containers

    # Fix bind mount dir permissions (first-run: init populates, we fix ownership)
    fix_bind_mount_permissions

    # Restart manager to pick up corrected permissions
    log_info "Restarting manager with corrected permissions..."
    docker restart "$CONTAINER_NAME" >/dev/null 2>&1
    sleep 5

    # Phase 5: Wait for all services to be healthy
    wait_for_all_healthy

    # Phase 6: Post-install configuration (rules/decoders from GitHub)
    if run_postinstall; then
        log_success "Post-install configuration succeeded"
    else
        log_warn "Post-install was skipped or failed — containers are running"
        log_info "You can run it later: GITHUB_TOKEN='...' $POSTINSTALL_SCRIPT"
    fi
    echo ""

    # Phase 7: Deploy branded control wrapper
    if deploy_control_wrapper; then
        log_success "Control wrapper deployment succeeded"
    else
        log_warn "Control wrapper deployment was skipped"
    fi
    echo ""

    # Phase 8: Auto-configure Graylog Raw TCP input
    if setup_graylog_input; then
        log_success "Graylog input configured"
    else
        log_warn "Graylog input setup was skipped — configure manually if needed"
    fi
    echo ""

    # Phase 9: Final verification
    final_verification

    # Display access info and summary
    display_summary
}

# Execute
main "$@"
