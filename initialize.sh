#!/bin/sh

# copy matomo code
set -e

if [ ! -e matomo.php ]; then
	tar cf - --one-file-system -C /usr/src/matomo . | tar xf -
	chown -R www-data .
fi

# wait for db to start
sleep 60

# start a temporary apache instance to run curl commands against
apachectl start

# run system check
curl -sS -o /dev/null -X POST -F "action=systemCheck" $MATOMO_INDEX

# create database and tables
curl -sS -o /dev/null  -X POST -F "action=databaseSetup" -F "module=Installation" -F "submit=submit" -F "type=$MATOMO_DATABASE_TYPE" -F "host=$MATOMO_DATABASE_HOST" -F "username=$MATOMO_DATABASE_USERNAME" -F "password=$MATOMO_DATABASE_PASSWORD" -F "dbname=$MATOMO_DATABASE_DBNAME" -F "tables_prefix=$MATOMO_DATABASE_TABLES_PREFIX" -F "adapter=$MATOMO_DATABASE_ADAPTER" $MATOMO_INDEX
curl -sS -o /dev/null  -X POST -F "action=tablesCreation" -F "module=Installation" -F "submit=submit" -F "host=$MATOMO_DATABASE_HOST" -F "username=$MATOMO_DATABASE_USERNAME" -F "password=$MATOMO_DATABASE_PASSWORD" -F "dbname=$MATOMO_DATABASE_DBNAME" $MATOMO_INDEX

# create super user
curl -sS -o /dev/null  -X POST -F "action=setupSuperUser" -F "module=Installation" -F "submit=submit" -F "login=$MATOMO_SUPERUSER_USERNAME" -F "password=$MATOMO_SUPERUSER_PASSWORD" -F "password_bis=$MATOMO_SUPERUSER_PASSWORD" -F "email=$MATOMO_SUPERUSER_EMAIL"  $MATOMO_INDEX

# name website
curl -sS -o /dev/null  -X POST -F "action=firstWebsiteSetup" -F "module=Installation" -F "submit=submit" -F "siteName=$MATOMO_SITENAME" -F "url=$MATOMO_URL" -F "timezone=$MATOMO_TIMEZONE" $MATOMO_INDEX

# create tracking code
curl -sS -o /dev/null  -X POST -F "action=trackingCode" -F "module=Installation" -F "submit=submit" -F "site_idSite=1" -F "site_name=$MATOMO_SITENAME" $MATOMO_INDEX

# finish up!
curl -sS -o /dev/null  -X POST -F "action=finished" -F "module=Installation" -F "submit=submit" -F "site_idSite=1" -F "site_name=$MATOMO_SITENAME" $MATOMO_INDEX

# activate plugins
/var/www/html/console plugin:activate LoginLdap
/var/www/html/console plugin:activate LoginOIDC
chown -R www-data /var/www/html/tmp/

# stop temporary apache
apachectl stop

# run apache in the foreground
exec apache2-foreground