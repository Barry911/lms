#!/bin/bash
set -e

# Configuration defaults
DB_HOST=${DB_HOST:-db}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD:-123}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin}
SITE_NAME=${SITE_NAME:-lms.localhost}

# Gunicorn configuration defaults
GUNICORN_THREADS=${GUNICORN_THREADS:-4}
GUNICORN_WORKERS=${GUNICORN_WORKERS:-2}
GUNICORN_TIMEOUT=${GUNICORN_TIMEOUT:-120}

SITE_DIR="/home/frappe/frappe-bench/sites/${SITE_NAME}"

# Check if site already exists
if [ ! -d "$SITE_DIR" ]; then
    echo "Site ${SITE_NAME} does not exist. Beginning automated initialization..."

    # Wait for Database connectivity
    echo "Waiting for MariaDB connection at ${DB_HOST}..."
    until mysql -h"${DB_HOST}" -u"root" -p"${DB_ROOT_PASSWORD}" -e "status" &>/dev/null; do
        echo "MariaDB is unavailable. Retrying in 3 seconds..."
        sleep 3
    done
    echo "MariaDB connection established successfully."

    # Set MariaDB host config
    bench set-mariadb-host "${DB_HOST}"

    # Create the new site
    echo "Creating new site ${SITE_NAME}..."
    bench new-site "${SITE_NAME}" \
        --force \
        --mariadb-root-password "${DB_ROOT_PASSWORD}" \
        --admin-password "${ADMIN_PASSWORD}" \
        --no-mariadb-socket

    # Install applications
    echo "Installing payments app on ${SITE_NAME}..."
    bench --site "${SITE_NAME}" install-app payments

    echo "Installing lms app on ${SITE_NAME}..."
    bench --site "${SITE_NAME}" install-app lms

    echo "Setting site default config..."
    bench --site "${SITE_NAME}" set-config developer_mode 0
    bench --site "${SITE_NAME}" clear-cache
    bench use "${SITE_NAME}"
    echo "Initialization completed successfully!"
else
    echo "Site ${SITE_NAME} already exists. Running database migrations..."
    
    # Wait for Database connectivity
    echo "Waiting for MariaDB connection at ${DB_HOST}..."
    until mysql -h"${DB_HOST}" -u"root" -p"${DB_ROOT_PASSWORD}" -e "status" &>/dev/null; do
        echo "MariaDB is unavailable. Retrying in 3 seconds..."
        sleep 3
    done
    
    bench --site "${SITE_NAME}" migrate
    echo "Database migrations applied successfully."
fi

# Boot dynamic Gunicorn web server
echo "Starting Gunicorn with $GUNICORN_WORKERS workers and $GUNICORN_THREADS threads..."
exec /home/frappe/frappe-bench/env/bin/gunicorn \
  --chdir=/home/frappe/frappe-bench/sites \
  --bind=0.0.0.0:8000 \
  --threads="$GUNICORN_THREADS" \
  --workers="$GUNICORN_WORKERS" \
  --worker-class=gthread \
  --worker-tmp-dir=/dev/shm \
  --timeout="$GUNICORN_TIMEOUT" \
  --preload \
  frappe.app:application
