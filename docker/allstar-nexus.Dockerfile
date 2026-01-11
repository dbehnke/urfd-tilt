# Build stage
FROM golang:1.25.3-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git make nodejs npm

WORKDIR /build

# Copy go mod files first for better caching
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build frontend
WORKDIR /build/frontend
RUN npm ci && npm run build

# Build backend with embedded frontend
WORKDIR /build
# Use fixed version string for dev build or dynamic
RUN go build \
    -ldflags "-X 'main.buildVersion=dev-tilt' -X 'main.buildTime=$(date -u +'%Y-%m-%dT%H:%M:%SZ')'" \
    -o allstar-nexus \
    .

# Final stage
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    wget

WORKDIR /app

# Copy binary from builder
COPY --from=builder /build/allstar-nexus .
# We might need default config or let docker-compose mount it
COPY --from=builder /build/config.yaml.example .

# Expose port
EXPOSE 8080

CMD ["./allstar-nexus"]
