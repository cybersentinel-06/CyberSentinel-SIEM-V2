# CyberSentinel - Production SIEM Platform

**CyberSentinel** is a production-ready Security Information and Event Management (SIEM) platform based on Wazuh Manager 4.14.x, deployed using Docker for maximum portability and maintainability.

## What is CyberSentinel?

CyberSentinel uses **Wazuh Manager** internally with **no exposed Wazuh components**. It presents itself as a standalone SIEM platform with:

- **Manager-Only Deployment** - No dashboard, no indexer
- **Docker-Native** - Fully containerized for easy deployment
- **AI-Powered** - SentinelAI for intelligent alert analysis
- **Production-Ready** - Upgrade-safe, tested architecture
- **Custom Branding** - No "Wazuh" references in external interfaces

## Quick Start

```bash
cd cybersentinel-manager
cp .env.example .env
nano .env  # Configure your settings
docker-compose build
docker-compose up -d
```

## Repository Structure

```
Docker-CyberSentinel/
├── README.md                          # This file
├── cybersentinel-collector.sh         # Original bare-metal installer (reference)
└── cybersentinel-manager/             # Docker deployment
    ├── README.md                      # Complete documentation
    ├── DEPLOYMENT.md                  # Production deployment guide
    ├── STRUCTURE.md                   # Architecture overview
    ├── volumes.md                     # Backup and restore procedures
    ├── docker-compose.yml             # Service orchestration
    ├── Dockerfile                     # CyberSentinel Manager image
    ├── .env.example                   # Environment template
    ├── config/                        # SIEM configuration
    ├── sentinelai/                    # AI analysis engine
    └── fluent-bit/                    # Log forwarding
```

## Features

### Core Components

- **CyberSentinel Manager** - Wazuh 4.14.x based SIEM engine
- **SentinelAI** - OpenAI-powered alert analysis
- **Fluent Bit** - Log forwarding to Graylog
- **No Dashboard** - Manager-only deployment
- **No Indexer** - External Graylog for visualization

### Capabilities

- Host-based intrusion detection (HIDS)
- Log data analysis
- File integrity monitoring (FIM)
- Vulnerability detection
- Configuration assessment (SCA)
- Incident response
- Regulatory compliance (PCI-DSS, HIPAA, GDPR)
- Cloud security (AWS, Azure, GCP)
- Container security (Docker, Kubernetes)

### Integrations

- **Threat Intelligence**: VirusTotal, AlienVault OTX, AbuseIPDB, MISP
- **SOAR**: Shuffle automation
- **Log Management**: Graylog, Elasticsearch
- **Custom Integrations**: Network devices (Cisco, MikroTik, HP)

## Documentation

- **[README.md](cybersentinel-manager/README.md)** - Complete user guide
- **[DEPLOYMENT.md](cybersentinel-manager/DEPLOYMENT.md)** - Production deployment
- **[STRUCTURE.md](cybersentinel-manager/STRUCTURE.md)** - Architecture details
- **[volumes.md](cybersentinel-manager/volumes.md)** - Backup procedures

## System Requirements

- **OS**: Linux (Ubuntu 20.04+, Debian 11+, RHEL 8+)
- **CPU**: 4+ cores (8+ recommended)
- **RAM**: 8GB minimum (16GB+ recommended)
- **Disk**: 100GB minimum (500GB+ recommended)
- **Docker**: 20.10+
- **Docker Compose**: 2.0+

## Installation

### 1. Install Prerequisites

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### 2. Deploy CyberSentinel

```bash
cd cybersentinel-manager

# Configure environment
cp .env.example .env
nano .env  # Set passwords, API keys, Graylog host

# Build and start
docker-compose build
docker-compose up -d

# Verify
docker-compose ps
docker-compose logs -f
```

### 3. Connect Agents

```bash
# On agent machine
curl -so wazuh-agent.deb https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.0-1_amd64.deb
sudo WAZUH_MANAGER='CYBERSENTINEL_IP' WAZUH_AGENT_NAME='agent-name' dpkg -i wazuh-agent.deb
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent
```

