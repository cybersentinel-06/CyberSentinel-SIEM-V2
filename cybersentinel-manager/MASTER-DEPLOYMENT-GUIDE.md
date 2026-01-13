# CyberSentinel Master Deployment Guide

## Overview

The **Master Deployment Script** (`cybersentinel-deploy-master.sh`) provides complete end-to-end automated deployment of the CyberSentinel SIEM platform. It orchestrates the entire process from Docker container deployment to post-installation configuration.

## What This Script Does

This master script automates the **complete deployment pipeline**:

```
┌─────────────────────────────────────────────────────────────┐
│                   MASTER DEPLOYMENT FLOW                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Phase 1: Prerequisites Validation                           │
│    ✓ Check Docker installed (20.10+)                        │
│    ✓ Check Docker Compose installed (2.0+)                  │
│    ✓ Verify file structure integrity                        │
│    ✓ Validate GitHub token (for post-install)               │
│                                                               │
│  Phase 2: Docker Container Deployment                        │
│    ✓ Build Docker images (cybersentinel-manager)            │
│    ✓ Start all containers (docker-compose up -d)            │
│    ✓ Containers: Manager, Graylog, ES, MongoDB, Fluent-bit  │
│                                                               │
│  Phase 3: Health Check & Monitoring                          │
│    ✓ Wait for containers to start (max 5 minutes)           │
│    ✓ Monitor cybersentinel-manager health status            │
│    ✓ Verify all services operational                        │
│    ✓ Check Wazuh Manager processes                          │
│                                                               │
│  Phase 4: Post-Install Configuration                         │
│    ✓ Execute cybersentinel-postinstall.sh                   │
│    ✓ Download configs from GitHub                           │
│    ✓ Deploy rules, decoders, integrations                   │
│    ✓ Fix permissions inside container                       │
│    ✓ Restart Wazuh Manager                                  │
│                                                               │
│  Phase 5: Final Verification                                 │
│    ✓ Verify all containers running                          │
│    ✓ Check critical files deployed                          │
│    ✓ Display access information                             │
│    ✓ Show next steps                                        │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Key Differences from Manual Deployment

### Before (Manual Process):
```bash
# Step 1: Deploy containers manually
cd cybersentinel-manager
docker-compose build
docker-compose up -d

# Step 2: Wait and hope containers are healthy
sleep 120  # Just guessing...

# Step 3: Manually run post-install
cd ..
export GITHUB_TOKEN="ghp_xxxx"
./cybersentinel-postinstall.sh

# Step 4: Check if everything worked
docker ps
docker logs cybersentinel-manager
```

### Now (Master Script):
```bash
# ONE COMMAND - Everything automated!
export GITHUB_TOKEN="ghp_xxxx"
./cybersentinel-deploy-master.sh
```

## Prerequisites

### System Requirements
- **OS**: Linux (Ubuntu 20.04+, Debian 11+, RHEL 8+)
- **CPU**: 4+ cores (8+ recommended)
- **RAM**: 8GB minimum (16GB+ recommended)
- **Disk**: 100GB minimum (500GB+ recommended)

### Required Software
- **Docker**: 20.10+
- **Docker Compose**: 2.0+

### GitHub Access
- **GitHub Personal Access Token** with `repo` scope
- Access to private repository: `cybersentinel-06/CyberSentinel-SIEM`

## Installation

### Step 1: Install Docker & Docker Compose

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Logout and login for group changes to take effect
exit
```

### Step 2: Prepare Environment

```bash
# Navigate to project directory
cd /home/soc/Docker-CyberSentinel

# Configure environment variables (optional but recommended)
cd cybersentinel-manager
cp .env.example .env
nano .env
# Update: INDEXER_PASSWORD, GRAYLOG credentials, etc.
cd ..

# Make master script executable (if not already)
chmod +x cybersentinel-deploy-master.sh
```

### Step 3: Set GitHub Token

```bash
# Export your GitHub Personal Access Token
export GITHUB_TOKEN="ghp_your_token_here"

# Optional: Set custom repository (if different)
export REPO_OWNER="your-org"
export REPO_NAME="your-repo"
export BRANCH="main"
```

### Step 4: Run Master Deployment

```bash
# Execute the master script
./cybersentinel-deploy-master.sh
```

## What Happens During Deployment

### Phase 1: Prerequisites Validation (30 seconds)
```
✓ Checking Docker access
✓ Verifying Docker version
✓ Checking Docker Compose version
✓ Validating directory structure
✓ Verifying docker-compose.yml exists
✓ Checking .env file
✓ Validating post-install script
✓ Verifying GitHub token is set
```

### Phase 2: Docker Container Deployment (3-5 minutes)
```
→ Building Docker images (cybersentinel-manager, sentinelai)
→ Pulling base images (MongoDB, Elasticsearch, Graylog, Fluent-bit)
→ Starting all containers with docker-compose up -d
→ Creating Docker networks and volumes
→ Displaying initial container status
```

### Phase 3: Health Check Monitoring (2-5 minutes)
```
→ Waiting for cybersentinel-manager healthcheck
→ Monitoring container health status (updates every 10s)
→ Maximum wait time: 5 minutes
→ Verifying Wazuh Manager services inside container
→ Checking all supporting containers (Graylog, ES, MongoDB)
```

