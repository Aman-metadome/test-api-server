# Multi-stage Go Dockerfile for API Server
# Supports global deployment with dynamic configuration

# Build stage
FROM golang:1.21-alpine AS builder

# Set environment variables for build
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOARCH=amd64

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set working directory
WORKDIR /build

# Copy go mod files
COPY api-server/go.mod api-server/go.sum ./

# Download dependencies
RUN go mod download && go mod verify

# Copy source code
COPY api-server/ .

# Build the application
RUN go build -ldflags="-w -s" -o api-server ./cmd/api

# Final stage
FROM alpine:3.18

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    curl \
    tzdata \
    && addgroup -S app \
    && adduser -S app -G app

# Copy binary from build stage
COPY --from=builder /build/api-server /usr/local/bin/api-server

# Copy any required static files
COPY --from=builder /build/configs/ /app/configs/

# Create application directories
RUN mkdir -p /app/logs /app/data && \
    chown -R app:app /app

# Switch to non-root user
USER app

# Set working directory
WORKDIR /app

# Expose port (will be overridden by environment variable)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:${PORT:-8080}/health || exit 1

# Default command
CMD ["/usr/local/bin/api-server"]