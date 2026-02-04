FROM fluent/fluent-bit:3.0

LABEL maintainer="CyberSentinel <support@cybersentinel.ai>" \
      vendor="CyberSentinel" \
      product="CyberSentinel Forwarder" \
      version="1.0" \
      description="CyberSentinel Forwarder - Fluent Bit-based log forwarding for the CyberSentinel SIEM platform"

COPY fluent-bit.conf /fluent-bit/etc/fluent-bit.conf
COPY parsers.conf /fluent-bit/etc/parsers.conf
COPY timestamp.lua /fluent-bit/etc/timestamp.lua

EXPOSE 2020

CMD ["/fluent-bit/bin/fluent-bit", "-c", "/fluent-bit/etc/fluent-bit.conf", "-R", "/fluent-bit/etc/parsers.conf"]