### Phase 4: Post-Install Configuration (1-2 minutes)
```
→ Executing cybersentinel-postinstall.sh
→ Downloading configurations from GitHub:
  • ossec.conf
  • Custom rules (12+ files)
  • Custom decoders (6+ files)
  • Integration scripts (7+ files)
→ Deploying files to container using docker cp
→ Fixing ownership and permissions (root:wazuh, 640/750)
→ Restarting Wazuh Manager inside container
→ Verifying critical files deployed
```

### Phase 5: Final Verification & Summary (30 seconds)
```
→ Checking all container statuses
→ Verifying Wazuh Manager processes
→ Validating critical configuration files
→ Displaying access URLs and credentials
→ Showing useful management commands
→ Listing next steps and documentation
```

## Expected Output

### Successful Deployment
```
   ______      __              _____            __  _            __
  / ____/_  __/ /_  ___  _____/ ___/___  ____  / /_(_)___  ___  / /
 / /   / / / / __ \/ _ \/ ___/\__ \/ _ \/ __ \/ __/ / __ \/ _ \/ /
/ /___/ /_/ / /_/ /  __/ /   ___/ /  __/ / / / /_/ / / / /  __/ /
\____/\__, /_.___/\___/_/   /____/\___/_/ /_/\__/_/_/ /_/\___/_/
     /____/
        MASTER DEPLOYMENT SCRIPT

[INFO] CyberSentinel Master Deployment Script
[INFO] Starting complete end-to-end deployment...

[STEP] Phase 1: Validating Prerequisites
========================================================================
[SUCCESS] Docker access: OK
[SUCCESS] Docker version: 24.0.7
[SUCCESS] Docker Compose version: 2.21.0
[SUCCESS] Compose directory: /home/soc/Docker-CyberSentinel/cybersentinel-manager
[SUCCESS] Docker Compose file: Found
[SUCCESS] Environment file: Found
[SUCCESS] Post-install script: Found
[SUCCESS] GitHub Token: Set
[SUCCESS] All prerequisites validated successfully!

[STEP] Phase 2: Deploying Docker Containers
========================================================================
[INFO] Building Docker images (this may take several minutes)...
[SUCCESS] Docker images built successfully
[INFO] Starting Docker containers...
[SUCCESS] Docker containers started

[STEP] Phase 3: Waiting for Containers to be Healthy
========================================================================
[INFO] Waiting for container 'cybersentinel-manager' to be healthy...
[INFO] Waiting... [0s/300s] Status: starting
[INFO] Waiting... [10s/300s] Status: starting
...
[SUCCESS] Container 'cybersentinel-manager' is HEALTHY!

[STEP] Phase 4: Running Post-Install Configuration
========================================================================
[INFO] Executing post-install script...
[SUCCESS] Post-install configuration completed successfully!

[STEP] Phase 5: Final Verification & Summary
========================================================================
[SUCCESS] ✓ ossec.conf exists
[SUCCESS] ✓ local_rules.xml exists

   ____  __________________  ________  ____  ___  _____________
  / __ \/ ____/ ____/ ____/ / / / __ \/ __ \/   |/_  __/ ____/
 / / / / __/ / /   / __/   / / / /_/ / / / / /| | / / / __/
/ /_/ / /___/ /___/ /___  /_/ / ____/ /_/ / ___ |/ / / /___
\____/_____/\____/_____/  (_)_/_/    \____/_/  |_/_/ /_____/

    DEPLOYMENT COMPLETE!

========================================================================
[SUCCESS] CyberSentinel SIEM Platform is ready for production use!
========================================================================
```

## Post-Deployment

### Access Information

**CyberSentinel Manager API:**
- URL: `https://localhost:55000`
- Auth: Wazuh API credentials

**Graylog Web UI:**
- URL: `http://localhost:9000`
- Username: `admin`
- Password: `admin` (**CHANGE THIS IMMEDIATELY!**)

### Useful Management Commands

```bash
# View container logs
docker logs cybersentinel-manager -f

# Check Wazuh Manager status
docker exec cybersentinel-manager /var/ossec/bin/wazuh-control status

# List connected agents
docker exec cybersentinel-manager /var/ossec/bin/agent_control -l

# Test log parsing
docker exec -it cybersentinel-manager /var/ossec/bin/wazuh-logtest

# View all container status
cd cybersentinel-manager && docker-compose ps

# Stop all containers
cd cybersentinel-manager && docker-compose down

# Restart specific container
cd cybersentinel-manager && docker-compose restart cybersentinel-manager
```

## Troubleshooting

### Error: "Cannot access Docker daemon"

**Solution:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Or run with sudo
sudo ./cybersentinel-deploy-master.sh
```

### Error: "Docker Compose is not installed"

**Solution:**
```bash
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### Error: "GITHUB_TOKEN is not set"

**Solution:**
```bash
# Generate token at: https://github.com/settings/tokens
# Scope required: repo (Full control of private repositories)

export GITHUB_TOKEN="ghp_your_new_token_here"
./cybersentinel-deploy-master.sh
```

