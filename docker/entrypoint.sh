#!/bin/bash
set -e

cd /var/www/html

# Ensure .env exists (Coolify typically injects env vars directly, but this
# covers local/manual runs that mount a .env file).
if [ ! -f .env ] && [ -f .env.example ]; then
    cp .env.example .env
fi

# Generate an app key if one isn't set (safe no-op if already set).
if [ -f artisan ]; then
    php artisan key:generate --force --no-interaction || true
fi

# Fix storage/bootstrap cache permissions on every boot (volumes reset perms).
mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache
chown -R www:www storage bootstrap/cache
chmod -R 775 storage bootstrap/cache

# Wait for the database to accept connections before migrating (best effort).
if [ -n "$DB_HOST" ] && [ "$DB_CONNECTION" != "sqlite" ]; then
    echo "Waiting for database at $DB_HOST:${DB_PORT:-3306}..."
    for i in $(seq 1 30); do
        (echo > /dev/tcp/"$DB_HOST"/"${DB_PORT:-3306}") >/dev/null 2>&1 && break
        sleep 2
    done
fi

# Run migrations automatically (set RUN_MIGRATIONS=false to disable).
if [ "${RUN_MIGRATIONS:-true}" = "true" ]; then
    php artisan migrate --force --no-interaction || echo "Migration step failed or skipped."
fi

# Cache config/routes/views for production performance.
php artisan config:cache --no-interaction || true
php artisan route:cache --no-interaction || true
php artisan view:cache --no-interaction || true

# Link storage (safe if already linked).
php artisan storage:link --no-interaction || true

exec "$@"
