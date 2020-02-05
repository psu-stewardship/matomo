FROM php:7.4.2-apache-buster

RUN set -ex; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	\
	apt-get update; \
	apt-get install -y --no-install-recommends \
		libfreetype6-dev \
		libjpeg-dev \
		libldap2-dev \
		libpng-dev \
		libzip-dev \
		git \
	; \
	\
	debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
	docker-php-ext-configure gd --with-freetype --with-jpeg; \
	docker-php-ext-configure ldap --with-libdir="lib/$debMultiarch"; \
	docker-php-ext-install -j "$(nproc)" \
		gd \
		ldap \
		mysqli \
		opcache \
		pdo_mysql \
		zip \
	; \
	\
# pecl will claim success even if one install fails, so we need to perform each install separately
	pecl install APCu-5.1.18; \
	pecl install redis-4.3.0; \
	\
	docker-php-ext-enable \
		apcu \
		redis \
	; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark; \
	ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
		| awk '/=>/ { print $3 }' \
		| sort -u \
		| xargs -r dpkg-query -S \
		| cut -d: -f1 \
		| sort -u \
		| xargs -rt apt-mark manual; \
	\
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf /var/lib/apt/lists/*


## Composer 
## Todo pin version 
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

ENV MATOMO_VERSION 3.13.1


COPY config/php.ini /usr/local/etc/php/conf.d/php-matomo.ini

RUN apt-get update && \
	apt-get -y install git mariadb-client && \
	git clone -b ${MATOMO_VERSION} --single-branch --depth 1 https://github.com/matomo-org/matomo.git /var/www/html && \
	rm -rf /var/lib/apt/lists/* 


# Adds packages required for extratools
RUN composer require symfony/yaml:~2.6.0 && \
	composer require symfony/process:^3.4 && \
	composer install && \
	rm -rf /var/www/html/.git


# Cleanup directories we don't need 
# RUN r
COPY plugins /var/www/html/plugins
COPY initialize.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/initialize.sh

CMD [ "/usr/local/bin/initialize.sh" ]
