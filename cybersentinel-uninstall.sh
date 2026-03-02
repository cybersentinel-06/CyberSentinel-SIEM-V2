#!/usr/bin/env bash
################################################################################
# CyberSentinel Uninstall Script
#
# Purpose: Completely removes the CyberSentinel SIEM deployment
#          - Stops and removes all containers
#          - Removes Docker images, volumes, and networks
#          - Removes host bind mount directories (/var/ossec/*)
#          - Removes project directory (/opt/cybersentinel-manager)
#          - Cleans up sysctl config
#
#          Does NOT uninstall: Docker, Docker Compose, git, curl
#
# Usage: sudo ./cybersentinel-uninstall.sh
#
# Author: CyberSentinel Security Team
################################################################################

set -uo pipefail

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
COMPOSE_DIR="/opt/cybersentinel-manager"

CONTAINERS=(
    "cybersentinel-forwarder"
    "cybersentinel-normalizer"
    "cybersentinel-manager"
    "elasticsearch"
    "mongodb"
)

IMAGES=(
    "cybersentinel/manager:4.14.0"
    "cybersentinel/normalizer:6.1"
    "cybersentinel/forwarder:1.0"
    "mongo:8.0.5"
    "docker.elastic.co/elasticsearch/elasticsearch-oss:7.10.2"
    "graylog/graylog:6.1"
    "wazuh/wazuh-manager:4.14.0"
    "fluent/fluent-bit:3.0"
)

VOLUMES=(
    "cybersentinel-manager_cybersentinel-data"
    "cybersentinel-manager_cybersentinel-queue"
    "cybersentinel-manager_cybersentinel-api-configuration"
    "cybersentinel-manager_cybersentinel-agentless"
    "cybersentinel-manager_cybersentinel-ruleset"
    "cybersentinel-manager_cybersentinel-wodles"
    "cybersentinel-manager_cybersentinel-stats"
    "cybersentinel-manager_mongodb-data"
    "cybersentinel-manager_elasticsearch-data"
    "cybersentinel-manager_cybersentinel-normalizer-data"
    "cybersentinel-manager_cybersentinel-normalizer-journal"
)

NETWORKS=(
    "cybersentinel-manager_cybersentinel-network"
)

HOST_DIRS=(
    "/var/ossec/etc"
    "/var/ossec/integrations"
    "/var/ossec/logs"
)

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

separator() {
    echo -e "${BLUE}========================================================================${NC}"
}

banner() {
    echo -e "${RED}${BOLD}"
    cat << "EOF"
   ______      __              _____            __  _            __
  / ____/_  __/ /_  ___  _____/ ___/___  ____  / /_(_)___  ___  / /
 / /   / / / / __ \/ _ \/ ___/\__ \/ _ \/ __ \/ __/ / __ \/ _ \/ /
/ /___/ /_/ / /_/ /  __/ /   ___/ /  __/ / / / /_/ / / / /  __/ /
\____/\__, /_.___/\___/_/   /____/\___/_/ /_/\__/_/_/ /_/\___/_/
     /____/
        UNINSTALL SCRIPT
EOF
    echo -e "${NC}"
}

# ========================================
# Pre-flight Checks
# ========================================

preflight() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root!"
        exit 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log_warn "Docker not found — skipping container/image/volume cleanup"
        DOCKER_AVAILABLE=false
    else
        DOCKER_AVAILABLE=true
    fi
}

# ========================================
# Confirmation
# ========================================

confirm_uninstall() {
    separator
    echo ""
    echo -e "${RED}${BOLD}  WARNING: This will permanently remove:${NC}"
    echo ""
    echo "    - All CyberSentinel containers (manager, normalizer, forwarder, elasticsearch, mongodb)"
    echo "    - All Docker images (cybersentinel/*, mongo, elasticsearch, graylog, wazuh, fluent-bit)"
    echo "    - All Docker volumes (ALL data: logs, databases, queues, configs)"
    echo "    - Host directories: /var/ossec/etc, /var/ossec/integrations, /var/ossec/logs"
    echo "    - Project directory: /opt/cybersentinel-manager"
    echo "    - vm.max_map_count sysctl entry"
    echo ""
    echo -e "${GREEN}  Will NOT remove: Docker, Docker Compose, git, curl${NC}"
    echo ""
    separator
    echo ""

    read -r -p "$(echo -e "${RED}${BOLD}Are you sure you want to uninstall? Type 'YES' to confirm: ${NC}")" confirm
    echo ""

    if [ "$confirm" != "YES" ]; then
        log_info "Uninstall cancelled."
        exit 0
    fi
}

# ========================================
# Step 1: Stop & Remove Containers
# ========================================

remove_containers() {
    log_step "Step 1: Stopping & Removing Containers"
    separator

    if [ "$DOCKER_AVAILABLE" = false ]; then
        log_warn "Docker not available — skipping"
        return
    fi

    # Try docker compose down first (cleanest)
    if [ -f "$COMPOSE_DIR/docker-compose.yml" ]; then
        log_info "Running docker compose down..."
        cd "$COMPOSE_DIR" && docker compose down 2>/dev/null || true
        cd /
    fi

    # Force remove any remaining containers
    for container in "${CONTAINERS[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
            log_info "Removing container: $container"
            docker stop "$container" 2>/dev/null || true
            docker rm -f "$container" 2>/dev/null || true
            log_success "  Removed $container"
        else
            log_info "  $container — not found (already removed)"
        fi
    done

    echo ""
    log_success "All containers removed"
}

