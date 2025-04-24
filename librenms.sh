#!/bin/bash
set -e

##### Check if sudo
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

##### Start script
echo "###########################################################"
echo "Script para instalar LibreNMS usando NGINX para Ubuntu 20.04"
echo "###########################################################"
read -p "Presione [Enter] para continuar..." ignore

##### Installing Required Packages
apt update
apt install -y software-properties-common acl curl fping git graphviz imagemagick \
mariadb-client mariadb-server mtr-tiny nginx-full nmap \
php-cli php-curl php-fpm php-gd php-gmp php-json php-mbstring \
php-mysql php-snmp php-xml php-zip rrdtool snmp snmpd unzip \
python3-pymysql python3-dotenv python3-redis python3-setuptools \
python3-psutil python3-systemd python3-pip whois traceroute

LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
apt update
echo "Actualizando paquetes instalados"
apt upgrade -y

##### Add librenms user
useradd librenms -d /opt/librenms -M -r -s /bin/bash

##### Download LibreNMS
cd /opt
git clone https://github.com/librenms/librenms.git
chown -R librenms:librenms /opt/librenms
chmod 771 /opt/librenms
setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache /opt/librenms/storage
setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache /opt/librenms/storage

##### Install PHP dependencies
su - librenms -c '/opt/librenms/scripts/composer_wrapper.php install --no-dev'

##### Set timezone
echo "Configurando timezone"
TZ="America/Bogota"
sed -i "s|;date.timezone =|date.timezone = $TZ|g" /etc/php/7.4/fpm/php.ini
sed -i "s|;date.timezone =|date.timezone = $TZ|g" /etc/php/7.4/cli/php.ini

##### Configure MariaDB
echo "Configurando MariaDB"
sed -i '/\[mysqld\]/a innodb_file_per_table=1\nlower_case_table_names=0' /etc/mysql/mariadb.conf.d/50-server.cnf
systemctl enable mariadb
systemctl restart mariadb

mysql -uroot <<EOF
CREATE DATABASE librenms CHARACTER SET utf8 COLLATE utf8_unicode_ci;
CREATE USER 'librenms'@'localhost' IDENTIFIED BY 'password';
GRANT ALL PRIVILEGES ON librenms.* TO 'librenms'@'localhost';
FLUSH PRIVILEGES;
EOF

##### Configure PHP-FPM
cp /etc/php/7.4/fpm/pool.d/www.conf /etc/php/7.4/fpm/pool.d/librenms.conf
sed -i 's/^\[www\]/[librenms]/' /etc/php/7.4/fpm/pool.d/librenms.conf
sed -i 's/^user = www-data/user = librenms/' /etc/php/7.4/fpm/pool.d/librenms.conf
sed -i 's/^group = www-data/group = librenms/' /etc/php/7.4/fpm/pool.d/librenms.conf
sed -i 's|^listen =.*|listen = /run/php-fpm-librenms.sock|' /etc/php/7.4/fpm/pool.d/librenms.conf

##### Configure NGINX
echo -n "Ingrese la IP o dominio del servidor [x.x.x.x o servidor.com]: "
read HOSTNAME

cat <<EOF > /etc/nginx/conf.d/librenms.conf
server {
    listen      80;
    server_name $HOSTNAME;
    root        /opt/librenms/html;
    index       index.php;
    charset utf-8;

    gzip on;
    gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml text/plain text/xsd text/xsl text/xml image/x-icon;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ [^/]\.php(/|$) {
        fastcgi_pass unix:/run/php-fpm-librenms.sock;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        include fastcgi.conf;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx
systemctl restart php7.4-fpm

##### Enable lnms CLI
ln -sf /opt/librenms/lnms /usr/local/bin/lnms
cp /opt/librenms/misc/lnms-completion.bash /etc/bash_completion.d/

##### Configure SNMP
cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf
sed -i "s/RANDOMSTRINGGOESHERE/public/" /etc/snmp/snmpd.conf
curl -o /usr/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
chmod +x /usr/bin/distro
systemctl enable snmpd
systemctl restart snmpd

##### Set up cron
cp /opt/librenms/librenms.nonroot.cron /etc/cron.d/librenms

##### Scheduler
cp /opt/librenms/dist/librenms-scheduler.service /opt/librenms/dist/librenms-scheduler.timer /etc/systemd/system/
systemctl enable librenms-scheduler.timer
systemctl start librenms-scheduler.timer

##### Logrotate
cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms

##### Final Message
echo "###############################################################################################"
echo "Instalación básica completa. Abre http://$HOSTNAME/install.php en tu navegador para finalizar."
echo "###############################################################################################"