## Configuration

### Required Configuration Files

The deployment includes template configuration files that **MUST be replaced** with your actual configurations:

1. **config/ossec.conf** - Main SIEM configuration
2. **config/rules/*.xml** - Custom detection rules
3. **config/decoders/*.xml** - Log parsing decoders
4. **config/integrations/*.py** - Threat intelligence scripts

See the original `cybersentinel-collector.sh` script for references to your private repository files.

### Environment Variables

Configure in `.env`:

```env
INDEXER_PASSWORD=YourSecurePassword
OPENAI_API_KEY=sk-your-key
GRAYLOG_HOST=graylog.example.com
GRAYLOG_PORT=12201
```

## Upgrading

### Wazuh Version Upgrades

CyberSentinel is designed for upgrade-safe deployments:

```bash
# 1. Backup
docker run --rm -v cybersentinel-data:/data -v $(pwd)/backups:/backup \
  alpine tar czf /backup/data-$(date +%Y%m%d).tar.gz -C /data .

# 2. Update version in docker-compose.yml
# Change: WAZUH_VERSION: 4.14.0
# To:     WAZUH_VERSION: 4.15.0

# 3. Rebuild and deploy
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

See [README.md](cybersentinel-manager/README.md) for detailed upgrade procedures.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  CyberSentinel Platform                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────┐    ┌──────────────┐   ┌────────────┐ │
│  │ CyberSentinel    │───▶│ SentinelAI   │   │ Fluent Bit │ │
│  │ Manager          │    │ (OpenAI)     │   │ (Forwarder)│ │
│  │ (Wazuh 4.14.x)   │    └──────────────┘   └─────┬──────┘ │
│  └────────┬─────────┘                              │        │
│           │                                         │        │
│           ▼                                         ▼        │
│    alerts.json (Shared Volume)                  Graylog     │
│                                                 (External)   │
└─────────────────────────────────────────────────────────────┘
         ▲
         │
    Wazuh Agents
```

## Production Checklist

- [ ] Configure firewall (ports 1514, 1515, 55000, 514)
- [ ] Set secure passwords in .env
- [ ] Replace template configs with actual files
- [ ] Configure email notifications
- [ ] Add threat intelligence API keys
- [ ] Setup Graylog GELF input
- [ ] Configure SentinelAI with OpenAI key
- [ ] Deploy first agents
- [ ] Setup automated backups
- [ ] Test disaster recovery

## Operations

```bash
# Service Management
docker-compose up -d              # Start
docker-compose down               # Stop
docker-compose restart SERVICE    # Restart
docker-compose logs -f            # View logs

# CyberSentinel Commands
docker-compose exec cybersentinel-manager /var/ossec/bin/wazuh-control status
docker-compose exec cybersentinel-manager /var/ossec/bin/agent_control -l
docker-compose exec cybersentinel-manager /var/ossec/bin/wazuh-logtest

# Backup
docker run --rm -v cybersentinel-data:/data -v $(pwd)/backups:/backup \
  alpine tar czf /backup/data-$(date +%Y%m%d).tar.gz -C /data .
```

## Support

- **Documentation**: See `cybersentinel-manager/README.md`
- **Wazuh Docs**: https://documentation.wazuh.com/current/
- **Docker Docs**: https://docs.docker.com/

## License

CyberSentinel uses open-source components:

- **Wazuh Manager**: GNU GPL v2.0
- **Fluent Bit**: Apache License 2.0
- **CyberSentinel Customizations**: Your organization's license

## Security Notice

This deployment is designed for **authorized security operations**. Use only in:

- SOC/SIEM deployments
- Security monitoring
- Incident response
- Compliance auditing
- Authorized penetration testing
- CTF challenges and security research

---

**CyberSentinel - Production SIEM Platform**

Built on Wazuh Manager 4.14.x | Docker-Native | Production-Ready

For complete documentation, see: [cybersentinel-manager/README.md](cybersentinel-manager/README.md)
