#!/bin/bash

# -----------------------
# CONFIGURACIÓN BÁSICA
# -----------------------
set -e

# Configura tu contraseña de root para MySQL/MariaDB aquí si no tienes autenticación por socket
MYSQL_ROOT_PASSWORD='password'
DB_PASSWORD='password'
DB_NAME='librenms'
DB_USER='librenms'

PHP_VERSION="8.1"
TIMEZONE="America/Bogota"

# -----------------------
# VERIFICAR DEPENDENCIAS
# -----------------------
echo "==> Verificando dependencias..."

apt update && apt install -y \
    nginx \
    mariadb-server \
    php${PHP_VERSION} php${PHP_VERSION}-cli php${PHP_VERSION}-fpm php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-mbstring php${PHP_VERSION}-xml php${PHP_VERSION}-curl \
    php${PHP_VERSION}-gd php${PHP_VERSION}-zip php${PHP_VERSION}-snmp php${PHP_VERSION}-bcmath \
    snmp composer git unzip curl fping rrdtool whois python3-pymysql python3-dotenv python3-pip

# -----------------------
# CONFIGURAR PHP TIMEZONE
# -----------------------
echo "==> Configurando timezone PHP..."
for ini in /etc/php/${PHP_VERSION}/*/php.ini; do
    if grep -q "^;date.timezone" "$ini"; then
        sed -i "s|^;date.timezone =.*|date.timezone = ${TIMEZONE}|" "$ini"
    elif ! grep -q "^date.timezone" "$ini"; then
        echo "date.timezone = ${TIMEZONE}" >> "$ini"
    fi
done

# -----------------------
# CONFIGURAR BASE DE DATOS
# -----------------------
echo "==> Configurando base de datos..."

mysql -u root -p${MYSQL_ROOT_PASSWORD} <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8 COLLATE utf8_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

# -----------------------
# CREAR USUARIO LIBRENMS
# -----------------------
echo "==> Creando usuario librenms..."
useradd librenms -d /opt/librenms -M -r -s /bin/bash || true

# -----------------------
# CLONAR LIBRENMS
# -----------------------
echo "==> Clonando LibreNMS..."
cd /opt
if [ ! -d /opt/librenms ]; then
    git clone https://github.com/librenms/librenms.git
    chown -R librenms:librenms /opt/librenms
else
    echo "⚠️ /opt/librenms ya existe. No se clona de nuevo."
fi

# -----------------------
# INSTALAR DEPENDENCIAS PHP CON COMPOSER
# -----------------------
echo "==> Instalando dependencias con Composer..."
cd /opt/librenms
sudo -u librenms composer install --no-dev

# -----------------------
# CONFIGURAR PERMISOS
# -----------------------
echo "==> Configurando permisos..."
chown -R librenms:librenms /opt/librenms
chmod 770 /opt/librenms

# -----------------------
# CONFIGURAR NGINX
# -----------------------
echo "==> Configurando NGINX..."
cp /opt/librenms/dist/librenms.nginx.conf /etc/nginx/sites-available/librenms.conf
ln -sf /etc/nginx/sites-available/librenms.conf /etc/nginx/sites-enabled/librenms.conf
rm -f /etc/nginx/sites-enabled/default

systemctl enable nginx
systemctl restart nginx

# -----------------------
# CONFIGURAR PHP-FPM
# -----------------------
echo "==> Configurando PHP-FPM..."
cat > /etc/php/${PHP_VERSION}/fpm/pool.d/librenms.conf <<EOL
[librenms]
user = librenms
group = librenms
listen = /run/php-fpm-librenms.sock
listen.owner = librenms
listen.group = librenms
pm = dynamic
pm.max_children = 5
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
chdir = /
EOL

systemctl enable php${PHP_VERSION}-fpm
systemctl restart php${PHP_VERSION}-fpm

# -----------------------
# CONFIGURAR SNMPD
# -----------------------
echo "==> Configurando SNMP..."
cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf
sed -i "s/RANDOMSTRINGGOESHERE/public/" /etc/snmp/snmpd.conf
systemctl enable snmpd
systemctl restart snmpd

# -----------------------
# CRON Y LOGROTATE
# -----------------------
echo "==> Configurando cron y logrotate..."
cp /opt/librenms/librenms.nonroot.cron /etc/cron.d/librenms
cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms

# -----------------------
# TERMINADO
# -----------------------
echo "✅ Instalación base de LibreNMS finalizada. Accede desde tu navegador a http://<tu_ip> para continuar la configuración web."
