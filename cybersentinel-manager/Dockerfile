# CyberSentinel Manager Dockerfile
# Based on official Wazuh Manager 4.14.x
# All custom configs, rules, decoders, and integrations are baked into the image.
#
# Build locally:
#   1. Run: GITHUB_TOKEN='ghp_xxx' ./fetch-configs.sh
#   2. Run: docker build -t ghcr.io/cybersentinel-06/cybersentinel-siem/manager:4.14.0 .
#
# CI build (GitHub Actions):
#   Configs are fetched automatically during the workflow.

ARG WAZUH_VERSION=4.14.0
FROM wazuh/wazuh-manager:${WAZUH_VERSION}

LABEL maintainer="CyberSentinel Security Team"
LABEL description="CyberSentinel Manager - Production SIEM Platform"
LABEL version="1.0.0"
LABEL org.opencontainers.image.source="https://github.com/cybersentinel-06/CyberSentinel-SIEM-V2"
LABEL org.opencontainers.image.title="CyberSentinel Manager"
LABEL org.opencontainers.image.description="CyberSentinel SIEM Manager with baked-in rules, decoders, and integrations"

# ========================================
# Build-time Configuration
# ========================================
USER root

# Set timezone to IST
ENV TZ=Asia/Kolkata
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ========================================
# Install System Utilities
# ========================================
RUN (microdnf install -y nano 2>/dev/null \
    || yum install -y nano 2>/dev/null \
    || dnf install -y nano 2>/dev/null \
    || echo "WARNING: Could not install nano") \
    && (microdnf clean all 2>/dev/null || yum clean all 2>/dev/null || dnf clean all 2>/dev/null || true)

# ========================================
# Bake CyberSentinel Control Wrapper
# ========================================
COPY cybersentinel-control /usr/local/bin/cybersentinel-control
RUN chmod 755 /usr/local/bin/cybersentinel-control \
    && chown root:root /usr/local/bin/cybersentinel-control

# ========================================
# Bake Main Configuration
# ========================================
# ossec.conf — the core SIEM configuration
COPY config/ossec.conf /var/ossec/etc/ossec.conf
RUN chown root:wazuh /var/ossec/etc/ossec.conf \
    && chmod 640 /var/ossec/etc/ossec.conf

# ========================================
# Bake Custom Rules (/var/ossec/etc/rules/)
# ========================================
# Copy all custom rule XML files into etc/rules/
COPY config/rules/ /tmp/custom-rules/
RUN if ls /tmp/custom-rules/*.xml 1>/dev/null 2>&1; then \
        cp /tmp/custom-rules/*.xml /var/ossec/etc/rules/ \
        && chown root:wazuh /var/ossec/etc/rules/*.xml \
        && chmod 640 /var/ossec/etc/rules/*.xml; \
    fi \
    && rm -rf /tmp/custom-rules

# ========================================
# Bake Ruleset Overrides (/var/ossec/ruleset/rules/)
# ========================================
# These override the default Wazuh rules
COPY config/ruleset/rules/ /tmp/ruleset-rules/
RUN if ls /tmp/ruleset-rules/*.xml 1>/dev/null 2>&1; then \
        cp /tmp/ruleset-rules/*.xml /var/ossec/ruleset/rules/ \
        # Special case: 0475-IDS_IPS_rules.xml replaces 0475-suricata_rules.xml
        && if [ -f /var/ossec/ruleset/rules/0475-IDS_IPS_rules.xml ]; then \
            mv /var/ossec/ruleset/rules/0475-IDS_IPS_rules.xml /var/ossec/ruleset/rules/0475-suricata_rules.xml; \
        fi \
        && chown root:wazuh /var/ossec/ruleset/rules/*.xml \
        && chmod 640 /var/ossec/ruleset/rules/*.xml; \
    fi \
    && rm -rf /tmp/ruleset-rules

# ========================================
# Bake Custom Decoders (/var/ossec/etc/decoders/)
# ========================================
COPY config/decoders/ /tmp/custom-decoders/
RUN if ls /tmp/custom-decoders/*.xml 1>/dev/null 2>&1; then \
        # 0005-wazuh_decoders.xml goes to ruleset/decoders/ (override)
        if [ -f /tmp/custom-decoders/0005-wazuh_decoders.xml ]; then \
            cp /tmp/custom-decoders/0005-wazuh_decoders.xml /var/ossec/ruleset/decoders/0005-wazuh_decoders.xml \
            && chown root:wazuh /var/ossec/ruleset/decoders/0005-wazuh_decoders.xml \
            && chmod 640 /var/ossec/ruleset/decoders/0005-wazuh_decoders.xml; \
        fi \
        # All other decoders go to etc/decoders/
        && for f in /tmp/custom-decoders/*.xml; do \
            fname=$(basename "$f"); \
            if [ "$fname" != "0005-wazuh_decoders.xml" ]; then \
                cp "$f" "/var/ossec/etc/decoders/$fname"; \
            fi; \
        done \
        && chown root:wazuh /var/ossec/etc/decoders/*.xml \
        && chmod 640 /var/ossec/etc/decoders/*.xml; \
    fi \
    && rm -rf /tmp/custom-decoders

# ========================================
# Bake Integration Scripts (/var/ossec/integrations/)
# ========================================
COPY config/integrations/ /tmp/custom-integrations/
RUN if ls /tmp/custom-integrations/* 1>/dev/null 2>&1; then \
        cp /tmp/custom-integrations/* /var/ossec/integrations/ \
        && chown root:wazuh /var/ossec/integrations/custom-* /var/ossec/integrations/get_malicious* 2>/dev/null \
        && chmod 750 /var/ossec/integrations/custom-* /var/ossec/integrations/get_malicious* 2>/dev/null; \
    fi \
    && rm -rf /tmp/custom-integrations

# ========================================
# Runtime Directory Setup
# ========================================
RUN mkdir -p /var/ossec/logs/{alerts,archives,firewall,wazuh,api,cluster} \
    && chown -R wazuh:wazuh /var/ossec/logs \
    && chmod -R 770 /var/ossec/logs

# ========================================
# Health Check
# ========================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD /var/ossec/bin/wazuh-control status | grep -q 'is running' || exit 1

# ========================================
# Expose Ports
# ========================================
EXPOSE 1514/tcp 1515/tcp 55000/tcp 514/udp 514/tcp
