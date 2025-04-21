# LibreNMS Install script
#!/bin/bash

##### Check if sudo
if [[ "$EUID" -ne 0 ]]
  then echo "Please run as root"
  exit
fi

##### Start script
echo "###########################################################"
echo "Script para instalar LibreNMS usando NGINX para Ubuntu 20.04"
echo "###########################################################"
read -p "Please [Enter] to continue..." ignore

##### Installing Required Packages
apt install software-properties-common
LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/php
apt update
apt install acl curl fping git graphviz imagemagick mariadb-client mariadb-server mtr-tiny nginx-full nmap php-cli php-curl php-fpm php-gd php-gmp php-json php-mbstring php-mysql php-snmp php-xml php-zip rrdtool snmp snmpd unzip python3-pymysql python3-dotenv python3-redis python3-setuptools python3-psutil python3-systemd python3-pip whois traceroute
echo "Upgrading installed packages"
echo "###########################################################"

##### Add librenms user
echo "Add librenms user"
echo "###########################################################"
useradd librenms -d /opt/librenms -M -r -s "$(which bash)"

##### Download LibreNMS itself
echo "Downloading libreNMS to /opt/librenms"
echo "###########################################################"
cd /opt
git clone https://github.com/librenms/librenms.git


# Set permissions
echo "###########################################################"
chown -R librenms:librenms /opt/librenms
chmod 771 /opt/librenms
setfacl -d -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/
setfacl -R -m g::rwx /opt/librenms/rrd /opt/librenms/logs /opt/librenms/bootstrap/cache/ /opt/librenms/storage/

##### Install PHP dependencies
echo "Install PHP dependencies"
echo "###########################################################"
su librenms bash -c '/opt/librenms/scripts/composer_wrapper.php install --no-dev'

##### Set system timezone
echo "Setup of system and PHP timezone"
echo "###########################################################"
TZ= "America/Bogota"
sed -i "/;date.timezone =/ a date.timezone = $TZ" /etc/php/7.4/fpm/php.ini
sed -i "/;date.timezone =/ a date.timezone = $TZ" /etc/php/7.4/cli/php.ini

##### Configure MariaDB
echo "Configuring MariaDB"
echo "###########################################################"
##### Within the [mysqld] section of the config file please add: ####
## innodb_file_per_table=1
## lower_case_table_names=0
sed -i '/mysqld]/ a lower_case_table_names=0' /etc/mysql/mariadb.conf.d/50-server.cnf
sed -i '/mysqld]/ a innodb_file_per_table=1' /etc/mysql/mariadb.conf.d/50-server.cnf
# Enable & restart MariaDB
systemctl enable mariadb
systemctl restart mariadb

mysql -uroot -e "CREATE DATABASE librenms CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
mysql -uroot -e "CREATE USER 'librenms'@'localhost' IDENTIFIED BY 'password';"
mysql -uroot -e "GRANT ALL PRIVILEGES ON librenms.* TO 'librenms'@'localhost';"
mysql -uroot -e "FLUSH PRIVILEGES;"

##### Configure PHP-FPM
echo "Configure PHP-FPM (FastCGI Process Manager)"
echo "###########################################################"
cp /etc/php/7.4/fpm/pool.d/www.conf /etc/php/7.4/fpm/pool.d/librenms.conf
sed -i 's/^\[www\]/\[librenms\]/' /etc/php/7.4/fpm/pool.d/librenms.conf
sed -i 's/^user = www-data/user = librenms/' /etc/php/7.4/fpm/pool.d/librenms.conf
sed -i 's/^group = www-data/group = librenms/' /etc/php/7.4/fpm/pool.d/librenms.conf
sed -i 's/^listen =.*/listen = \/run\/php-fpm-librenms.sock/' /etc/php/7.4/fpm/pool.d/librenms.conf

##### Configure web server (NGINX
echo "Configure web server (NGINX)"
echo "###########################################################"
# Create NGINX .conf file
echo "Ingresar la ip del servidor [x.x.x.x o serv.examp.com]: "
read HOSTNAME
echo 'server {'> /etc/nginx/conf.d/librenms.conf
echo ' listen      80;' >>/etc/nginx/conf.d/librenms.conf
echo " server_name $HOSTNAME;" >>/etc/nginx/conf.d/librenms.conf
echo ' root        /opt/librenms/html;' >>/etc/nginx/conf.d/librenms.conf
echo ' index       index.php;' >>/etc/nginx/conf.d/librenms.conf
echo ' ' >>/etc/nginx/conf.d/librenms.conf
echo ' charset utf-8;' >>/etc/nginx/conf.d/librenms.conf
echo ' gzip on;' >>/etc/nginx/conf.d/librenms.conf
echo ' gzip_types text/css application/javascript text/javascript application/x-javascript image/svg+xml \
text/plain text/xsd text/xsl text/xml image/x-icon;' >>/etc/nginx/conf.d/librenms.conf
echo ' location / {' >>/etc/nginx/conf.d/librenms.conf
echo '  try_files $uri $uri/ /index.php?$query_string;' >>/etc/nginx/conf.d/librenms.conf
echo ' }' >>/etc/nginx/conf.d/librenms.conf
echo ' location ~ [^/]\.php(/|$) {' >>/etc/nginx/conf.d/librenms.conf
echo '  fastcgi_pass unix:/run/php-fpm-librenms.sock;' >>/etc/nginx/conf.d/librenms.conf
echo '  fastcgi_split_path_info ^(.+\.php)(/.+)$;' >>/etc/nginx/conf.d/librenms.conf
echo '  include fastcgi.conf;' >>/etc/nginx/conf.d/librenms.conf
echo ' }' >>/etc/nginx/conf.d/librenms.conf
echo ' location ~ /\.(?!well-known).* {' >>/etc/nginx/conf.d/librenms.conf
echo '  deny all;' >>/etc/nginx/conf.d/librenms.conf
echo ' }' >>/etc/nginx/conf.d/librenms.conf
echo '}' >>/etc/nginx/conf.d/librenms.conf
# remove the default site link
rm /etc/nginx/sites-enabled/default
systemctl restart nginx
systemctl restart php7.4-fpm

##### Enable lnms command completion
echo "Enable lnms command completion"
echo "###########################################################"
ln -s /opt/librenms/lnms /usr/local/bin/lnms
cp /opt/librenms/misc/lnms-completion.bash /etc/bash_completion.d/

##### Configure snmpd
echo "Configure snmpd"
cp /opt/librenms/snmpd.conf.example /etc/snmp/snmpd.conf
sed -i "s/RANDOMSTRINGGOESHERE/public/g" /etc/snmp/snmpd.conf

curl -o /usr/bin/distro https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/distro
chmod +x /usr/bin/distro
systemctl enable snmpd
systemctl restart snmpd

##### Cron job
echo "Setup LibreNMS Cron job"
echo "###########################################################"
cp /opt/librenms/librenms.nonroot.cron /etc/cron.d/librenms

### Scheduler
echo "Activando el Scheduler"
echo "###########################################################"
cp /opt/librenms/dist/librenms-scheduler.service /opt/librenms/dist/librenms-scheduler.timer /etc/systemd/system/
systemctl enable librenms-scheduler.timer
systemctl start librenms-scheduler.timer

##### Setup logrotate config
echo "Setup logrotate config"
echo "###########################################################"
cp /opt/librenms/misc/librenms.logrotate /etc/logrotate.d/librenms


##### Fin de la instalacion, continue en el navegador
echo "###############################################################################################"
echo "Navega en http://$HOSTNAME/install.php in you web browser to finish the installation."
echo "###############################################################################################"
