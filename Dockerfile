##= BUILDER =##
FROM 84codes/crystal:latest-debian-12 AS builder

WORKDIR /cyclonedx-cr

# Install build dependencies for the libraries Crystal links against
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential pkg-config \
    libyaml-dev libxml2-dev libicu-dev libpcre2-dev libgc-dev liblzma-dev zlib1g-dev && \
    rm -rf /var/lib/apt/lists/*

# Install shards first for better layer cache
COPY shard.yml shard.lock ./
RUN shards install --production

# Copy the rest and build (no --static)
COPY . .
RUN shards build --release --no-debug --production && \
    strip bin/cyclonedx-cr

##= RUNNER =##
# Use Debian 12 runtime to match builder's ABI (avoids ICU/glibc mismatches)
FROM debian:13-slim

# Install runtime libraries required by the linked binary
RUN apt-get update && apt-get install -y --no-install-recommends \
    libyaml-0-2 \
    libxml2 \
    libicu72 \
    libpcre2-8-0 \
    libgc1 \
    liblzma5 \
    zlib1g \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /cyclonedx-cr/bin/cyclonedx-cr /usr/local/bin/cyclonedx-cr

# Run as non-root
# USER 2:2

# Default command
CMD ["cyclonedx-cr"]
