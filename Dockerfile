# Stage 0:
# Build the assets that are needed for the frontend. This build stage is then discarded
# since we won't need NodeJS anymore in the future. This Docker image ships a final production
# level distribution of Pterodactyl.
FROM --platform=$TARGETOS/$TARGETARCH mhart/alpine-node:14
WORKDIR /app
COPY . ./
RUN yarn install --frozen-lockfile \
    && yarn run build:production

# Stage 1:
# Build the actual container with all of the needed PHP dependencies that will run the application.
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

WORKDIR /app

COPY . ./
COPY --from=0 /app/public/assets ./public/assets

RUN apt update -y \
                && apt install -y --no-install-recommends software-properties-common curl apt-transport-https ca-certificates gnupg \
                && LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php \
                && apt update \
                && apt -y --no-install-recommends install supervisor netcat cron php8.1 php8.1-common php8.1-cli php8.1-gd php8.1-mysql php8.1-mbstring php8.1-bcmath php8.1-xml php8.1-fpm php8.1-curl php8.1-zip nginx tar unzip \
        && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
        && cp .env.example .env \
        && mkdir -p bootstrap/cache/ storage/logs storage/framework/sessions storage/framework/views storage/framework/cache \
                && chmod -R 755 storage/* bootstrap/cache/ \
        && composer install --no-dev --optimize-autoloader \
        && rm -rf .env bootstrap/cache/*.php \
        && chown -R www-data:www-data . \
        && mkdir -p /var/run/php /var/run/nginx \
        && rm -rf /var/lib/apt/lists/* \
        && echo "* * * * * . /root/project_env.sh; /usr/bin/php /app/artisan schedule:run >> /tmp/cron 2>&1" >> /var/spool/cron/crontabs/root \
        && chmod -R 600 /var/spool/cron

COPY .github/docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY .github/docker/php-fpm.conf /etc/php/8.1/fpm/pool.d/www.conf
COPY .github/docker/supervisord.conf /etc/supervisord.conf
COPY .github/docker/entrypoint.sh ./entrypoint.sh

# Copy configs that are used in entrypoint.sh
COPY .github/docker/nginx.conf ./nginx.conf

EXPOSE 80 443
ENTRYPOINT [ "/bin/bash", "./entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisord.conf"]