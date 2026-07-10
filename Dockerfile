# syntax=docker/dockerfile:1

############################################
# Stage 1: PHP dependencies via Composer
############################################
FROM php:8.4-cli-alpine AS vendor

WORKDIR /app

# Install system dependencies required for Composer/Laravel packages
RUN apk add --no-cache \
    bash \
    git \
    unzip \
    curl \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libzip-dev \
    libxml2-dev \
    oniguruma-dev \
    icu-dev \
    postgresql-dev \
    sqlite-dev \
    $PHPIZE_DEPS

# Install PHP extensions needed by Laravel
RUN docker-php-ext-configure gd --with-jpeg --with-freetype \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        pdo_pgsql \
        pdo_sqlite \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        zip \
        intl

# Copy Composer binary
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Copy only Composer files first for better Docker cache
COPY composer.json composer.lock ./

# Copy database folder if package discovery or scripts need it
COPY database/ database/

# Install production PHP dependencies
RUN composer install \
    --no-interaction \
    --no-dev \
    --prefer-dist \
    --optimize-autoloader \
    --no-scripts


############################################
# Stage 2: Frontend assets build
############################################
FROM node:20-alpine AS frontend

WORKDIR /app

# Copy package files first for better Docker cache
COPY package.json package-lock.json* ./

# Install frontend dependencies
RUN npm ci

# Copy full application source
COPY . .

# Copy vendor from Composer stage because some Vite/Laravel build tools may need it
COPY --from=vendor /app/vendor ./vendor

# Build frontend assets
RUN npm run build


############################################
# Stage 3: Final runtime image
############################################
FROM php:8.4-fpm-alpine AS app

LABEL maintainer="you@example.com"

ARG WWWUSER=1000
ARG WWWGROUP=1000

# Install runtime system dependencies
RUN apk add --no-cache \
    nginx \
    supervisor \
    bash \
    curl \
    git \
    unzip \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libzip-dev \
    libxml2-dev \
    oniguruma-dev \
    icu-dev \
    postgresql-dev \
    sqlite-dev \
    $PHPIZE_DEPS

# Install PHP extensions
RUN docker-php-ext-configure gd --with-jpeg --with-freetype \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        pdo_pgsql \
        pdo_sqlite \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        zip \
        intl \
        opcache \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apk del $PHPIZE_DEPS

# Copy Composer binary
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Copy PHP custom configs
COPY docker/php/php.ini /usr/local/etc/php/conf.d/99-custom.ini
COPY docker/php/opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# Copy Nginx and Supervisor configs
COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/default.conf /etc/nginx/http.d/default.conf
COPY docker/supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create app user/group
RUN addgroup -g ${WWWGROUP} -S www \
    && adduser -u ${WWWUSER} -S www -G www

WORKDIR /var/www/html

# Copy full Laravel application
COPY --chown=www:www . .

# Copy Composer vendor from vendor stage
COPY --from=vendor --chown=www:www /app/vendor ./vendor

# Copy built frontend assets from frontend stage
COPY --from=frontend --chown=www:www /app/public/build ./public/build

# Copy entrypoint
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Prepare Laravel writable directories
RUN mkdir -p \
        storage/framework/cache \
        storage/framework/sessions \
        storage/framework/views \
        storage/logs \
        bootstrap/cache \
    && chown -R www:www storage bootstrap/cache \
    && chmod -R 775 storage bootstrap/cache

EXPOSE 8080

ENTRYPOINT ["entrypoint.sh"]

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf", "-n"]