### Error: "Timeout waiting for container to be healthy"

**Possible causes:**
1. Insufficient system resources
2. Port conflicts
3. Configuration errors

**Solution:**
```bash
# Check container logs
docker logs cybersentinel-manager

# Check resource usage
docker stats

# Verify no port conflicts
sudo netstat -tulpn | grep -E '(1514|1515|55000|9000|12201)'

# Check container health manually
docker inspect --format='{{.State.Health}}' cybersentinel-manager
```

### Post-Install Script Fails

**Solution:**
```bash
# Verify GitHub token is valid
curl -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/user

# Run troubleshooting script
./troubleshoot-github.sh

# Run post-install manually after deployment
export GITHUB_TOKEN="ghp_your_token"
./cybersentinel-postinstall.sh
```

## Advanced Usage

### Custom Repository Configuration

```bash
# Deploy from custom GitHub repository
export GITHUB_TOKEN="ghp_your_token"
export REPO_OWNER="your-organization"
export REPO_NAME="your-siem-repo"
export BRANCH="production"

./cybersentinel-deploy-master.sh
```

### Skip Post-Install (Containers Only)

If you want to deploy containers without running post-install:

```bash
# Don't set GITHUB_TOKEN
unset GITHUB_TOKEN

# Script will deploy containers but skip post-install
./cybersentinel-deploy-master.sh

# Run post-install later manually
export GITHUB_TOKEN="ghp_xxx"
./cybersentinel-postinstall.sh
```

### Re-run Post-Install Only

If containers are already running and you only want to update configurations:

```bash
# Just run the post-install script directly
export GITHUB_TOKEN="ghp_xxx"
./cybersentinel-postinstall.sh
```

## Script Architecture

### Error Handling
- **Set -euo pipefail**: Strict error handling
- **Trap on EXIT**: Cleanup on errors
- **Validation checks**: Every step validated before proceeding
- **Detailed logging**: Color-coded progress messages

### Key Features
- **Idempotent**: Safe to run multiple times
- **Automated health monitoring**: Waits for containers to be healthy
- **Progress tracking**: Real-time status updates
- **Rollback friendly**: Easy to stop and restart
- **Comprehensive logging**: All actions logged with timestamps

## Comparison with Other Scripts

| Script | Purpose | When to Use |
|--------|---------|-------------|
| **cybersentinel-deploy-master.sh** | **Complete automated deployment** | **First-time setup, full redeployment** |
| cybersentinel-postinstall.sh | Configuration deployment only | Update configs on running system |
| cybersentinel-postinstall-local.sh | Deploy configs from local files | No GitHub access |
| troubleshoot-github.sh | Diagnose GitHub connectivity | Debug token issues |

## Security Considerations

### GitHub Token Security

```bash
# NEVER commit tokens to version control
echo "export GITHUB_TOKEN='ghp_xxx'" >> ~/.bashrc  # ✗ BAD

# Use environment variables
export GITHUB_TOKEN='ghp_xxx'  # ✓ GOOD (current session only)

# Or use a secrets management tool
# - HashiCorp Vault
# - AWS Secrets Manager
# - Azure Key Vault
```

### Post-Deployment Hardening

```bash
# 1. Change Graylog admin password
# Visit: http://localhost:9000
# Login: admin / admin
# Settings → Users → Change Password

# 2. Configure firewall
sudo ufw allow 1514/tcp  # Agent communication
sudo ufw allow 1515/tcp  # Agent registration
sudo ufw allow 55000/tcp # API
sudo ufw enable

# 3. Secure .env file
chmod 600 cybersentinel-manager/.env
chown root:root cybersentinel-manager/.env

# 4. Setup automated backups
# See: cybersentinel-manager/volumes.md
```

## Next Steps After Deployment

1. **Access Graylog UI** → Create GELF input (port 12201)
2. **Configure threat intelligence** → Add API keys to ossec.conf
3. **Deploy agents** → Install Wazuh agents on monitored systems
4. **Customize rules** → Edit detection rules in config/rules/
5. **Setup backups** → Configure automated backups (volumes.md)
6. **Change passwords** → Update default Graylog admin password
7. **Enable TLS** → Configure SSL for agent communication
8. **Monitor alerts** → Review alerts in Graylog dashboards

## Documentation References

- **This Guide**: Master deployment overview
- **README.md**: Project overview
- **cybersentinel-manager/README.md**: Complete operational guide
- **POST-INSTALL-GUIDE.md**: Post-install script documentation
- **TROUBLESHOOTING-SUMMARY.md**: Common issues and solutions
- **cybersentinel-manager/DEPLOYMENT.md**: Production deployment guide
- **cybersentinel-manager/volumes.md**: Backup and restore procedures

## Support

For issues or questions:

1. Check logs: `docker logs cybersentinel-manager`
2. Review troubleshooting section above
3. Consult: **TROUBLESHOOTING-SUMMARY.md**
4. Check Wazuh documentation: https://documentation.wazuh.com/

---

**Master Deployment Script v1.0.0**

Built for CyberSentinel SIEM Platform | Automated, Reliable, Production-Ready
