# Use the cyclonedx-cr base image from GitHub Container Registry
FROM ghcr.io/hahwul/cyclonedx-cr:v1.3.0

# Copy the entrypoint script into the container
COPY entrypoint.sh /entrypoint.sh

# Run the script via /bin/sh, so no executable bit is required

# Run as a non-root user so SBOM output written into the bind-mounted
# $GITHUB_WORKSPACE is owned by the runner user instead of root. The
# `id -u cyclonedx` check makes this work whether the base image already
# provisions the user (newer releases) or not (v1.3.0 and earlier).
USER root
RUN if ! id -u cyclonedx >/dev/null 2>&1; then \
      groupadd --system --gid 1001 cyclonedx && \
      useradd  --system --uid 1001 --gid cyclonedx --create-home --shell /usr/sbin/nologin cyclonedx; \
    fi
USER 1001:1001

# Set the entrypoint to the script
ENTRYPOINT ["/bin/sh", "-l", "/entrypoint.sh"]
