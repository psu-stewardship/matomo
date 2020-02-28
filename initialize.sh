#!/bin/bash

set -e


# wait for database connection
echo " "
echo " ============================= WAITING FOR DATABASE CONNECTION ============================= "
echo " "

if ! timeout 120 bash -c 'until printf "" 2>>/dev/null >>/dev/tcp/$0/$1; do sleep 1; done' "${MATOMO_DB_HOST:-localhost}" "3306"
then
  echo " "
  echo " ============================= NO DATABASE CONNECTION TIMED OUT, EXITING ============================= "
  echo " "
  exit 1
fi

# check if matomo is installed
echo " "
echo " ============================= ENABLING PREVIOUS INSTALLATION ============================= "
echo " "

# link to config
if [ -d /usr/local/matomo/config ] ; then
  if [ -d /var/www/html/config ] ; then
    rm -R /var/www/html/config
  fi
  ln -s /usr/local/matomo/config /var/www/html/config
fi

# link to plugins
if [ -d /usr/local/matomo/ExtraTools ] ; then
  if [ -d /var/www/html/plugins/ExtraTools ] ; then
    rm -R /var/www/html/plugins/ExtraTools
  fi
  ln -s /usr/local/matomo/ExtraTools /var/www/html/plugins/ExtraTools
fi

if [ -d /usr/local/matomo/LoginLdap ] ; then
  if [ -d /var/www/html/plugins/LoginLdap ] ; then
    rm -R /var/www/html/plugins/LoginLdap
  fi
  ln -s /usr/local/matomo/LoginLdap /var/www/html/plugins/LoginLdap
fi

if [ -d /usr/local/matomo/LoginOIDC ] ; then
  if [ -d /var/www/html/plugins/LoginOIDC ] ; then
    rm -R /var/www/html/plugins/LoginOIDC
  fi
  ln -s /usr/local/matomo/LoginOIDC /var/www/html/plugins/LoginOIDC
fi

if [ ! -L /etc/apache2/conf-enabled/rewrite.conf ] ; then
  ln -s /usr/local/apache2/rewrite.conf /etc/apache2/conf-enabled/rewrite.conf
  a2enmod rewrite
fi


# exec apache2-foreground

# check if matomo is installed
if bash -c '/var/www/html/console -q site:list' >> /dev/null
then

  echo " "
  echo " ============================= MATOMO ALREADY INSTALLED ============================= "
  echo " "

