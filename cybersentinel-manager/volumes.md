# CyberSentinel Docker Volumes Documentation

This document describes all Docker volumes used by CyberSentinel for persistent data storage.

## Overview

CyberSentinel uses Docker named volumes to ensure data persistence across container restarts, updates, and upgrades. All volumes are defined in `docker-compose.yml`.

## Volume List

### CyberSentinel Manager Volumes

| Volume Name | Container Path | Purpose | Backup Priority | Size Estimate |
|-------------|---------------|---------|----------------|---------------|
| `cybersentinel-data` | `/var/ossec/data` | Agent keys, internal databases | **CRITICAL** | 1-10 GB |
| `cybersentinel-logs` | `/var/ossec/logs` | All SIEM logs, alerts, archives | **CRITICAL** | 10-100+ GB |
| `cybersentinel-queue` | `/var/ossec/queue` | Message queues, temporary data | Medium | 1-5 GB |
| `cybersentinel-etc` | `/var/ossec/etc` | Configuration files | **CRITICAL** | 100 MB |
| `cybersentinel-integrations` | `/var/ossec/integrations` | Integration scripts | High | 10 MB |
| `cybersentinel-api-configuration` | `/var/ossec/api/configuration` | API configuration | High | 10 MB |
| `cybersentinel-agentless` | `/var/ossec/agentless` | Agentless monitoring data | Medium | 100 MB |
| `cybersentinel-wodles` | `/var/ossec/wodles` | Wodle modules and data | Medium | 500 MB |
| `cybersentinel-stats` | `/var/ossec/stats` | Statistics and metrics | Low | 100 MB |

### Shared Volumes

| Volume Name | Container Path | Purpose | Backup Priority | Size Estimate |
|-------------|---------------|---------|----------------|---------------|
| `shared-alerts` | `/var/ossec/logs/alerts` (Manager)<br>`/alerts` (SentinelAI, Fluent Bit) | Shared alerts.json for real-time processing | High | 1-10 GB |

### SentinelAI Volumes

| Volume Name | Container Path | Purpose | Backup Priority | Size Estimate |
|-------------|---------------|---------|----------------|---------------|
| `sentinelai-data` | `/app/data` | AI analysis logs, malware summaries | High | 1-5 GB |

## Volume Locations

By default, Docker stores named volumes at:
```
/var/lib/docker/volumes/<volume-name>/_data
```

To find the exact location of a volume:
```bash
docker volume inspect <volume-name>
```

## Backup Strategy

### Critical Volumes (Daily Backup Required)

1. **cybersentinel-data**
   - Contains agent keys and internal databases
   - Loss = loss of all agent registrations
   - Backup command:
     ```bash
     docker run --rm \
       -v cybersentinel-data:/data \
       -v $(pwd)/backups:/backup \
       alpine tar czf /backup/cybersentinel-data-$(date +%Y%m%d).tar.gz -C /data .
     ```

2. **cybersentinel-logs**
   - Contains all security events and alerts
   - Critical for forensic analysis and compliance
   - Backup command:
     ```bash
     docker run --rm \
       -v cybersentinel-logs:/logs \
       -v $(pwd)/backups:/backup \
       alpine tar czf /backup/cybersentinel-logs-$(date +%Y%m%d).tar.gz -C /logs .
     ```

3. **cybersentinel-etc**
   - Contains all configuration files
   - Loss = need to reconfigure from scratch
   - Backup command:
     ```bash
     docker run --rm \
       -v cybersentinel-etc:/etc \
       -v $(pwd)/backups:/backup \
       alpine tar czf /backup/cybersentinel-etc-$(date +%Y%m%d).tar.gz -C /etc .
     ```

### High Priority Volumes (Weekly Backup)

- `cybersentinel-integrations`
- `cybersentinel-api-configuration`
- `shared-alerts`
- `sentinelai-data`

### Automated Backup Script

Save as `backup-cybersentinel.sh`:

