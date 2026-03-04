FROM graylog/graylog:6.3.9

LABEL maintainer="CyberSentinel <support@cybersentinel.ai>" \
      vendor="CyberSentinel" \
      product="CyberSentinel Normalizer" \
      version="6.3.9" \
      description="CyberSentinel Normalizer - Log aggregation and normalization for the CyberSentinel SIEM platform" \
      org.opencontainers.image.title="CyberSentinel Normalizer" \
      org.opencontainers.image.source="https://github.com/cybersentinel-06/CyberSentinel-SIEM-V2"

ARG CYBERSENTINEL_VERSION=6.3.9
ENV CYBERSENTINEL_VERSION=${CYBERSENTINEL_VERSION}

# Set timezone to IST
ENV TZ=Asia/Kolkata

COPY README.md /usr/share/graylog/README.cybersentinel.md

EXPOSE 9000 5555 12201 12201/udp 5140 5140/udp 5044

# Preserve upstream entrypoint and CMD - no overrides
