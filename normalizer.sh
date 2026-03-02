#!/usr/bin/env bash
################################################################################
# CyberSentinel Normalizer Configuration Script
#
# Purpose: Configures Graylog (CyberSentinel Normalizer) via API:
#          1. Creates Raw TCP Input on port 5555
#          2. Creates CyberSentinel Indexer (index set)
#          3. Creates CyberSentinel Stream (routes all messages)
#          4. Downloads pipeline rules from private GitHub repo
#          5. Creates pipeline rules in Graylog
#          6. Creates CyberSentinel PIPELINE with all rules in Stage 0
#          7. Connects pipeline to stream
#          8. Restarts normalizer container
#
# Usage: sudo ./normalizer.sh
#   Or:  GITHUB_TOKEN='ghp_xxx' sudo ./normalizer.sh
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
GRAYLOG_URL="http://localhost:9000"
GRAYLOG_USER="admin"
GRAYLOG_PASS="Virtual%09"
GRAYLOG_API="${GRAYLOG_URL}/api"
GRAYLOG_WAIT_TIME=180

GITHUB_TOKEN="${GITHUB_TOKEN:-}"
REPO_OWNER="cybersentinel-06"
REPO_NAME="CyberSentinel-SIEM"
BRANCH="main"
GITHUB_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}"
GITHUB_PIPELINE_PATH="GRAYLOG/PIPLINES"

TEMP_DIR="/tmp/cybersentinel-normalizer-$$"

# Pipeline rule names (must match filenames on GitHub)
PIPELINE_RULES=(
    "AI_response"
    "Add is_internal_ip Field"
    "Enrich with Dest-GeoIP Data"
    "Enrich with GeoIP Data"
    "Extract Wazuh Fields"
    "Fortigate logs Normalization"
    "JSON Parser"
    "No src-ip Geolocation Fields"
    "Remove filebeat prefixes"
    "SRC-IP Geolocation Fields"
    "Suricata logs Normalization"
    "Tag after-hours logins (India Time) for Windows logs"
    "detect_new_ip_for_user (UBA)"
    "extract_all_emails"
    "extract_username_linux (UBA)"
    "failed login"
    "flag_src_foreign (UBA)"
    "normalize cybersentinel flooded logs"
    "normalize_user_and_ip"
    "parse 4624 event for UBA"
    "remove_field_execd"
    "rename_field_ai_ml_logs"
    "successful login"
    "tag_FIM_logs"
    "tag_Malware-Detection_logs"
    "tag_Router_logs"
    "tag_Vulnerability_logs"
    "tag_Windows-Event_logs"
    "tag_authentication_logs"
    "tag_cloud_logs"
    "tag_firewall_logs"
    "tag_network_logs"
    "tag_syslog_logs"
    "windows logs normalization"
)

# ========================================
# Helper Functions
# ========================================

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${MAGENTA}${BOLD}[STEP]${NC} $1"; }

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
        NORMALIZER CONFIGURATION SCRIPT
EOF
    echo -e "${NC}"
}

cleanup() {
    rm -rf "$TEMP_DIR" 2>/dev/null
}
trap cleanup EXIT

# Graylog API helper — returns response body (last line is http_code)
graylog_api() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    local args=(-s -w "\n%{http_code}" -u "${GRAYLOG_USER}:${GRAYLOG_PASS}")
    args+=(-H "Content-Type: application/json")
    args+=(-H "X-Requested-By: CyberSentinel")

    if [ "$method" = "GET" ]; then
        curl "${args[@]}" "${GRAYLOG_API}${endpoint}" 2>/dev/null
    elif [ "$method" = "POST" ]; then
        curl "${args[@]}" -X POST -d "$data" "${GRAYLOG_API}${endpoint}" 2>/dev/null
    elif [ "$method" = "PUT" ]; then
        curl "${args[@]}" -X PUT -d "$data" "${GRAYLOG_API}${endpoint}" 2>/dev/null
    fi
}

# Extract HTTP code from graylog_api response
get_http_code() { echo "$1" | tail -1; }
get_body() { echo "$1" | sed '$d'; }

# ========================================
# Phase 0: Pre-flight
# ========================================

