# Multi-stage production-ready Dockerfile for Frappe LMS

# --- Stage 1: Build assets and install apps ---
FROM frappe/bench:latest AS builder

USER root
# Install build-time system dependencies
RUN apt-get update && apt-get install --no-install-recommends -y \
    libxml2-dev \
    libxslt1-dev \
    && rm -rf /var/lib/apt/lists/*

USER frappe
WORKDIR /home/frappe

# Initialize the frappe-bench environment
RUN bench init --skip-redis-config-generation --frappe-branch=version-15 frappe-bench

WORKDIR /home/frappe/frappe-bench

# Install official payments app
RUN bench get-app payments

# Copy local lms app source code directly into the bench apps directory
COPY --chown=frappe:frappe . apps/lms

# Manually install the lms app (bench get-app requires a git repo, which COPY doesn't preserve reliably)
RUN cd apps/lms \
    && git init \
    && git add -A \
    && git -c user.name="docker" -c user.email="docker@build" commit -m "docker build" --quiet \
    && cd /home/frappe/frappe-bench \
    && ./env/bin/pip install -e apps/lms \
    && echo "lms" >> sites/apps.txt

# Build all frontend assets (Vite/yarn)
RUN bench build --production

# Move assets to a separate directory so they don't get wiped by the sites volume mount
RUN cp -r sites/assets /home/frappe/frappe-bench/assets && \
    rm -rf sites/assets

# --- Stage 2: Final lightweight backend and runner image ---
FROM frappe/bench:latest AS backend

USER frappe
WORKDIR /home/frappe/frappe-bench

# Copy the entire configured bench from the builder stage
COPY --from=builder --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

# Expose ports (8000 for gunicorn, 9000 for websocket/socketio)
EXPOSE 8000 9000

USER root
# Copy custom entrypoint and startup scripts
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/start.sh

USER frappe
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/local/bin/start.sh"]

# --- Stage 3: Frontend Nginx image ---
FROM nginx:alpine AS frontend

# Copy custom Nginx configuration
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf

# Copy baked assets from the builder stage
COPY --from=builder /home/frappe/frappe-bench/assets /home/frappe/frappe-bench/assets

EXPOSE 8080

