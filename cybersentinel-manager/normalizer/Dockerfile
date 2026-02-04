FROM graylog/graylog:6.1

LABEL maintainer="CyberSentinel <support@cybersentinel.ai>" \
      vendor="CyberSentinel" \
      product="CyberSentinel Normalizer" \
      version="6.1" \
      description="CyberSentinel Normalizer - Graylog-based log aggregation and normalization for the CyberSentinel SIEM platform"

ARG CYBERSENTINEL_VERSION=6.1
ENV CYBERSENTINEL_VERSION=${CYBERSENTINEL_VERSION}

COPY README.md /usr/share/graylog/README.cybersentinel.md

EXPOSE 9000 5555 12201 12201/udp 5140 5140/udp 5044

# Preserve upstream entrypoint and CMD - no overrides
