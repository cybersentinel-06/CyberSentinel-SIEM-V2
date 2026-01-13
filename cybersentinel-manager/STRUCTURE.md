# CyberSentinel Deployment Structure

## Complete Directory Layout

```
cybersentinel-manager/
├── README.md                           # Complete user guide with upgrade paths
├── DEPLOYMENT.md                       # Step-by-step production deployment guide
├── volumes.md                          # Volume backup and restore procedures
├── STRUCTURE.md                        # This file
│
├── docker-compose.yml                  # Service orchestration (Manager, SentinelAI, Fluent Bit)
├── Dockerfile                          # Custom CyberSentinel Manager image
├── .env.example                        # Environment variable template
├── .gitignore                          # Git ignore rules
│
├── config/                             # CyberSentinel configuration
│   ├── ossec.conf                      # Main SIEM configuration (REPLACE WITH YOURS)
│   │
│   ├── rules/                          # Custom detection rules (REPLACE WITH YOURS)
│   │   ├── local_rules.xml             # Local custom rules
│   │   ├── misp_threat_intel.xml       # MISP threat intelligence rules
│   │   ├── chavecloak_rules.xml        # ChaveCloak integration rules
│   │   ├── alienOTX.xml                # AlienVault OTX rules
│   │   ├── mikrotik_rules.xml          # MikroTik router rules
│   │   ├── hp_router_rules.xml         # HP router rules
│   │   ├── cisco_rules.xml             # Cisco device rules
│   │   ├── 0015-ossec_rules.xml        # OSSEC core rules override
│   │   ├── 0016-wazuh_rules.xml        # Wazuh core rules override
│   │   ├── 0475-IDS_IPS_rules.xml      # IDS/IPS rules (Suricata, Snort)
│   │   └── 0490-virustotal_rules.xml   # VirusTotal integration rules
│   │
│   ├── decoders/                       # Log parsing decoders (REPLACE WITH YOURS)
│   │   ├── local_decoder.xml           # Local custom decoders
│   │   ├── mikrotik_decoders.xml       # MikroTik log decoders
│   │   ├── hp_router_decoders.xml      # HP router log decoders
│   │   └── cisco_decoders.xml          # Cisco log decoders
│   │
│   ├── ruleset/                        # Ruleset overrides (REPLACE WITH YOURS)
│   │   ├── rules/                      # Override default Wazuh rules
│   │   │   ├── 0015-ossec_rules.xml
│   │   │   ├── 0016-wazuh_rules.xml
│   │   │   ├── 0475-suricata_rules.xml
│   │   │   └── 0490-virustotal_rules.xml
│   │   └── decoders/                   # Override default Wazuh decoders
│   │       └── 0005-wazuh_decoders.xml
│   │
│   └── integrations/                   # Threat intelligence scripts (REPLACE WITH YOURS)
│       ├── custom-abuseipdb.py         # AbuseIPDB integration
│       ├── custom-alienvault           # AlienVault OTX wrapper
│       ├── custom-alienvault.py        # AlienVault OTX integration
│       ├── get_malicious.py            # Malicious activity aggregator
│       ├── malware_llm_monitor.py      # LLM-based malware monitor
│       ├── shuffle                     # Shuffle SOAR wrapper
│       └── shuffle.py                  # Shuffle SOAR integration
│
├── sentinelai/                         # SentinelAI AI-powered analysis
│   ├── Dockerfile                      # SentinelAI container image
│   ├── requirements.txt                # Python dependencies
│   └── app/
│       └── sentinelai.py               # Main AI analysis engine
│
└── fluent-bit/                         # Log forwarding to Graylog
    ├── fluent-bit.conf                 # Fluent Bit configuration
    └── timestamp.lua                   # Lua script for timestamp handling
```

## File Count Summary

- **Configuration Files**: 1 (ossec.conf)
- **Rule Files**: 11 (custom + overrides)
- **Decoder Files**: 5 (custom + overrides)
- **Integration Scripts**: 7
- **Docker Files**: 3 (docker-compose.yml, 2x Dockerfile)
- **Documentation Files**: 4 (README, DEPLOYMENT, volumes, STRUCTURE)
- **Total Files**: 50+

## Important Files to Customize

### CRITICAL - Replace These Files

These template files MUST be replaced with your actual configurations:

1. **config/ossec.conf**
   - Main SIEM configuration
   - Update: SMTP settings, API keys, log sources
   - Source: `SERVER/ossec.conf` in your private repo