```bash
#!/bin/bash
# CyberSentinel Backup Script

BACKUP_DIR="/opt/backups/cybersentinel"
DATE=$(date +%Y%m%d-%H%M%S)
RETENTION_DAYS=30

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup critical volumes
for volume in cybersentinel-data cybersentinel-logs cybersentinel-etc; do
    echo "Backing up $volume..."
    docker run --rm \
        -v $volume:/source \
        -v $BACKUP_DIR:/backup \
        alpine tar czf /backup/${volume}-${DATE}.tar.gz -C /source .
done

# Cleanup old backups
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $BACKUP_DIR"
```

## Restore Procedure

### Restore a Volume

1. Stop the services:
   ```bash
   cd /path/to/cybersentinel-manager
   docker-compose down
   ```

2. Restore the volume:
   ```bash
   docker run --rm \
     -v cybersentinel-data:/data \
     -v $(pwd)/backups:/backup \
     alpine sh -c "cd /data && tar xzf /backup/cybersentinel-data-YYYYMMDD.tar.gz"
   ```

3. Start the services:
   ```bash
   docker-compose up -d
   ```

### Full Disaster Recovery

1. Install Docker and Docker Compose on new server
2. Clone repository or copy deployment files
3. Restore all volumes from backup
4. Update .env with correct configuration
5. Start services:
   ```bash
   docker-compose up -d
   ```

## Volume Maintenance

### Check Volume Usage

```bash
# List all CyberSentinel volumes with sizes
docker system df -v | grep cybersentinel
```

### Clean Up Unused Volumes

```bash
# WARNING: This will delete ALL unused volumes
docker volume prune

# Safer: List unused volumes first
docker volume ls -qf dangling=true
```

### Resize Volumes

Docker volumes automatically grow as needed (limited by disk space). To move to larger disk:

1. Stop services
2. Backup volumes
3. Create new volumes on new disk
4. Restore backups to new volumes
5. Update docker-compose.yml with new volume names
6. Start services

## Monitoring Volume Growth

### Setup Monitoring Alert

Create `/etc/cron.daily/check-cybersentinel-volumes`:

```bash
#!/bin/bash

THRESHOLD=80  # Alert at 80% disk usage

USAGE=$(df -h /var/lib/docker | awk 'NR==2 {print $5}' | sed 's/%//')

if [ "$USAGE" -gt "$THRESHOLD" ]; then
    echo "WARNING: Docker volume disk usage at ${USAGE}%"
    # Send alert (email, Slack, etc.)
fi
```

## Production Recommendations

1. **Separate Disk for Volumes**
   - Mount dedicated disk at `/var/lib/docker`
   - SSD recommended for performance
   - Size: 500GB+ for production SIEM

2. **Log Rotation**
   - Configure log rotation in ossec.conf
   - Archive old logs to object storage (S3, MinIO)
   - Default retention: 90 days

3. **Monitoring**
   - Monitor disk usage with Prometheus/Grafana
   - Alert on volume growth trends
   - Alert on backup failures

4. **High Availability**
   - Use network storage (NFS, GlusterFS) for multi-node
   - Or implement volume replication
   - Test restore procedures quarterly

## Troubleshooting

### Volume Permission Issues

```bash
# Fix ownership inside container
docker-compose exec cybersentinel-manager chown -R wazuh:wazuh /var/ossec/logs
```

### Volume Not Mounting

```bash
# Check volume exists
docker volume ls | grep cybersentinel

# Inspect volume
docker volume inspect cybersentinel-data

# Recreate volume
docker-compose down
docker volume rm cybersentinel-data
docker-compose up -d
```

### Volume Corruption

1. Stop services
2. Restore from latest backup
3. Check disk health: `smartctl -a /dev/sdX`
4. Consider moving to new disk

## References

- Docker Volumes Documentation: https://docs.docker.com/storage/volumes/
- CyberSentinel Architecture: README.md
- Wazuh Data Storage: https://documentation.wazuh.com/current/user-manual/manager/
