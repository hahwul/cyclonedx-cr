# Use the cyclonedx-cr base image from GitHub Container Registry
FROM ghcr.io/hahwul/cyclonedx-cr:latest

# Install jq for JSON processing
RUN apt-get update && apt-get install -y jq

# Copy the entrypoint script into the container
COPY entrypoint.sh /entrypoint.sh

# Make the entrypoint script executable
RUN chmod 755 /entrypoint.sh

# Set the entrypoint to the script
ENTRYPOINT ["/entrypoint.sh"]