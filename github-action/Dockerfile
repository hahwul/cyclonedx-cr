# Use the cyclonedx-cr base image from GitHub Container Registry
FROM ghcr.io/hahwul/cyclonedx-cr:v1.0.2

# Copy the entrypoint script into the container
COPY entrypoint.sh /entrypoint.sh

# Run the script via /bin/sh, so no executable bit is required

# Set the entrypoint to the script
ENTRYPOINT ["/bin/sh", "-l", "/entrypoint.sh"]