else

  # install plugins
  echo " "
  echo " ============================= INSTALLING MATOMO ============================= "
  echo " "

  if [ -d /var/www/html/config ] ; then
    mv /var/www/html/config /usr/local/matomo/
    ln -s /usr/local/matomo/config /var/www/html/config
  fi

  mv /tmp/ExtraTools /usr/local/matomo/
  mv /tmp/LoginLdap /usr/local/matomo/
  mv /tmp/LoginOIDC /usr/local/matomo/
  chown -R www-data /usr/local/matomo/

  if [ -d /var/www/html/plugins/ExtraTools ] ; then
    rm -R /var/www/html/plugins/ExtraTools
  fi
  ln -s /usr/local/matomo/ExtraTools /var/www/html/plugins/ExtraTools

  if [ -d /var/www/html/plugins/LoginLdap ] ; then
    rm -R /var/www/html/plugins/LoginLdap
  fi
  ln -s /usr/local/matomo/LoginLdap /var/www/html/plugins/LoginLdap

  if [ -d /var/www/html/plugins/LoginOIDC ] ; then
    rm -R /var/www/html/plugins/LoginOIDC
  fi
  ln -s /usr/local/matomo/LoginOIDC /var/www/html/plugins/LoginOIDC


  # use extra tools plugin to install matomo
  echo " "
  echo " ============================= ENABLING EXTRA TOOLS PLUGIN ============================= "
  echo " "

  /var/www/html/console plugin:activate ExtraTools
  /var/www/html/console matomo:install --force
  chown -R www-data /var/www/html/config/


  # import current database
  echo " "
  echo " ============================= IMPORTING THE EXISTING DATABASE ============================= "
  echo " "

  echo "DROP DATABASE matomo; CREATE DATABASE matomo" | /usr/bin/mysql --password="${MATOMO_DB_PASSWORD}" -u "${MATOMO_DB_USERNAME}" -h "${MATOMO_DB_HOST}"
  sed -i '/dbname/ a tables_prefix = \"matomo_\"' /var/www/html/config/config.ini.php
  /var/www/html/console database:import -b /tmp/matomo.sql


  # enable and conigure LoginLdap plugin
  echo " "
  echo " ============================= ENABLING LOGIN LDAP PLUGIN ============================= "
  echo " "

  /var/www/html/console plugin:activate LoginLdap
  cat /tmp/LoginLdap.conf >> /var/www/html/config/config.ini.php


  # enable and conigure LoginOIDC plugin
  echo " "
  echo " ============================= ENABLING LOGIN OIDC PLUGIN ============================= "
  echo " "

  /var/www/html/console plugin:activate LoginOIDC

  echo " "
  echo " ============================= CONFIGURING LOGIN OIDC ============================= "
  echo " "
  echo "INSERT INTO matomo_plugin_setting (plugin_name, setting_name, setting_value, json_encoded, user_login) VALUES ('LoginOIDC','disableSuperuser','1',0,''),('LoginOIDC','allowSignup','1',0,''),('LoginOIDC','authenticationName','OAuth login',0,''),('LoginOIDC','authorizeUrl','${LOGIN_OIDC_AUTHORIZE}',0,''),('LoginOIDC','tokenUrl','${LOGIN_OIDC_TOKEN}',0,''),('LoginOIDC','userinfoUrl','${LOGIN_OIDC_USERINFO}',0,''),('LoginOIDC','userinfoId','sub',0,''),('LoginOIDC','clientId','${LOGIN_OIDC_CLIENT_ID}',0,''),('LoginOIDC','clientSecret','${LOGIN_OIDC_CLIENT_SECRET}',0,''),('LoginOIDC','scope','openid email profile groups',0,''),('LoginOIDC','redirectUriOverride','${LOGIN_OIDC_CALLBACK}',0,'');" | /usr/bin/mysql --password="${MATOMO_DB_PASSWORD}" -u "${MATOMO_DB_USERNAME}" -h "${MATOMO_DB_HOST}" "${MATOMO_DB_NAME}"


  # link users to OAuth
  echo " "
  echo " ============================= LINKING USERS TO OAUTH ============================= "
  echo " "

  date=$(date +'%Y-%m-%d %H:%M:%S')
  USERLIST=$(echo "SELECT login from matomo_user" | /usr/bin/mysql --password="${MATOMO_DB_PASSWORD}" -u "${MATOMO_DB_USERNAME}" -h "${MATOMO_DB_HOST}" "${MATOMO_DB_NAME}")
  for user in $USERLIST
  do
    echo "USER: $user"
    if [ $user == 'login' ] || [ $user == 'anonymous' ] ; then
      echo "SKIPPING USER: $user"
      continue
    fi
    echo "INSERT INTO matomo_loginoidc_provider (user, provider_user, provider, date_connected) VALUES ('$user', '$user', 'oidc', '$date');" | /usr/bin/mysql --password="${MATOMO_DB_PASSWORD}" -u "${MATOMO_DB_USERNAME}" -h "${MATOMO_DB_HOST}" "${MATOMO_DB_NAME}"
  done


  # enable apache rewrite
  echo " "
  echo " ============================= ENABLING APACHE REWRITE ============================= "
  echo " "

  cp /tmp/rewrite.conf /usr/local/apache2/
  if [ ! -L /etc/apache2/conf-enabled/rewrite.conf ] ; then
    ln -s /usr/local/apache2/rewrite.conf /etc/apache2/conf-enabled/rewrite.conf
  fi
  a2enmod rewrite

fi


# update matomo and set web perms
echo " "
echo " ============================= UPDATING MATOMO ============================= "
echo " "

/var/www/html/console core:update --yes -n
chown -R www-data /var/www/html/tmp/ /var/www/html/vendor/


# synchronize ldap users
echo " "
echo " ============================= SYNCHRONIZING LDAP USERS ============================= "
echo " "

/var/www/html/console -n loginldap:synchronize-users || true


# run apache in the foreground
echo " "
echo " ============================= STARTING APACHE ============================= "
echo " "

exec apache2-foreground
