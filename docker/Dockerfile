# Imagen de pruebas de FacturaScripts: PHP (CLI) con las extensiones que necesita el core,
# más Composer y las herramientas que usan los scripts (git, unzip, rsync, curl).
# La versión de PHP se elige con el argumento PHP_VERSION (8.1, 8.2, 8.3, 8.4 u 8.5).
ARG PHP_VERSION=8.3
FROM php:${PHP_VERSION}-cli

# Dependencias del sistema y extensiones PHP (MySQL/MariaDB y PostgreSQL)
RUN apt-get update && \
	apt-get install -y --no-install-recommends libfreetype6-dev libgmp-dev libicu-dev libjpeg62-turbo-dev \
		libpng-dev libpq-dev libxml2-dev libzip-dev git unzip rsync curl ca-certificates && \
	apt-get clean && rm -rf /var/lib/apt/lists/* && \
	docker-php-ext-configure gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/ && \
	docker-php-ext-install bcmath gd gmp intl mysqli pdo pdo_mysql pgsql pdo_pgsql soap zip

# Composer, para instalar las dependencias del core y de los plugins dentro del contenedor
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Configuración PHP propia
COPY custom.ini $PHP_INI_DIR/conf.d/

# Caché de Composer compartida entre todas las versiones de PHP
ENV COMPOSER_CACHE_DIR=/cache/composer COMPOSER_ALLOW_SUPERUSER=1

WORKDIR /var/www/html
