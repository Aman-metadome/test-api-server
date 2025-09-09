#!/bin/bash
# Service Deployment Script - Global Region Support
# This script deploys and starts the test services

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICES_DIR="/opt/test-services"
LOG_FILE="$SERVICES_DIR/logs/deployment.log"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [DEPLOY] $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    log "ERROR: $1"
    exit 1
}

# Create log directory
mkdir -p "$SERVICES_DIR/logs"

log "Starting service deployment..."

# Change to services directory
cd "$SERVICES_DIR" || handle_error "Could not change to services directory"

# Verify required files
log "Verifying required files..."
REQUIRED_FILES=(
    "test-runner"
    "api-server" 
    "docker/test-runner/Dockerfile"
    "docker/api-server/Dockerfile"
    "configs/docker-compose.yml"
    "configs/test-runner.env"
    "configs/api-server.env"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -e "$file" ]; then
        handle_error "Required file not found: $file"
    fi
done

log "All required files found"

# Copy environment files to root for docker-compose
log "Setting up environment files..."
cp configs/test-runner.env .
cp configs/api-server.env .
cp configs/docker-compose.yml .

# Check if Docker is running
log "Checking Docker status..."
if ! systemctl is-active --quiet docker; then
    log "Starting Docker service..."
    systemctl start docker || handle_error "Could not start Docker"
    sleep 5
fi

# Verify Docker is accessible
docker info > /dev/null 2>&1 || handle_error "Docker is not accessible"

log "Docker is running and accessible"

# Stop any existing services
log "Stopping existing services..."
docker-compose down --timeout 30 2>/dev/null || log "No existing services to stop"

# Clean up old containers and images if they exist
log "Cleaning up old containers..."
docker container prune -f || log "Container cleanup completed"

# Build services
log "Building test runner service..."
docker-compose build test-runner || handle_error "Failed to build test-runner"

log "Building API server service..."
docker-compose build api-server || handle_error "Failed to build api-server"

# Start services
log "Starting services..."
docker-compose up -d || handle_error "Failed to start services"

# Wait for services to be ready
log "Waiting for services to start..."
sleep 30

# Check service status
log "Checking service health..."

# Function to check service health
check_service_health() {
    local service_name=$1
    local port=$2
    local endpoint=$3
    local max_attempts=30
    local attempt=0
    
    log "Checking $service_name health on port $port..."
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -f -s --connect-timeout 5 "http://localhost:$port$endpoint" > /dev/null 2>&1; then
            log "$service_name is healthy"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log "  Health check attempt $attempt/$max_attempts for $service_name..."
        sleep 10
    done
    
    log "WARNING: $service_name failed health checks after $max_attempts attempts"
    return 1
}

# Check API Server health
API_HEALTHY=false
if check_service_health "API Server" "8080" "/health"; then
    API_HEALTHY=true
fi

# Check Test Runner health
RUNNER_HEALTHY=false
if check_service_health "Test Runner" "5000" "/health"; then
    RUNNER_HEALTHY=true
fi

# Display service status
log "Service deployment status:"
docker-compose ps

# Show container logs for troubleshooting
log "Recent container logs:"
log "=== API Server Logs ==="
docker-compose logs --tail=20 api-server 2>/dev/null || log "Could not retrieve API server logs"

log "=== Test Runner Logs ==="
docker-compose logs --tail=20 test-runner 2>/dev/null || log "Could not retrieve test runner logs"

# Create status file
cat > "$SERVICES_DIR/deployment-status.json" << EOF
{
    "deployment_completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "services": {
        "api_server": {
            "healthy": $API_HEALTHY,
            "port": 8080,
            "endpoint": "/health"
        },
        "test_runner": {
            "healthy": $RUNNER_HEALTHY,
            "port": 5000,
            "endpoint": "/health"
        }
    },
    "docker_compose": {
        "services_running": $(docker-compose ps --services --filter status=running | wc -l),
        "total_services": $(docker-compose ps --services | wc -l)
    }
}
EOF

# Final status check
if [ "$API_HEALTHY" = true ] && [ "$RUNNER_HEALTHY" = true ]; then
    log "✅ All services deployed and healthy!"
    log "   - API Server: http://localhost:8080"
    log "   - Test Runner: http://localhost:5000"
    exit 0
else
    log "⚠️  Deployment completed with health check warnings"
    log "   - API Server healthy: $API_HEALTHY"
    log "   - Test Runner healthy: $RUNNER_HEALTHY"
    log "   - Check container logs for troubleshooting"
    exit 1
fi