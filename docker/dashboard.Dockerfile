# Frontend Build
FROM oven/bun:1 AS frontend-builder

# Install go-task
RUN apt-get update && apt-get install -y curl git \
    && sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

WORKDIR /app
COPY web ./web
COPY Taskfile.yml .

# Build frontend
RUN task install-frontend && task build-frontend

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

CMD ["dashboard"]
