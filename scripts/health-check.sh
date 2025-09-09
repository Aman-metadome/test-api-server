#!/bin/bash
# Comprehensive Health Check Script - Global Region Support
# This script performs detailed health checks on all components

set -e

# Configuration
SERVICES_DIR="/opt/test-services"
LOG_FILE="$SERVICES_DIR/logs/health-check.log"
API_SERVER_PORT=8080
TEST_RUNNER_PORT=5000

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [HEALTH] $1" | tee -a "$LOG_FILE"
}

# Status functions
print_status() {
    local status=$1
    local message=$2
    
    case $status in
        "OK")
            echo -e "${GREEN}✅ $message${NC}"
            ;;
        "WARNING")
            echo -e "${YELLOW}⚠️  $message${NC}"
            ;;
        "ERROR")
            echo -e "${RED}❌ $message${NC}"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  $message${NC}"
            ;;
    esac
}

# Create log directory
mkdir -p "$SERVICES_DIR/logs"

log "Starting comprehensive health check..."
echo ""
echo "🏥 SYSTEM HEALTH CHECK"
echo "======================"

# Initialize counters
CHECKS_TOTAL=0
CHECKS_PASSED=0
CHECKS_WARNING=0
CHECKS_FAILED=0

# Function to increment counters
increment_check() {
    local status=$1
    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    
    case $status in
        "OK")
            CHECKS_PASSED=$((CHECKS_PASSED + 1))
            ;;
        "WARNING")
            CHECKS_WARNING=$((CHECKS_WARNING + 1))
            ;;
        "ERROR")
            CHECKS_FAILED=$((CHECKS_FAILED + 1))
            ;;
    esac
}

# 1. System Resource Checks
echo ""
echo "🖥️  SYSTEM RESOURCES"
echo "-------------------"

# Check disk usage
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    print_status "OK" "Disk usage: ${DISK_USAGE}%"
    increment_check "OK"
elif [ "$DISK_USAGE" -lt 90 ]; then
    print_status "WARNING" "Disk usage: ${DISK_USAGE}%"
    increment_check "WARNING"
else
    print_status "ERROR" "Disk usage: ${DISK_USAGE}% (Critical)"
    increment_check "ERROR"
fi

# Check memory usage
MEMORY_INFO=$(free -m)
MEMORY_TOTAL=$(echo "$MEMORY_INFO" | grep '^Mem:' | awk '{print $2}')
MEMORY_USED=$(echo "$MEMORY_INFO" | grep '^Mem:' | awk '{print $3}')
MEMORY_PERCENT=$((MEMORY_USED * 100 / MEMORY_TOTAL))

if [ "$MEMORY_PERCENT" -lt 80 ]; then
    print_status "OK" "Memory usage: ${MEMORY_PERCENT}% (${MEMORY_USED}MB/${MEMORY_TOTAL}MB)"
    increment_check "OK"
elif [ "$MEMORY_PERCENT" -lt 90 ]; then
    print_status "WARNING" "Memory usage: ${MEMORY_PERCENT}% (${MEMORY_USED}MB/${MEMORY_TOTAL}MB)"
    increment_check "WARNING"
else
    print_status "ERROR" "Memory usage: ${MEMORY_PERCENT}% (${MEMORY_USED}MB/${MEMORY_TOTAL}MB)"
    increment_check "ERROR"
fi

# Check load average
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
CPU_COUNT=$(nproc)
LOAD_PERCENT=$(echo "$LOAD_AVG * 100 / $CPU_COUNT" | bc -l 2>/dev/null | cut -d. -f1 || echo "0")

if [ "$LOAD_PERCENT" -lt 70 ]; then
    print_status "OK" "Load average: $LOAD_AVG (${LOAD_PERCENT}% of ${CPU_COUNT} CPUs)"
    increment_check "OK"
elif [ "$LOAD_PERCENT" -lt 90 ]; then
    print_status "WARNING" "Load average: $LOAD_AVG (${LOAD_PERCENT}% of ${CPU_COUNT} CPUs)"
    increment_check "WARNING"
else
    print_status "ERROR" "Load average: $LOAD_AVG (${LOAD_PERCENT}% of ${CPU_COUNT} CPUs)"
    increment_check "ERROR"