preflight() {
    log_step "Phase 0: Pre-flight Checks"
    separator

    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root!"
        exit 1
    fi

    if [ -z "$GITHUB_TOKEN" ]; then
        log_info "GITHUB_TOKEN not set. Enter your GitHub token to download pipeline rules."
        read -r -p "$(echo -e "${YELLOW}GitHub Token: ${NC}")" token_input
        echo ""
        if [ -n "$token_input" ]; then
            GITHUB_TOKEN="$token_input"
        else
            log_error "GitHub token is required for downloading pipeline rules."
            exit 1
        fi
    fi
    log_success "GitHub Token: Set"

    if ! docker ps --format '{{.Names}}' | grep -q "^cybersentinel-normalizer$"; then
        log_error "cybersentinel-normalizer container is not running!"
        exit 1
    fi
    log_success "Normalizer container: Running"

    mkdir -p "$TEMP_DIR"
    log_success "Pre-flight checks passed"
    echo ""
}

# ========================================
# Phase 1: Wait for Graylog API
# ========================================

wait_for_graylog() {
    log_step "Phase 1: Waiting for Graylog API"
    separator

    local elapsed=0
    while [ $elapsed -lt $GRAYLOG_WAIT_TIME ]; do
        if curl -s -u "${GRAYLOG_USER}:${GRAYLOG_PASS}" "${GRAYLOG_URL}/api/system/lbstatus" 2>/dev/null | grep -qi "alive"; then
            log_success "Graylog API is ready!"
            echo ""
            return 0
        fi
        printf "\r${CYAN}[INFO]${NC} Waiting for Graylog... [${elapsed}s/${GRAYLOG_WAIT_TIME}s]     "
        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo ""
    log_error "Graylog API not ready after ${GRAYLOG_WAIT_TIME}s"
    exit 1
}

# ========================================
# Phase 2: Create Input
# ========================================

create_input() {
    log_step "Phase 2: Creating Raw TCP Input (port 5555)"
    separator

    # Check if input already exists
    local response
    response=$(graylog_api GET "/system/inputs")
    local body
    body=$(get_body "$response")

    if echo "$body" | grep -q "5555"; then
        log_success "Raw TCP input on port 5555 already exists — skipping"
        echo ""
        return 0
    fi

    response=$(graylog_api POST "/system/inputs" '{
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
    }')

    local code
    code=$(get_http_code "$response")

    if [ "$code" = "201" ] || [ "$code" = "200" ]; then
        log_success "Raw TCP input created on port 5555"
    else
        log_warn "Could not create input (HTTP $code) — may already exist"
    fi
    echo ""
}

# ========================================
# Phase 3: Create Index Set
# ========================================

