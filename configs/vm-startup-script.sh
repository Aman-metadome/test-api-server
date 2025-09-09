#!/bin/bash
# VM Startup Script Template - Global Region Support
# This is a template that gets customized during deployment

# Redirect output to startup log
exec > >(tee -a /var/log/startup.log)
exec 2>&1

echo "$(date): Starting VM setup for global regional testing..."

# Get instance metadata
INSTANCE_NAME=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/name)
INSTANCE_ZONE=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4)
PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/project/project-id)

echo "Instance: $INSTANCE_NAME"
echo "Zone: $INSTANCE_ZONE"
echo "Project: $PROJECT_ID"

# Update system
apt-get update -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Start Docker
systemctl start docker
systemctl enable docker

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install other essentials
apt-get install -y curl wget git unzip htop net-tools jq

# Create application directory
mkdir -p /opt/test-services
chown debian:debian /opt/test-services

echo "$(date): VM setup completed"