#!/bin/sh

set -e

# wait for database connection
echo "Waiting for database to become available"
if ! timeout 60 bash -c 'until printf "" 2>>/dev/null >>/dev/tcp/$0/$1; do sleep 1; done' "${MATOMO_DB_HOST:-localhost}" "3306"
then
  echo "Database never became ready. Exiting."
  exit 1
fi

# install matomo
if bash -c '/var/www/html/console -q site:list' >> /dev/null
then
  echo "Matomo is already installed, skipping installation."
else
  echo "Installing Matomo..."
  /var/www/html/console plugin:activate ExtraTools
  /var/www/html/console matomo:install --force
  #if [ $HOST_ENV = "TEST" ]; then
    echo "Enabling Login plugins..."
    /var/www/html/console plugin:activate LoginLdap
    cat /tmp/LoginLdap.conf >> /var/www/html/config/config.ini.php
    /var/www/html/console loginldap:synchronize-users
    # /var/www/html/console plugin:activate LoginOIDC
  #fi
fi

# update matomo and set perms
/var/www/html/console core:update --yes -n
chown -R www-data /var/www/html

# run apache in the foreground
exec apache2-foreground