create_index_set() {
    log_step "Phase 3: Creating CyberSentinel Indexer (Index Set)"
    separator

    # Check if index set already exists
    local response
    response=$(graylog_api GET "/system/indices/index_sets")
    local body
    body=$(get_body "$response")

    if echo "$body" | grep -q "CyberSentinel Indexer"; then
        log_success "CyberSentinel Indexer already exists — skipping"
        INDEX_SET_ID=$(echo "$body" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for s in data.get('index_sets', []):
    if s['title'] == 'CyberSentinel Indexer':
        print(s['id'])
        break
" 2>/dev/null)
        log_info "Index Set ID: $INDEX_SET_ID"
        echo ""
        return 0
    fi

    response=$(graylog_api POST "/system/indices/index_sets" '{
        "title": "CyberSentinel Indexer",
        "description": "CyberSentinel SIEM index set — 30 days max retention, daily rotation",
        "index_prefix": "cybersentinel",
        "shards": 1,
        "replicas": 0,
        "rotation_strategy_class": "org.graylog2.indexer.rotation.strategies.TimeBasedRotationStrategy",
        "rotation_strategy": {
            "type": "org.graylog2.indexer.rotation.strategies.TimeBasedRotationStrategyConfig",
            "rotation_period": "P1D",
            "rotate_empty_index_set": false,
            "max_rotation_period": null
        },
        "retention_strategy_class": "org.graylog2.indexer.retention.strategies.DeletionRetentionStrategy",
        "retention_strategy": {
            "type": "org.graylog2.indexer.retention.strategies.DeletionRetentionStrategyConfig",
            "max_number_of_indices": 30
        },
        "index_analyzer": "standard",
        "index_optimization_max_num_segments": 1,
        "index_optimization_disabled": false,
        "field_type_refresh_interval": 5000,
        "writable": true,
        "default": false
    }')

    local code
    code=$(get_http_code "$response")
    body=$(get_body "$response")

    if [ "$code" = "200" ] || [ "$code" = "201" ]; then
        INDEX_SET_ID=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
        log_success "CyberSentinel Indexer created"
        log_info "Index Set ID: $INDEX_SET_ID"
    else
        log_error "Failed to create index set (HTTP $code)"
        log_error "Response: $body"
        exit 1
    fi
    echo ""
}

# ========================================
# Phase 4: Create Stream
# ========================================

create_stream() {
    log_step "Phase 4: Creating CyberSentinel Stream"
    separator

    # Check if stream already exists
    local response
    response=$(graylog_api GET "/streams")
    local body
    body=$(get_body "$response")

    if echo "$body" | grep -q '"title":"CyberSentinel"'; then
        log_success "CyberSentinel stream already exists — skipping"
        STREAM_ID=$(echo "$body" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for s in data.get('streams', []):
    if s['title'] == 'CyberSentinel':
        print(s['id'])
        break
" 2>/dev/null)
        log_info "Stream ID: $STREAM_ID"
        echo ""
        return 0
    fi

    # Create stream linked to CyberSentinel Indexer
    response=$(graylog_api POST "/streams" "{
        \"title\": \"CyberSentinel\",
        \"description\": \"CyberSentinel SIEM — routes all messages to CyberSentinel Indexer\",
        \"index_set_id\": \"${INDEX_SET_ID}\",
        \"matching_type\": \"OR\",
        \"remove_matches_from_default_stream\": true
    }")

    local code
    code=$(get_http_code "$response")
    body=$(get_body "$response")

    if [ "$code" = "201" ] || [ "$code" = "200" ]; then
        STREAM_ID=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin)['stream_id'])" 2>/dev/null)
        log_success "CyberSentinel stream created"
        log_info "Stream ID: $STREAM_ID"
    else
        log_error "Failed to create stream (HTTP $code)"
        log_error "Response: $body"
        exit 1
    fi

    # Add a rule to match ALL messages (field presence on "source")
    log_info "Adding stream rule: match all messages..."
    response=$(graylog_api POST "/streams/${STREAM_ID}/rules" '{
        "field": "source",
        "type": 5,
        "inverted": false,
        "description": "Match all messages (every message has a source field)"
    }')
    code=$(get_http_code "$response")

    if [ "$code" = "201" ] || [ "$code" = "200" ]; then
        log_success "Stream rule added: match all messages"
    else
        log_warn "Could not add stream rule (HTTP $code)"
    fi

    # Start the stream
    log_info "Starting CyberSentinel stream..."
    response=$(graylog_api POST "/streams/${STREAM_ID}/resume" "")
    code=$(get_http_code "$response")

    if [ "$code" = "204" ] || [ "$code" = "200" ]; then
        log_success "CyberSentinel stream started"
    else
        log_warn "Could not start stream (HTTP $code) — may already be running"
    fi

    echo ""
}

# ========================================
# Phase 5: Download Pipeline Rules from GitHub
# ========================================

download_pipeline_rules() {
    log_step "Phase 5: Downloading Pipeline Rules from GitHub"
    separator

    mkdir -p "$TEMP_DIR/rules"

    local downloaded=0
    local failed=0

    for rule_name in "${PIPELINE_RULES[@]}"; do
        # URL-encode the filename (spaces → %20)
        local encoded_name
        encoded_name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$rule_name'))" 2>/dev/null)

        local url="${GITHUB_RAW}/${GITHUB_PIPELINE_PATH}/${encoded_name}"
        local dest="$TEMP_DIR/rules/${rule_name}"

        if curl -sSfL -H "Authorization: token ${GITHUB_TOKEN}" "$url" -o "$dest" 2>/dev/null && [ -s "$dest" ]; then
            log_success "  Downloaded: $rule_name"
            downloaded=$((downloaded + 1))
        else
            rm -f "$dest"
            log_warn "  Failed: $rule_name"
            failed=$((failed + 1))
        fi
    done

    echo ""
    log_info "Downloaded: $downloaded, Failed: $failed"

    if [ "$downloaded" -eq 0 ]; then
        log_error "No pipeline rules downloaded! Check GITHUB_TOKEN and repo access."
        exit 1
    fi
    echo ""
}

