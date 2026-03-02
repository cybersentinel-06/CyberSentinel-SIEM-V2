# CyberSentinel Normalizer

This is a branded wrapper image for Graylog 6.1, used as the log normalization component in the CyberSentinel SIEM platform.

## Upstream Source

This image is based on: `graylog/graylog:6.1`

## CyberSentinel Integration

- Connects to MongoDB for metadata storage
- Connects to Elasticsearch for log indexing
- Accepts logs from CyberSentinel Forwarder via RAW TCP (port 5555)
- Provides web UI on port 9000

## Image Details

- Base: Graylog 6.1
- Purpose: Log aggregation and normalization
- Ports: 9000 (UI), 5555 (RAW TCP), 12201 (GELF), 5140 (Syslog), 5044 (Beats)

## Support

For CyberSentinel support: support@cybersentinel.ai
