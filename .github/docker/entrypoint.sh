#!/bin/bash -e
cd /app

mkdir -p /var/log/panel/logs/ /var/log/supervisord/ /var/log/nginx/ /var/log/php8/ /var/run/php /var/run/nginx \
    && chmod 777 /var/log/panel/logs \
    && ln -s /var/log/panel/logs /app/storage/logs/

## check for .env file and generate app keys if missing
if [ -f /app/var/.env ]; then
  echo "external vars exist."
  rm -rf /app/.env
  ln -s /app/var/.env /app/
else
  echo "external vars don't exist."
  rm -rf /app/.env
  touch /app/var/.env

  ## manually generate a key because key generate --force fails
  if [ -z $APP_KEY ]; then
     echo -e "Generating key."
     APP_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
     echo -e "Generated app key: $APP_KEY"
     echo -e "APP_KEY=$APP_KEY" > /app/var/.env
  else
    echo -e "APP_KEY exists in environment, using that."
    echo -e "APP_KEY=$APP_KEY" > /app/var/.env
  fi

  ln -s /app/var/.env /app/
fi

## Set up nginx
if [ -f /etc/nginx/conf.d/panel.conf ]; then
    echo "Using existing nginx config."
else
    echo "Setting up nginx config."
    cp ./nginx.conf /etc/nginx/conf.d/panel.conf
    echo "Updating ssl config for domain."
    sed -i "s|<domain>|$(echo $APP_URL | sed 's~http[s]*://~~g')|g" /etc/nginx/conf.d/panel.conf
    echo "Removing default nginx config."
    rm -rf /etc/nginx/conf.d/default.conf
fi

## Make sure database port is set
if [[ -z $DB_PORT ]]; then
  echo -e "DB_PORT not specified, defaulting to 3306"
  DB_PORT=3306
fi

## Verify database is online
echo "Checking database status."
until nc -z -v -w30 $DB_HOST $DB_PORT
do
    echo "Waiting for connection..."
    sleep 1
done

## Make sure database is setup
echo -e "Migrating and seeding database"
php artisan migrate --seed --force

## Store environment variables
printenv | sed 's/^\(.*\)\=\(.*\)$/export \1="\2"/g' > /root/project_env.sh

## Start cronjobs
echo -e "Starting cronjobs."
cron

echo -e "Starting supervisord."
exec "$@"