2. **config/rules/*.xml**
   - All custom detection rules
   - Source: `SERVER/RULES/*.xml` in your private repo

3. **config/decoders/*.xml**
   - Log parsing decoders
   - Source: `SERVER/DECODERS/*.xml` in your private repo

4. **config/integrations/*.py**
   - Threat intelligence integrations
   - Source: `SERVER/INTEGRATIONS/*.py` in your private repo
   - Update: API keys and URLs

### REQUIRED - Configure These Files

5. **.env** (create from .env.example)
   - Environment variables
   - Required: OPENAI_API_KEY, GRAYLOG_HOST, passwords

## Docker Volumes (Persistent Data)

Created automatically by docker-compose:

- **cybersentinel-data**: Agent keys, internal databases
- **cybersentinel-logs**: All SIEM logs and alerts
- **cybersentinel-queue**: Message queues
- **cybersentinel-etc**: Configuration files
- **cybersentinel-integrations**: Integration scripts
- **cybersentinel-api-configuration**: API configuration
- **cybersentinel-agentless**: Agentless monitoring data
- **cybersentinel-wodles**: Wodle modules
- **cybersentinel-stats**: Statistics and metrics
- **shared-alerts**: Shared alerts.json (Manager → SentinelAI/Fluent Bit)
- **sentinelai-data**: AI analysis logs

See `volumes.md` for backup procedures.

## Container Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    CyberSentinel Platform                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Container: cybersentinel-manager                                │
│  ├─ Image: Custom-built from wazuh/wazuh-manager:4.14.0         │
│  ├─ Ports: 1514, 1515, 55000, 514                               │
│  ├─ Volumes: 9 named volumes + 1 shared                         │
│  └─ Function: Core SIEM engine, agent management, rule engine   │
│                                                                   │
│  Container: sentinelai                                           │
│  ├─ Image: Custom Python 3.11                                   │
│  ├─ Volumes: sentinelai-data + shared-alerts (read-only)        │
│  └─ Function: AI-powered alert analysis using OpenAI            │
│                                                                   │
│  Container: fluent-bit                                           │
│  ├─ Image: fluent/fluent-bit:3.0                                │
│  ├─ Volumes: fluent-bit config + shared-alerts (read-only)      │
│  └─ Function: Forward alerts to Graylog via GELF TCP            │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘

External Dependencies:
  - Graylog (log aggregation and visualization) - Optional
  - OpenAI API (SentinelAI analysis) - Optional
  - Wazuh Agents (endpoints sending logs) - Required for production use
```

## Deployment Workflow

1. **Preparation**
   ```bash
   cp .env.example .env
   nano .env  # Configure passwords and API keys
   ```

2. **Customize Configurations**
   ```bash
   # Replace template files with your actual files
   # OR edit templates directly
   nano config/ossec.conf
   ```

3. **Build**
   ```bash
   docker-compose build
   ```

4. **Deploy**
   ```bash
   docker-compose up -d
   ```

5. **Verify**
   ```bash
   docker-compose ps
   docker-compose logs -f
   ```

## Upgrade Path

### Wazuh 4.14 → 4.15 (Future)

1. Backup all volumes
2. Update `WAZUH_VERSION` in docker-compose.yml or .env
3. Rebuild: `docker-compose build --no-cache`
4. Deploy: `docker-compose up -d`
5. Verify agents reconnect

See README.md "Upgrading" section for detailed steps.

## Network Ports

| Port | Protocol | Service | Firewall |
|------|----------|---------|----------|
| 1514 | TCP | Agent events | Allow from agent network |
| 1515 | TCP | Agent registration | Allow from agent network |
| 55000 | TCP | CyberSentinel API | Restrict to admin IPs |
| 514 | UDP/TCP | Syslog | Allow from log sources |
| 12201 | TCP | Graylog GELF | Outbound to Graylog |

## Quick Commands

```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# Logs
docker-compose logs -f cybersentinel-manager

# Status
docker-compose exec cybersentinel-manager /var/ossec/bin/wazuh-control status

# List agents
docker-compose exec cybersentinel-manager /var/ossec/bin/agent_control -l

# Test rules
docker-compose exec cybersentinel-manager /var/ossec/bin/wazuh-logtest

# Backup
docker run --rm -v cybersentinel-data:/data -v $(pwd)/backups:/backup \
  alpine tar czf /backup/data-$(date +%Y%m%d).tar.gz -C /data .
```

## Next Steps

1. Read `README.md` for complete documentation
2. Follow `DEPLOYMENT.md` for production setup
3. Configure `.env` with your values
4. Replace template configs with actual files
5. Build and deploy
6. Connect agents
7. Configure Graylog input
8. Setup backups (see volumes.md)

## Support Resources

- **README.md**: Complete user guide
- **DEPLOYMENT.md**: Production deployment procedures
- **volumes.md**: Backup and restore procedures
- **Wazuh Docs**: https://documentation.wazuh.com/current/
- **Docker Docs**: https://docs.docker.com/

---

**CyberSentinel - Production SIEM Platform**
Built on Wazuh Manager 4.14.x | Docker-Native | Production-Ready
