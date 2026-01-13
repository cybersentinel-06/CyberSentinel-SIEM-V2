# CyberSentinel Manager Dockerfile
# Based on official Wazuh Manager 4.14.x
# Production-ready, upgrade-safe Docker deployment

ARG WAZUH_VERSION=4.14.0
FROM wazuh/wazuh-manager:${WAZUH_VERSION}

LABEL maintainer="CyberSentinel Security Team"
LABEL description="CyberSentinel Manager - Production SIEM Platform"
LABEL version="1.0.0"
LABEL wazuh.version="${WAZUH_VERSION}"

# ========================================
# Build-time Configuration
# ========================================

# Switch to root for configuration
USER root

# ========================================
# Install System Utilities (Build-time Only)
# ========================================
# Install nano text editor for runtime configuration management
# Uses fallback chain to handle different base image package managers
RUN (microdnf install -y nano 2>/dev/null \
    || yum install -y nano 2>/dev/null \
    || dnf install -y nano 2>/dev/null \
    || echo "WARNING: Could not install nano - no compatible package manager found") \
    && (microdnf clean all 2>/dev/null || yum clean all 2>/dev/null || dnf clean all 2>/dev/null || true)

# ========================================
# Copy Custom Configuration Files
# ========================================

# Main OSSEC configuration
#COPY --chown=root:wazuh --chmod=640 config/ossec.conf /var/ossec/etc/ossec.conf

# Custom Rules (applied in /etc/rules/)
#COPY --chown=root:wazuh --chmod=640 config/rules/local_rules.xml /var/ossec/etc/rules/local_rules.xml
#COPY --chown=root:wazuh --chmod=640 config/rules/misp_threat_intel.xml /var/ossec/etc/rules/misp_threat_intel.xml
#COPY --chown=root:wazuh --chmod=640 config/rules/chavecloak_rules.xml /var/ossec/etc/rules/chavecloak_rules.xml
#COPY --chown=root:wazuh --chmod=640 config/rules/alienOTX.xml /var/ossec/etc/rules/alienOTX.xml
#COPY --chown=root:wazuh --chmod=640 config/rules/mikrotik_rules.xml /var/ossec/etc/rules/mikrotik_rules.xml
#COPY --chown=root:wazuh --chmod=640 config/rules/hp_router_rules.xml /var/ossec/etc/rules/hp_router_rules.xml
#COPY --chown=root:wazuh --chmod=640 config/rules/cisco_rules.xml /var/ossec/etc/rules/cisco_rules.xml
# NOTE: Comment out placeholder override files - uncomment only if you have actual override content
# COPY --chown=root:wazuh --chmod=640 config/rules/0015-ossec_rules.xml /var/ossec/etc/rules/0015-ossec_rules.xml
# COPY --chown=root:wazuh --chmod=640 config/rules/0016-wazuh_rules.xml /var/ossec/etc/rules/0016-wazuh_rules.xml
# COPY --chown=root:wazuh --chmod=640 config/rules/0475-IDS_IPS_rules.xml /var/ossec/etc/rules/0475-IDS_IPS_rules.xml
# COPY --chown=root:wazuh --chmod=640 config/rules/0490-virustotal_rules.xml /var/ossec/etc/rules/0490-virustotal_rules.xml

# Custom Decoders
#COPY --chown=root:wazuh --chmod=640 config/decoders/local_decoder.xml /var/ossec/etc/decoders/local_decoder.xml
#COPY --chown=root:wazuh --chmod=640 config/decoders/mikrotik_decoders.xml /var/ossec/etc/decoders/mikrotik_decoders.xml
#COPY --chown=root:wazuh --chmod=640 config/decoders/hp_router_decoders.xml /var/ossec/etc/decoders/hp_router_decoders.xml
#COPY --chown=root:wazuh --chmod=640 config/decoders/cisco_decoders.xml /var/ossec/etc/decoders/cisco_decoders.xml

# Ruleset Overrides (replace default Wazuh rules)
# NOTE: Only copy these if you have actual override files
# Comment out these lines if using template/placeholder files
# COPY --chown=root:wazuh --chmod=640 config/ruleset/rules/0016-wazuh_rules.xml /var/ossec/ruleset/rules/0016-wazuh_rules.xml
# COPY --chown=root:wazuh --chmod=640 config/ruleset/rules/0015-ossec_rules.xml /var/ossec/ruleset/rules/0015-ossec_rules.xml
# COPY --chown=root:wazuh --chmod=640 config/ruleset/rules/0475-suricata_rules.xml /var/ossec/ruleset/rules/0475-suricata_rules.xml
# COPY --chown=root:wazuh --chmod=640 config/ruleset/rules/0490-virustotal_rules.xml /var/ossec/ruleset/rules/0490-virustotal_rules.xml

# Ruleset Decoder Overrides
# COPY --chown=root:wazuh --chmod=640 config/ruleset/decoders/0005-wazuh_decoders.xml /var/ossec/ruleset/decoders/0005-wazuh_decoders.xml

# Integration Scripts
#COPY --chown=root:wazuh --chmod=750 config/integrations/custom-abuseipdb.py /var/ossec/integrations/custom-abuseipdb.py
#COPY --chown=root:wazuh --chmod=750 config/integrations/custom-alienvault /var/ossec/integrations/custom-alienvault
#COPY --chown=root:wazuh --chmod=750 config/integrations/custom-alienvault.py /var/ossec/integrations/custom-alienvault.py
#COPY --chown=root:wazuh --chmod=750 config/integrations/get_malicious.py /var/ossec/integrations/get_malicious.py
#COPY --chown=root:wazuh --chmod=750 config/integrations/malware_llm_monitor.py /var/ossec/integrations/malware_llm_monitor.py
# NOTE: Shuffle integration files not present - uncomment if you add them later
# COPY --chown=root:wazuh --chmod=750 config/integrations/shuffle /var/ossec/integrations/shuffle
# COPY --chown=root:wazuh --chmod=750 config/integrations/shuffle.py /var/ossec/integrations/shuffle.py

# ========================================
# Runtime Configuration
# ========================================

# Ensure correct ownership of critical directories
#RUN chown -R wazuh:wazuh /var/ossec/logs \
#    && chown -R wazuh:wazuh /var/ossec/queue \
#    && chown -R root:wazuh /var/ossec/etc \
#    && chown -R root:wazuh /var/ossec/integrations

# Create alerts directory with proper permissions
RUN mkdir -p /var/ossec/logs/alerts \
    && chown wazuh:wazuh /var/ossec/logs/alerts \
    && chmod 750 /var/ossec/logs/alerts

# ========================================
# Health Check
# ========================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD /var/ossec/bin/wazuh-control status | grep -q 'is running' || exit 1

# ========================================
# Entrypoint & Command
# ========================================
# Use default Wazuh entrypoint
# ENTRYPOINT ["/entrypoint.sh"]

# Expose required ports
EXPOSE 1514/tcp 1515/tcp 55000/tcp 514/udp 514/tcp

# Return to wazuh user (if the base image supports it)
# USER wazuh

# Note: The official wazuh-manager image runs as root by default
# This is required for proper operation of OSSEC components