fi

# 2. Docker System Check
echo ""
echo "🐳 DOCKER SYSTEM"
echo "----------------"

# Check if Docker daemon is running
if systemctl is-active --quiet docker; then
    print_status "OK" "Docker daemon is running"
    increment_check "OK"
    
    # Check Docker version
    DOCKER_VERSION=$(docker --version 2>/dev/null || echo "unknown")
    print_status "INFO" "Docker version: $DOCKER_VERSION"
    
    # Check Docker system info
    DOCKER_CONTAINERS_RUNNING=$(docker ps --format "table {{.Names}}" 2>/dev/null | grep -v NAMES | wc -l)
    print_status "INFO" "Running containers: $DOCKER_CONTAINERS_RUNNING"
    
else
    print_status "ERROR" "Docker daemon is not running"
    increment_check "ERROR"
fi

# 3. Network Connectivity
echo ""
echo "🌐 NETWORK CONNECTIVITY"
echo "------------------------"

# Check external connectivity
if curl -s --connect-timeout 10 https://www.google.com > /dev/null; then
    print_status "OK" "External internet connectivity"
    increment_check "OK"
else
    print_status "ERROR" "No external internet connectivity"
    increment_check "ERROR"
fi

# Check DNS resolution
if nslookup google.com > /dev/null 2>&1; then
    print_status "OK" "DNS resolution working"
    increment_check "OK"
else
    print_status "ERROR" "DNS resolution failed"
    increment_check "ERROR"
fi

# 4. Port Availability
echo ""
echo "🔌 PORT AVAILABILITY"
echo "--------------------"

# Check if required ports are listening
check_port() {
    local port=$1
    local service=$2
    
    if netstat -tuln | grep -q ":${port} "; then
        print_status "OK" "$service port $port is listening"
        increment_check "OK"
        return 0
    else
        print_status "ERROR" "$service port $port is not listening"
        increment_check "ERROR"
        return 1
    fi
}

API_PORT_OPEN=$(check_port $API_SERVER_PORT "API Server")
RUNNER_PORT_OPEN=$(check_port $TEST_RUNNER_PORT "Test Runner")

# 5. Service Health Checks
echo ""
echo "🏥 SERVICE HEALTH"
echo "-----------------"

# Function to check HTTP endpoint
check_http_endpoint() {
    local url=$1
    local service_name=$2
    local timeout=${3:-10}
    
    if curl -f -s --connect-timeout "$timeout" "$url" > /dev/null 2>&1; then
        print_status "OK" "$service_name endpoint responds"
        increment_check "OK"
        return 0
    else
        print_status "ERROR" "$service_name endpoint not responding"
        increment_check "ERROR"
        return 1
    fi
}

# Check API Server health
API_HEALTHY=$(check_http_endpoint "http://localhost:$API_SERVER_PORT/health" "API Server")

# Check Test Runner health
RUNNER_HEALTHY=$(check_http_endpoint "http://localhost:$TEST_RUNNER_PORT/health" "Test Runner")

# 6. Docker Compose Service Status
echo ""
echo "📦 DOCKER COMPOSE SERVICES"
echo "---------------------------"

if [ -f "$SERVICES_DIR/docker-compose.yml" ]; then
    cd "$SERVICES_DIR"
    
    # Get service status
    COMPOSE_STATUS=$(docker-compose ps 2>/dev/null || echo "")
    
    if [ -n "$COMPOSE_STATUS" ]; then
        # Check each service
        SERVICES=$(docker-compose config --services 2>/dev/null || echo "")
        
        for service in $SERVICES; do
            STATUS=$(docker-compose ps --filter status=running "$service" 2>/dev/null | grep -v Name | wc -l)
            
            if [ "$STATUS" -gt 0 ]; then
                print_status "OK" "Docker service '$service' is running"
                increment_check "OK"
            else
                print_status "ERROR" "Docker service '$service' is not running"
                increment_check "ERROR"
            fi
        done
    else
        print_status "WARNING" "No Docker Compose services found"
        increment_check "WARNING"
    fi
