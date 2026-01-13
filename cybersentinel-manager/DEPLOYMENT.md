# CyberSentinel Production Deployment Guide

This guide provides step-by-step instructions for deploying CyberSentinel in a production environment.

## Pre-Deployment Checklist

- [ ] Server meets minimum requirements (8GB RAM, 4 CPU cores, 100GB disk)
- [ ] Docker and Docker Compose installed
- [ ] Network firewall configured
- [ ] External Graylog instance available (optional)
- [ ] API keys obtained (OpenAI, VirusTotal, etc.)
- [ ] Custom rules and configurations prepared
- [ ] Backup strategy defined

## Deployment Steps

### 1. Server Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl git vim htop

# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Logout and login for group changes to take effect
exit
```

### 2. Deploy CyberSentinel

```bash
# Create deployment directory
sudo mkdir -p /opt/cybersentinel
cd /opt/cybersentinel

# Clone repository (or copy files)
git clone <your-repo> .
cd cybersentinel-manager

# OR: Copy deployment files
# scp -r cybersentinel-manager/ user@server:/opt/cybersentinel/
```

### 3. Configure Environment

```bash
# Copy environment template
cp .env.example .env

# Edit configuration
nano .env
```

**Required values**:
```env
INDEXER_PASSWORD=YourSecurePassword123!
OPENAI_API_KEY=sk-your-openai-api-key
GRAYLOG_HOST=graylog.yourdomain.com
GRAYLOG_PORT=12201
```

```bash
# Secure environment file
chmod 600 .env
chown root:root .env
```

### 4. Customize Configuration Files

#### Option A: Use Your Private Repository Files

```bash
# Download from your private GitHub repository
# Replace the placeholder files in config/ with your actual files:

# Main configuration
curl -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/SERVER/ossec.conf \
  -o config/ossec.conf

# Rules (repeat for each rule file)
curl -H "Authorization: token YOUR_GITHUB_TOKEN" \
  https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/SERVER/RULES/local_rules.xml \
  -o config/rules/local_rules.xml

# Decoders (repeat for each decoder)
# Integrations (repeat for each integration script)
```

#### Option B: Use Template Files

The template files will work but provide minimal detection. Customize them:

```bash
# Edit main configuration
nano config/ossec.conf
# Update: SMTP settings, API keys, log sources

# Edit custom rules
nano config/rules/local_rules.xml
# Add your organization-specific detection rules

# Edit integration scripts
nano config/integrations/custom-alienvault.py
# Add your actual API keys
```

### 5. Configure Firewall

```bash
# Allow required ports
sudo ufw allow 22/tcp      # SSH (if using UFW)
sudo ufw allow 1514/tcp    # Agent communication
sudo ufw allow 1515/tcp    # Agent registration
sudo ufw allow 55000/tcp   # CyberSentinel API
sudo ufw allow 514/udp     # Syslog UDP
sudo ufw allow 514/tcp     # Syslog TCP

# Enable firewall
sudo ufw enable
```

### 6. Build and Deploy

```bash
# Build custom images
docker-compose build

# Start services in detached mode
docker-compose up -d

# Monitor startup
docker-compose logs -f
```

### 7. Verify Deployment

```bash
# Check service status
docker-compose ps

# Should show all services as "Up":
# - cybersentinel-manager
# - sentinelai
# - fluent-bit

# Verify CyberSentinel Manager
docker-compose exec cybersentinel-manager /var/ossec/bin/wazuh-control status

# Check logs for errors
docker-compose logs cybersentinel-manager | grep -i error
docker-compose logs sentinelai | grep -i error
docker-compose logs fluent-bit | grep -i error
```

### 8. Test Alert Generation

```bash
# Access log test tool
docker-compose exec cybersentinel-manager /var/ossec/bin/wazuh-logtest

# Test sample log (SSH authentication failure)
# Paste this log and press Ctrl+D:
# Dec 25 20:45:02 server sshd[12345]: Failed password for invalid user admin from 192.168.1.100 port 12345 ssh2

# Verify alert appears in alerts.json
docker-compose exec cybersentinel-manager tail -f /var/ossec/logs/alerts/alerts.json
```

### 9. Connect First Agent

```bash
# On agent machine (example: Ubuntu)
# Download Wazuh agent
curl -so wazuh-agent.deb https://packages.wazuh.com/4.x/apt/pool/main/w/wazuh-agent/wazuh-agent_4.14.0-1_amd64.deb

# Install with CyberSentinel Manager IP
sudo WAZUH_MANAGER='YOUR_CYBERSENTINEL_IP' \
     WAZUH_AGENT_NAME='web-server-01' \
     dpkg -i wazuh-agent.deb

# Start agent
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent

