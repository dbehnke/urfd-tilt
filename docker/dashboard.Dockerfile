# Frontend Build - Using Node.js for compatibility (AVX not required)
FROM node:20-slim AS frontend-builder

# Install go-task
RUN apt-get update && apt-get install -y curl git \
    && sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

WORKDIR /app
COPY web ./web
COPY Taskfile.yml .

# Install and build frontend with npm (instead of bun)
RUN cd web && npm install && npm run build

# Backend Build
FROM urfd-common AS backend-builder

WORKDIR /build/urfd-nng-dashboard
COPY . .

# Copy built frontend assets
# Note: Taskfile 'sync-assets' expects web/dist.
COPY --from=frontend-builder /app/web/dist ./web/dist

# Build backend
RUN task build-backend

# Install
RUN cp urfd-dashboard /usr/local/bin/dashboard

# Ensure the default working directory contains config.yaml
WORKDIR /build/urfd-nng-dashboard

# Run the installed dashboard binary (absolute path)
CMD ["/usr/local/bin/dashboard"]