# ========================================
# Phase 6: Create Pipeline Rules in Graylog
# ========================================

create_pipeline_rules() {
    log_step "Phase 6: Creating Pipeline Rules in Graylog"
    separator

    # Get existing rules to avoid duplicates
    local existing_response
    existing_response=$(graylog_api GET "/system/pipelines/rule")
    local existing_body
    existing_body=$(get_body "$existing_response")

    CREATED_RULE_IDS=()
    local created=0
    local skipped=0
    local failed=0

    for rule_file in "$TEMP_DIR/rules"/*; do
        [ -f "$rule_file" ] || continue

        local rule_name
        rule_name=$(basename "$rule_file")
        local rule_source
        rule_source=$(cat "$rule_file")

        # Check if rule already exists
        if echo "$existing_body" | grep -q "\"title\":\"${rule_name}\""; then
            log_info "  Already exists: $rule_name"
            # Get the existing rule ID
            local existing_id
            existing_id=$(echo "$existing_body" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for r in data:
    if r['title'] == '$rule_name':
        print(r['id'])
        break
" 2>/dev/null)
            if [ -n "$existing_id" ]; then
                CREATED_RULE_IDS+=("$existing_id")
            fi
            skipped=$((skipped + 1))
            continue
        fi

        # Escape the rule source for JSON
        local escaped_source
        escaped_source=$(python3 -c "
import json, sys
with open('$rule_file', 'r') as f:
    content = f.read()
print(json.dumps({'title': '$rule_name', 'description': 'CyberSentinel pipeline rule', 'source': content}))
" 2>/dev/null)

        if [ -z "$escaped_source" ]; then
            log_warn "  Failed to encode: $rule_name"
            failed=$((failed + 1))
            continue
        fi

        local response
        response=$(graylog_api POST "/system/pipelines/rule" "$escaped_source")
        local code
        code=$(get_http_code "$response")
        local body
        body=$(get_body "$response")

        if [ "$code" = "200" ] || [ "$code" = "201" ]; then
            local rule_id
            rule_id=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
            CREATED_RULE_IDS+=("$rule_id")
            log_success "  Created: $rule_name"
            created=$((created + 1))
        else
            log_warn "  Failed: $rule_name (HTTP $code)"
            failed=$((failed + 1))
        fi
    done

    echo ""
    log_info "Created: $created, Skipped (existing): $skipped, Failed: $failed"
    log_info "Total rules available: ${#CREATED_RULE_IDS[@]}"
    echo ""
}

# ========================================
# Phase 7: Create Pipeline
# ========================================

create_pipeline() {
    log_step "Phase 7: Creating CyberSentinel PIPELINE"
    separator

    # Check if pipeline already exists
    local response
    response=$(graylog_api GET "/system/pipelines/pipeline")
    local body
    body=$(get_body "$response")

    if echo "$body" | grep -q "CyberSentinel PIPELINE"; then
        log_success "CyberSentinel PIPELINE already exists — skipping creation"
        PIPELINE_ID=$(echo "$body" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data:
    if p['title'] == 'CyberSentinel PIPELINE':
        print(p['id'])
        break
" 2>/dev/null)
        log_info "Pipeline ID: $PIPELINE_ID"
        echo ""
        return 0
    fi

    # Build the pipeline source with all rules in Stage 0
    local rule_lines=""
    for rule_file in "$TEMP_DIR/rules"/*; do
        [ -f "$rule_file" ] || continue
        local rule_name
        rule_name=$(basename "$rule_file")
        rule_lines="${rule_lines}  rule \"${rule_name}\"\n"
    done

    # Also include any existing rules that were skipped
    local pipeline_source
    pipeline_source="pipeline \"CyberSentinel PIPELINE\"\nstage 0 match either\n${rule_lines}end"

    # Create the pipeline via API
    local payload
    payload=$(python3 -c "
import json
source = '''$(echo -e "$pipeline_source")'''
print(json.dumps({
    'title': 'CyberSentinel PIPELINE',
    'description': 'Main CyberSentinel processing pipeline — all rules in Stage 0',
    'source': source
}))
" 2>/dev/null)

    response=$(graylog_api POST "/system/pipelines/pipeline" "$payload")
    local code
    code=$(get_http_code "$response")
    body=$(get_body "$response")

    if [ "$code" = "200" ] || [ "$code" = "201" ]; then
        PIPELINE_ID=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
        log_success "CyberSentinel PIPELINE created"
        log_info "Pipeline ID: $PIPELINE_ID"
    else
        log_error "Failed to create pipeline (HTTP $code)"
        log_error "Response: $body"
        exit 1
    fi
    echo ""
}

# ========================================
# Phase 8: Connect Pipeline to Stream
# ========================================

connect_pipeline_to_stream() {
    log_step "Phase 8: Connecting Pipeline to CyberSentinel Stream"
    separator

    if [ -z "${PIPELINE_ID:-}" ] || [ -z "${STREAM_ID:-}" ]; then
        log_error "Pipeline ID or Stream ID is missing!"
        exit 1
    fi

    local response
    response=$(graylog_api POST "/system/pipelines/connections/to_stream" "{
        \"stream_id\": \"${STREAM_ID}\",
        \"pipeline_ids\": [\"${PIPELINE_ID}\"]
    }")

    local code
    code=$(get_http_code "$response")

    if [ "$code" = "200" ] || [ "$code" = "201" ]; then
        log_success "Pipeline connected to CyberSentinel stream"
    else
        log_warn "Could not connect pipeline to stream (HTTP $code) — may already be connected"
    fi
    echo ""
}

# ========================================
# Phase 9: Restart Normalizer
# ========================================

restart_normalizer() {
    log_step "Phase 9: Restarting CyberSentinel Normalizer"
    separator

    log_info "Restarting cybersentinel-normalizer container..."
    docker restart cybersentinel-normalizer

    log_info "Waiting for Graylog to be ready again..."
    sleep 10

    local elapsed=0
    while [ $elapsed -lt 120 ]; do
        if curl -s -u "${GRAYLOG_USER}:${GRAYLOG_PASS}" "${GRAYLOG_URL}/api/system/lbstatus" 2>/dev/null | grep -qi "alive"; then
            log_success "Graylog is back online!"
            echo ""
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    log_warn "Graylog may still be starting — check http://localhost:9000"
    echo ""
}

# ========================================
# Summary
# ========================================

show_summary() {
    separator
    echo -e "${GREEN}${BOLD}"
    cat << "EOF"

    NORMALIZER CONFIGURATION COMPLETE

EOF
    echo -e "${NC}"
    separator

    echo ""
    log_info "What was configured:"
    echo ""
    echo -e "  ${BOLD}Input:${NC}"
    echo "    Raw/Plaintext TCP on port 5555"
    echo ""
    echo -e "  ${BOLD}Index Set:${NC}"
    echo "    Name: CyberSentinel Indexer"
    echo "    Rotation: Daily (P1D)"
    echo "    Retention: 30 days max (delete oldest)"
    echo ""
    echo -e "  ${BOLD}Stream:${NC}"
    echo "    Name: CyberSentinel"
    echo "    Routes: All messages → CyberSentinel Indexer"
    echo "    Removes from: Default stream"
    echo ""
    echo -e "  ${BOLD}Pipeline:${NC}"
    echo "    Name: CyberSentinel PIPELINE"
    echo "    Stage 0: ${#PIPELINE_RULES[@]} rules (match either)"
    echo "    Connected to: CyberSentinel stream"
    echo ""
    echo -e "  ${BOLD}Access:${NC}"
    echo "    Graylog UI: http://localhost:9000"
    echo "    Username:   admin"
    echo "    Password:   Virtual%09"
    echo ""
    separator
}

# ========================================
# Main
# ========================================

main() {
    banner

    log_info "CyberSentinel Normalizer Configuration"
    log_info "Configuring Graylog via API..."
    echo ""

    preflight
    wait_for_graylog
    create_input
    create_index_set
    create_stream
    download_pipeline_rules
    create_pipeline_rules
    create_pipeline
    connect_pipeline_to_stream
    restart_normalizer
    show_summary
}

main "$@"