else
    print_status "WARNING" "Docker Compose file not found"
    increment_check "WARNING"
fi

# 7. Log File Health
echo ""
echo "📋 LOG FILES"
echo "------------"

# Check log directory
if [ -d "$SERVICES_DIR/logs" ]; then
    LOG_COUNT=$(find "$SERVICES_DIR/logs" -name "*.log" -type f | wc -l)
    print_status "INFO" "Log files found: $LOG_COUNT"
    
    # Check for recent log activity
    RECENT_LOGS=$(find "$SERVICES_DIR/logs" -name "*.log" -type f -mmin -10 | wc -l)
    if [ "$RECENT_LOGS" -gt 0 ]; then
        print_status "OK" "Recent log activity detected"
        increment_check "OK"
    else
        print_status "WARNING" "No recent log activity"
        increment_check "WARNING"
    fi
else
    print_status "WARNING" "Log directory not found"
    increment_check "WARNING"
fi

# 8. File System Permissions
echo ""
echo "🔐 FILE PERMISSIONS"
echo "-------------------"

# Check services directory permissions
if [ -w "$SERVICES_DIR" ]; then
    print_status "OK" "Services directory is writable"
    increment_check "OK"
else
    print_status "ERROR" "Services directory is not writable"
    increment_check "ERROR"
fi

# Check if setup is complete
if [ -f "$SERVICES_DIR/setup-complete" ]; then
    print_status "OK" "VM setup completed"
    increment_check "OK"
else
    print_status "WARNING" "VM setup may not be complete"
    increment_check "WARNING"
fi

# 9. Generate Health Summary
echo ""
echo "📊 HEALTH CHECK SUMMARY"
echo "========================"

HEALTH_PERCENTAGE=$((CHECKS_PASSED * 100 / CHECKS_TOTAL))

echo "Total checks: $CHECKS_TOTAL"
echo "Passed: $CHECKS_PASSED"
echo "Warnings: $CHECKS_WARNING"
echo "Failed: $CHECKS_FAILED"
echo "Health score: $HEALTH_PERCENTAGE%"

# Determine overall health status
if [ $CHECKS_FAILED -eq 0 ] && [ $CHECKS_WARNING -eq 0 ]; then
    OVERALL_STATUS="HEALTHY"
    STATUS_COLOR=$GREEN
elif [ $CHECKS_FAILED -eq 0 ] && [ $CHECKS_WARNING -gt 0 ]; then
    OVERALL_STATUS="DEGRADED"
    STATUS_COLOR=$YELLOW
else
    OVERALL_STATUS="UNHEALTHY"
    STATUS_COLOR=$RED
fi

echo -e "\n${STATUS_COLOR}Overall Status: $OVERALL_STATUS${NC}"

# Generate JSON health report
cat > "$SERVICES_DIR/health-report.json" << EOF
{
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "overall_status": "$OVERALL_STATUS",
    "health_percentage": $HEALTH_PERCENTAGE,
    "checks": {
        "total": $CHECKS_TOTAL,
        "passed": $CHECKS_PASSED,
        "warnings": $CHECKS_WARNING,
        "failed": $CHECKS_FAILED
    },
    "services": {
        "api_server": {
            "port": $API_SERVER_PORT,
            "healthy": $([ "$API_HEALTHY" = "0" ] && echo "true" || echo "false")
        },
        "test_runner": {
            "port": $TEST_RUNNER_PORT,
            "healthy": $([ "$RUNNER_HEALTHY" = "0" ] && echo "true" || echo "false")
        }
    },
    "system": {
        "disk_usage_percent": $DISK_USAGE,
        "memory_usage_percent": $MEMORY_PERCENT,
        "load_average": "$LOAD_AVG",
        "docker_running": $(systemctl is-active --quiet docker && echo "true" || echo "false")
    }
}
EOF

log "Health check completed. Status: $OVERALL_STATUS ($HEALTH_PERCENTAGE%)"

# Exit with appropriate code
case $OVERALL_STATUS in
    "HEALTHY")
        exit 0
        ;;
    "DEGRADED")
        exit 1
        ;;
    "UNHEALTHY")
        exit 2
        ;;
    *)
        exit 3
        ;;
esac