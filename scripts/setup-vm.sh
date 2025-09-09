#!/bin/bash
# VM Setup Script - Global Region Support
# This script runs on VM startup and prepares the environment for test services

set -e

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [SETUP] $1" | tee -a /var/log/startup.log
}

log "Starting VM setup for regional testing..."

# Get metadata
DEPLOYMENT_ID=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/deployment-id || echo "unknown")
REGION=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/region || echo "unknown")
VM_ZONE=$(curl -s -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/zone | cut -d/ -f4 || echo "unknown")

log "VM Metadata - Deployment: $DEPLOYMENT_ID, Region: $REGION, Zone: $VM_ZONE"

# Update system packages
log "Updating system packages..."
apt-get update -y
apt-get upgrade -y

# Install essential packages
log "Installing essential packages..."
apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    htop \
    net-tools \
    jq \
    ca-certificates \
    gnupg \
    lsb-release

# Install Docker
log "Installing Docker..."
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add user to docker group
usermod -aG docker debian || usermod -aG docker $USER || log "Could not add user to docker group"

# Install Docker Compose (standalone)
log "Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="v2.24.1"
curl -SL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install Go
log "Installing Go..."
GO_VERSION="1.21.5"
wget "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -O /tmp/go.tar.gz
tar -C /usr/local -xzf /tmp/go.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/debian/.bashrc || true
rm /tmp/go.tar.gz

# Install Python and pip
log "Installing Python..."
apt-get install -y python3 python3-pip python3-venv python3-dev

# Create application directories with proper permissions
log "Creating application directories..."
mkdir -p /opt/test-services/{configs,logs,data}
chown -R debian:debian /opt/test-services || chown -R $USER:$USER /opt/test-services

# Create health check endpoint
log "Setting up health check service..."
cat > /opt/test-services/health-check.sh << 'EOF'
#!/bin/bash
# Simple health check script

API_SERVER_PORT=8080
TEST_RUNNER_PORT=5000

# Check if ports are listening
API_SERVER_STATUS="down"
TEST_RUNNER_STATUS="down"

if netstat -tuln | grep -q ":${API_SERVER_PORT} "; then
    if curl -f -s "http://localhost:${API_SERVER_PORT}/health" > /dev/null 2>&1; then
        API_SERVER_STATUS="up"
    fi
fi

if netstat -tuln | grep -q ":${TEST_RUNNER_PORT} "; then
    if curl -f -s "http://localhost:${TEST_RUNNER_PORT}/health" > /dev/null 2>&1; then
        TEST_RUNNER_STATUS="up"
    fi
fi

cat << EOM
{
  "status": "healthy",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "services": {
    "api_server": {
      "status": "$API_SERVER_STATUS",
      "port": $API_SERVER_PORT
    },
    "test_runner": {
      "status": "$TEST_RUNNER_STATUS", 
      "port": $TEST_RUNNER_PORT
    }
  },
  "vm_info": {
    "deployment_id": "$DEPLOYMENT_ID",
    "region": "$REGION",
    "zone": "$VM_ZONE"
  }
}
EOM
EOF

chmod +x /opt/test-services/health-check.sh

# Setup log rotation
log "Configuring log rotation..."
cat > /etc/logrotate.d/test-services << EOF
/opt/test-services/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
    maxsize 100M
}
EOF

# Configure firewall (if ufw is available)
if command -v ufw >/dev/null 2>&1; then
    log "Configuring firewall..."
    ufw allow 22/tcp   # SSH
    ufw allow 5000/tcp # Test Runner
    ufw allow 8080/tcp # API Server
    ufw --force enable
else
    log "UFW not available, skipping firewall configuration"
fi

# Set timezone to UTC
log "Setting timezone to UTC..."
timedatectl set-timezone UTC || ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Setup monitoring script
log "Setting up monitoring..."
cat > /opt/test-services/monitor.sh << 'EOF'
#!/bin/bash
# Simple monitoring script

LOG_FILE="/opt/test-services/logs/monitor.log"
mkdir -p "$(dirname "$LOG_FILE")"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Check disk usage
    DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    # Check memory usage
    MEMORY_USAGE=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    
    # Check load average
    LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    # Check Docker status
    DOCKER_STATUS="unknown"
    if systemctl is-active --quiet docker; then
        DOCKER_STATUS="running"
    else
        DOCKER_STATUS="stopped"
    fi
    
    # Log metrics
    echo "[$TIMESTAMP] Disk: ${DISK_USAGE}%, Memory: ${MEMORY_USAGE}%, Load: ${LOAD_AVG}, Docker: ${DOCKER_STATUS}" >> "$LOG_FILE"
    
    # Alert on high resource usage
    if [ "$DISK_USAGE" -gt 90 ]; then
        echo "[$TIMESTAMP] ALERT: Disk usage is at ${DISK_USAGE}%" >> "$LOG_FILE"
    fi
    
    if [ "$(echo "$MEMORY_USAGE > 90" | bc 2>/dev/null || echo "0")" = "1" ]; then
        echo "[$TIMESTAMP] ALERT: Memory usage is at ${MEMORY_USAGE}%" >> "$LOG_FILE"
    fi
    
    sleep 300  # Check every 5 minutes
done
EOF

chmod +x /opt/test-services/monitor.sh

# Start monitoring in background
nohup /opt/test-services/monitor.sh > /dev/null 2>&1 &

# Create systemd service for health checks
cat > /etc/systemd/system/test-services-health.service << EOF
[Unit]
Description=Test Services Health Check
After=network.target

[Service]
Type=simple
User=root
ExecStart=/opt/test-services/health-check.sh
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable test-services-health.service

# Verify Docker installation
log "Verifying Docker installation..."
docker --version
docker-compose --version

# Test Docker with hello-world
log "Testing Docker..."
docker run --rm hello-world

# Clean up
log "Cleaning up..."
apt-get autoremove -y
apt-get autoclean

# Create version file
cat > /opt/test-services/versions.txt << EOF
Docker: $(docker --version)
Docker Compose: $(docker-compose --version)
Go: $(if [ -x /usr/local/go/bin/go ]; then /usr/local/go/bin/go version; else echo "Not installed"; fi)
Python: $(python3 --version)
Git: $(git --version)
OS: $(lsb_release -d | cut -f2-)
Kernel: $(uname -r)
Setup completed: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Deployment ID: $DEPLOYMENT_ID
Region: $REGION
Zone: $VM_ZONE
EOF

log "VM setup completed successfully!"
log "System is ready for test service deployment"

# Signal completion
touch /opt/test-services/setup-complete