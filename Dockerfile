##= BUILDER =##
FROM crystallang/crystal:1.20.0 AS builder

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
# Match builder's ABI (Ubuntu 24.04) to avoid ICU/glibc mismatches
FROM ubuntu:24.04

# Install runtime libraries required by the linked binary
RUN apt-get update && apt-get install -y --no-install-recommends \
    libyaml-0-2 \
    libxml2 \
    libicu74 \
    libpcre2-8-0 \
    libgc1 \
    liblzma5 \
    zlib1g \
    ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /cyclonedx-cr/bin/cyclonedx-cr /usr/local/bin/cyclonedx-cr

# Run as a non-root user. uid/gid 1001 matches the default uid of the
# GitHub Actions runner, which means SBOM output written to a bind-mounted
# $GITHUB_WORKSPACE will land owned by the runner user instead of root.
# Standalone CLI consumers can override with `--user` if needed.
RUN groupadd --system --gid 1001 cyclonedx \
 && useradd  --system --uid 1001 --gid cyclonedx --create-home --shell /usr/sbin/nologin cyclonedx
USER 1001:1001

# Default command
CMD ["cyclonedx-cr"]
