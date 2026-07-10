# Deploying this Laravel app to Coolify via GitHub

## 1. Push to GitHub

```bash
cd laravel-app
git init
git add .
git commit -m "Initial commit: Laravel + Docker for Coolify"
git branch -M main
git remote add origin git@github.com:<your-username>/<your-repo>.git
git push -u origin main
```

## 2. Create the app in Coolify

1. In Coolify: **+ New Resource → Application → Public/Private GitHub Repository**.
2. Select your repo and the `main` branch.
3. Build Pack: choose **Dockerfile** (Coolify will detect the `Dockerfile` at the repo root automatically).
4. Port: set **8080** (this is what nginx listens on inside the container).
5. Health check path: `/up` (Laravel's built-in health route).

## 3. Environment variables

In Coolify's **Environment Variables** tab for the app, add at minimum:

```
APP_NAME=Laravel
APP_ENV=production
APP_KEY=                # leave blank; generated automatically on first boot
APP_DEBUG=false
APP_URL=https://your-domain.example.com

DB_CONNECTION=mysql
DB_HOST=<your-db-service-name-or-host>
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=<strong-password>

REDIS_HOST=<your-redis-service-name-or-host>
REDIS_PORT=6379
CACHE_STORE=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis

RUN_MIGRATIONS=true
```

Tip: In Coolify you can spin up **MySQL** and **Redis** as separate managed resources in the same project, then reference their internal service names as `DB_HOST` / `REDIS_HOST`.

`APP_KEY` does not need to be pre-generated — `docker/entrypoint.sh` runs `php artisan key:generate` automatically on first boot if it's missing. If you prefer to pin it (recommended so it survives redeploys/rebuilds), generate one locally and paste it in:

```bash
docker run --rm laravel-app:local php artisan key:generate --show
```

## 4. Persistent storage

Mount a persistent volume in Coolify for:

```
/var/www/html/storage/app
```

so uploaded files survive redeploys. Logs and cache under `storage/framework` and `storage/logs` are fine to be ephemeral.

## 5. Deploy

Click **Deploy**. Coolify will:
- Build the multi-stage Dockerfile (Composer install → npm build → final PHP-FPM/nginx/Supervisor image).
- Run the container, which on boot: waits for the DB, runs `php artisan migrate --force`, caches config/routes/views, links storage, then starts nginx + php-fpm + queue worker + scheduler under Supervisor.

## 6. Auto-deploy on push (optional)

In Coolify, enable **Automatic Deployment** / add the provided webhook URL as a GitHub webhook (or install the Coolify GitHub App) so every push to `main` triggers a rebuild + redeploy.

## Local development

```bash
docker compose up --build
```

App will be available at `http://localhost:8080`. This local compose file also spins up MySQL and Redis containers for you — separate from the Coolify-managed production database.

## Notes

- PHP version: **8.3** (Laravel 13 requires `^8.3`).
- Composer: **2.x** (via the official `composer:2` build image).
- The queue worker and scheduler run inside the same container via Supervisor. For higher-traffic production apps, consider splitting these into separate Coolify services (same image, different `CMD`) so they scale independently of the web process.
