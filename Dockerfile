# Use the lightweight Alpine base image
FROM alpine:latest AS builder

# Copy the ip update script into the container
COPY update-ip.sh /app/update-ip.sh

# Add entrypoint script for changing update frequency
COPY entrypoint.sh /app/entrypoint.sh

FROM alpine:latest

# Set a working directory
WORKDIR /app

# Install required tools: bash, curl, and jq for API response parsing
RUN apk add --no-cache bash curl jq

# Copy the scripts from the builder stage
COPY --from=builder /app/update-ip.sh /app/update-ip.sh
COPY --from=builder /app/entrypoint.sh /app/entrypoint.sh

# Make scripts executable
RUN chmod +x /app/update-ip.sh /app/entrypoint.sh

# Run the entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]