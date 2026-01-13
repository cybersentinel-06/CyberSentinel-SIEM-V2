FROM fluent/fluent-bit:3.0

# Copy Fluent Bit configuration directly
COPY fluent-bit.conf /fluent-bit/etc/fluent-bit.conf
COPY timestamp.lua /fluent-bit/etc/timestamp.lua

# Expose metrics port (optional)
EXPOSE 2020

# Start Fluent Bit
CMD ["fluent-bit", "-c", "/fluent-bit/etc/fluent-bit.conf"]