# ========================================
# Step 2: Remove Docker Images
# ========================================

remove_images() {
    log_step "Step 2: Removing Docker Images"
    separator

    if [ "$DOCKER_AVAILABLE" = false ]; then
        log_warn "Docker not available — skipping"
        return
    fi

    for image in "${IMAGES[@]}"; do
        if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${image}$"; then
            log_info "Removing image: $image"
            docker rmi -f "$image" 2>/dev/null || true
            log_success "  Removed $image"
        else
            log_info "  $image — not found"
        fi
    done

    # Remove any dangling images from the build
    local dangling
    dangling=$(docker images -f "dangling=true" -q 2>/dev/null)
    if [ -n "$dangling" ]; then
        log_info "Removing dangling images..."
        docker rmi -f $dangling 2>/dev/null || true
    fi

    echo ""
    log_success "All images removed"
}

# ========================================
# Step 3: Remove Docker Volumes
# ========================================

remove_volumes() {
    log_step "Step 3: Removing Docker Volumes"
    separator

    if [ "$DOCKER_AVAILABLE" = false ]; then
        log_warn "Docker not available — skipping"
        return
    fi

    for volume in "${VOLUMES[@]}"; do
        if docker volume ls --format '{{.Name}}' | grep -q "^${volume}$"; then
            log_info "Removing volume: $volume"
            docker volume rm -f "$volume" 2>/dev/null || true
            log_success "  Removed $volume"
        else
            log_info "  $volume — not found"
        fi
    done

    echo ""
    log_success "All volumes removed"
}

# ========================================
# Step 4: Remove Docker Networks
# ========================================

remove_networks() {
    log_step "Step 4: Removing Docker Networks"
    separator

    if [ "$DOCKER_AVAILABLE" = false ]; then
        log_warn "Docker not available — skipping"
        return
    fi

    for network in "${NETWORKS[@]}"; do
        if docker network ls --format '{{.Name}}' | grep -q "^${network}$"; then
            log_info "Removing network: $network"
            docker network rm "$network" 2>/dev/null || true
            log_success "  Removed $network"
        else
            log_info "  $network — not found"
        fi
    done

    echo ""
    log_success "All networks removed"
}

# ========================================
# Step 5: Remove Host Bind Mount Directories
# ========================================

remove_host_dirs() {
    log_step "Step 5: Removing Host Directories"
    separator

    for dir in "${HOST_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            log_info "Removing: $dir"
            rm -rf "$dir"
            log_success "  Removed $dir"
        else
            log_info "  $dir — not found"
        fi
    done

    # Clean up /var/ossec if empty
    if [ -d "/var/ossec" ]; then
        rmdir /var/ossec 2>/dev/null && log_success "  Removed /var/ossec (empty)" \
            || log_warn "  /var/ossec not empty — left in place"
    fi

    echo ""
    log_success "Host directories removed"
}

# ========================================
# Step 6: Remove Project Directory
# ========================================

remove_project() {
    log_step "Step 6: Removing Project Directory"
    separator

    if [ -d "$COMPOSE_DIR" ]; then
        log_info "Removing: $COMPOSE_DIR"
        rm -rf "$COMPOSE_DIR"
        log_success "  Removed $COMPOSE_DIR"
    else
        log_info "  $COMPOSE_DIR — not found"
    fi

    echo ""
    log_success "Project directory removed"
}

# ========================================
# Step 7: Clean Up System Config
# ========================================

cleanup_system() {
    log_step "Step 7: Cleaning Up System Configuration"
    separator

    # Remove vm.max_map_count from sysctl.conf
    if grep -q "vm.max_map_count" /etc/sysctl.conf 2>/dev/null; then
        log_info "Removing vm.max_map_count from /etc/sysctl.conf"
        sed -i '/vm.max_map_count/d' /etc/sysctl.conf
        log_success "  Removed sysctl entry"
    else
        log_info "  vm.max_map_count not found in sysctl.conf"
    fi

    # Remove temp build log
    if [ -f /tmp/docker-build.log ]; then
        rm -f /tmp/docker-build.log
        log_info "  Removed /tmp/docker-build.log"
    fi

    echo ""
    log_success "System cleanup complete"
}

# ========================================
# Summary
# ========================================

show_summary() {
    separator
    echo -e "${GREEN}${BOLD}"
    cat << "EOF"

    UNINSTALL COMPLETE

EOF
    echo -e "${NC}"
    separator

    echo ""
    log_success "CyberSentinel has been completely removed from this system."
    echo ""
    log_info "What was removed:"
    echo "  - All containers, images, volumes, and networks"
    echo "  - /opt/cybersentinel-manager (project files)"
    echo "  - /var/ossec/etc, /var/ossec/integrations, /var/ossec/logs"
    echo "  - vm.max_map_count sysctl entry"
    echo ""
    log_info "What was kept:"
    echo "  - Docker & Docker Compose"
    echo "  - git, curl"
    echo ""
    log_info "To reinstall, run the deploy script again:"
    echo "  ./cybersentinel-deploy-master.sh"
    echo ""
    separator
}

# ========================================
# Main
# ========================================

main() {
    banner
    preflight
    confirm_uninstall

    remove_containers
    remove_images
    remove_volumes
    remove_networks
    remove_host_dirs
    remove_project
    cleanup_system
    show_summary
}

main "$@"
