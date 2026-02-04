# Graylog Integration - Quick Setup Guide

## Stack Status: ✅ DEPLOYED & RUNNING

All services are operational. Complete the Graylog input setup below.

---

## 🚀 Quick Start (3 Steps)

### 1. Access Graylog
```
http://localhost:9000
Username: admin
Password: admin
```

### 2. Create RAW TCP Input
1. Go to: **System → Inputs**
2. Select: **"Raw/Plaintext TCP"**
3. Click: **"Launch new input"**
4. Configure:
   - **Title**: CyberSentinel Wazuh Alerts
   - **Bind address**: 0.0.0.0
   - **Port**: 5555
   - ✅ **Check**: "Store full message"
5. Click: **Save**

### 3. Verify Logs Arriving
1. Go to: **Search**
2. Time range: **Last 15 minutes**
3. Search: `*`
4. Expected: Wazuh alerts in real-time

---

## 📊 Services

| Service | Container | Status | Port |
|---------|-----------|--------|------|
| Wazuh Manager | cybersentinel-manager | ✅ Healthy | 1514, 1515, 55000 |
| CyberSentinel Normalizer | cybersentinel-normalizer | ✅ Healthy | 9000 (UI), 5555 (RAW) |
| MongoDB | mongodb | ✅ Running | 27017 (internal) |
| Elasticsearch | elasticsearch | ✅ Running | 9200 (internal) |
| Fluent Bit | cybersentinel-forwarder | ✅ Running | - |

---

## 🔍 Verification Commands

```bash
# Check all services
docker-compose ps

# Check Wazuh status
docker exec cybersentinel-manager /var/ossec/bin/wazuh-control status

# View live alerts
docker exec cybersentinel-manager tail -f /var/ossec/logs/alerts/alerts.json

# Check CyberSentinel Forwarder
docker logs cybersentinel-forwarder --tail 20

# Check Graylog
curl http://localhost:9000/api
```

---

## 🔐 Change Default Password (REQUIRED FOR PRODUCTION)

```bash
# Generate new password hash
echo -n "YourNewPassword" | sha256sum

# Edit .env file
nano .env

# Update this line:
GRAYLOG_ROOT_PASSWORD_SHA2=<paste_hash_here>

# Restart CyberSentinel Normalizer
docker-compose restart cybersentinel-normalizer
```

---

## 📁 Files Modified

- `docker-compose.yml` - Added Graylog stack, removed SentinelAI
- `fluent-bit/fluent-bit.conf` - Changed to RAW TCP output
- `.env` - Added Graylog variables

---

## 🛠️ Management Commands

```bash
# Start stack
docker-compose up -d

# Stop stack
docker-compose down

# Restart stack
docker-compose restart

# View logs
docker logs <container-name> -f

# Access shell
docker exec -it <container-name> bash
```

---

## 📊 Data Flow

```
Wazuh Agents 
    ↓
CyberSentinel Manager 
    ↓
/var/ossec/logs/alerts/alerts.json
    ↓
CyberSentinel Forwarder (tail + parse JSON)
    ↓
CyberSentinel Normalizer RAW TCP (port 5555)
    ↓
Elasticsearch (storage)
    ↓
CyberSentinel Normalizer Web UI (port 9000)
```

---

## ⚠️ Current Status

✅ All services running
⚠️ Graylog RAW TCP input NOT YET CREATED (follow Step 2 above)
⚠️ Default password still active (change immediately)

---

**Next Action**: Create Graylog RAW TCP input (5555) to enable log ingestion