# Verify on manager
docker-compose exec cybersentinel-manager /var/ossec/bin/agent_control -l
```

### 10. Configure Graylog (Optional)

If using Graylog for centralized logging:

```bash
# 1. In Graylog web interface:
#    System → Inputs → Select "GELF TCP" → Launch new input
#    Port: 12201
#    Bind address: 0.0.0.0

# 2. Verify Fluent Bit connectivity
docker-compose exec fluent-bit nc -zv ${GRAYLOG_HOST} ${GRAYLOG_PORT}

# 3. Check logs in Graylog
#    Search → Last 5 minutes → source:CyberSentinel
```

### 11. Setup Automated Backups

```bash
# Create backup script
sudo nano /opt/cybersentinel/backup-cybersentinel.sh
```

Add content from `volumes.md` backup script, then:

```bash
# Make executable
sudo chmod +x /opt/cybersentinel/backup-cybersentinel.sh

# Test backup
sudo /opt/cybersentinel/backup-cybersentinel.sh

# Setup daily cron job
sudo crontab -e
# Add:
# 0 2 * * * /opt/cybersentinel/backup-cybersentinel.sh >> /var/log/cybersentinel-backup.log 2>&1
```

### 12. Configure Monitoring

```bash
# Setup health check monitoring (example: using systemd)
sudo nano /etc/systemd/system/cybersentinel-health.service
```

```ini
[Unit]
Description=CyberSentinel Health Check
After=docker.service

[Service]
Type=oneshot
WorkingDirectory=/opt/cybersentinel/cybersentinel-manager
ExecStart=/usr/local/bin/docker-compose ps
User=root

[Install]
WantedBy=multi-user.target
```

```bash
# Enable health check timer
sudo nano /etc/systemd/system/cybersentinel-health.timer
```

```ini
[Unit]
Description=CyberSentinel Health Check Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

```bash
# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable cybersentinel-health.timer
sudo systemctl start cybersentinel-health.timer
```

## Post-Deployment

### 1. Security Hardening

```bash
# Restrict API access to specific IPs
# Edit docker-compose.yml, add:
# ports:
#   - "127.0.0.1:55000:55000"

# Enable SELinux (RHEL/CentOS)
sudo setenforce 1

# Or AppArmor (Ubuntu/Debian)
sudo systemctl enable apparmor
```

### 2. Performance Tuning

```bash
# Increase file descriptor limits
sudo nano /etc/security/limits.conf
# Add:
# * soft nofile 65536
# * hard nofile 65536

# Increase Docker storage driver performance
# Edit /etc/docker/daemon.json
sudo nano /etc/docker/daemon.json
```

```json
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

```bash
sudo systemctl restart docker
docker-compose up -d
```

### 3. Documentation

```bash
# Document your deployment
sudo nano /opt/cybersentinel/DEPLOYMENT_NOTES.md
```

Include:
- Server IP addresses
- Agent list and purposes
- Custom rule IDs used
- Integration API keys location
- Escalation procedures
- Backup locations

### 4. Test Disaster Recovery

```bash
# Simulate failure and recovery
docker-compose down
# Wait 5 minutes
docker-compose up -d

# Verify:
# - Agents reconnect
# - Alerts generate
# - Logs forward to Graylog
```

## Common Issues

### Issue: Services fail to start

**Solution**:
```bash
# Check disk space
df -h

# Check Docker logs
journalctl -u docker -n 50

# Check permissions
ls -la /opt/cybersentinel/cybersentinel-manager/
```

### Issue: Agents won't connect

**Solution**:
```bash
# Check firewall
sudo netstat -tulpn | grep 1514
sudo ufw status

# Check manager logs
docker-compose logs cybersentinel-manager | grep agent

# Verify agent configuration
# On agent: cat /var/ossec/etc/ossec.conf
```

### Issue: High CPU/Memory usage

**Solution**:
```bash
# Add resource limits to docker-compose.yml
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 8G

# Restart services
docker-compose up -d
```

## Maintenance Schedule

### Daily
- Monitor disk usage
- Check service status
- Review critical alerts

### Weekly
- Review backup logs
- Check agent status
- Update threat intelligence feeds

### Monthly
- Review and tune rules
- Analyze false positives
- Update documentation
- Test disaster recovery

### Quarterly
- Rotate API keys
- Review user access
- Update Docker images
- Security audit

## Support

For production support:
- **Documentation**: `/opt/cybersentinel/cybersentinel-manager/README.md`
- **Logs**: `docker-compose logs`
- **Wazuh Docs**: https://documentation.wazuh.com/current/

---

**Deployment Complete!**

Your CyberSentinel Manager is now running in production mode.

Next steps:
1. Connect your agents
2. Configure threat intelligence integrations
3. Customize detection rules
4. Setup alerting workflows
5. Train your SOC team
