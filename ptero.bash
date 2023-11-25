#Preconfig
URL=https://pterodactyl-oviedocraft.stableup.es
DOMAIN=pterodactyl-oviedocraft.stableup.es
TIMEZONE=Europe/Madrid

#Dependencias
apt update -y
apt -y install software-properties-common curl ca-certificates gnupg2 sudo lsb-release
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/sury-php.list
curl -fsSL  https://packages.sury.org/php/apt.gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/sury-keyring.gpg
curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list
apt update -y
apt install -y php8.1 php8.1-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip}
curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | sudo bash
apt install -y mariadb-server nginx tar unzip git redis-server

#Archivos Web
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 /var/www/pterodactyl

#BBDD
mysql -u root --execute="CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'YCrnnPfEYhQB';"
mysql -u root --execute="CREATE DATABASE panel;"
mysql -u root --execute="GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"

cp .env.example .env
composer install --no-dev --optimize-autoloader

#Importar Configuracion Predefinida
  # Generate encryption key
  php artisan key:generate --force

  # Fill in environment:setup automatically
  php artisan p:environment:setup \
    --author="pablo@stableup.es" \
    --url="$URL" \
    --timezone="$TIMEZONE" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="localhost" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true

  # Fill in environment:database credentials automatically
  php artisan p:environment:database \
    --host="127.0.0.1" \
    --port="3306" \
    --database="panel" \
    --username="pterodactyl" \
    --password="YCrnnPfEYhQB"

  # configures database
  php artisan migrate --seed --force

  # Create user account
  php artisan p:user:make \
    --email="pablo@stableup.es" \
    --username="root" \
    --name-first="Pablo" \
    --name-last="Plaza" \
    --password="CodigoLyoko-99" \
    --admin=1

#Dar Permisos a NGINX

chown -R www-data:www-data /var/www/pterodactyl/*

#Crontab Configuration

* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1

#Crear Service

echo "# Pterodactyl Queue Worker File
# ----------------------------------

[Unit]
Description=Pterodactyl Queue Worker
After=redis-server.service

[Service]
# On some systems the user and group might be different.
# Some systems use `apache` or `nginx` as the user and group.
User=www-data
Group=www-data
Restart=always
ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --queue=high,standard,low --sleep=3 --tries=3
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/pteroq.service

#Habilitar Servicios

sudo systemctl enable --now redis-server
sudo systemctl enable --now pteroq.service

#Instalar SSL

mkdir /var/ssl
cd /var/ssl
wget https://cdn.discordapp.com/attachments/1001188905443401882/1080806309475131465/STABLEUP_SSL-fullchain.zip
unzip STABLEUP_SSL-fullchain.zip


#Configurar NGINX

rm /etc/nginx/sites-enabled/default

echo 'server_tokens off;

server {
    listen 80;
    server_name pterodactyl-oviedocraft.stableup.es;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name pterodactyl-oviedocraft.stableup.es;

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # allow larger file uploads and longer script runtimes
    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    # SSL Configuration - Replace the example $DOMAIN with your domain
    ssl_certificate /var/ssl/certificado-fullchain.cer;
    ssl_certificate_key /var/ssl/stableup.key;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    # See https://hstspreload.org/ before uncommenting the line below.
    # add_header Strict-Transport-Security "max-age=15768000; preload;";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header Content-Security-Policy "frame-ancestors 'self'";
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy same-origin;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors off;
        fastcgi_buffer_size 16k;
        fastcgi_buffers 4 16k;
        fastcgi_connect_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_read_timeout 300;
        include /etc/nginx/fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
} 
' > /etc/nginx/sites-available/pterodactyl.conf

sudo ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf


sudo systemctl restart nginx


#Instalar Wings

curl -sSL https://get.docker.com/ | CHANNEL=stable bash

systemctl enable --now docker

GRUB_CMDLINE_LINUX_DEFAULT="swapaccount=1"

mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
chmod u+x /usr/local/bin/wings

#Crear servicio wings 

echo "[Unit]
Description=Pterodactyl Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pterodactyl
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/wings.service

systemctl enable --now wings