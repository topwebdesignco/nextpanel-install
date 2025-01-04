#!/bin/bash

# Function to check and remove a package
remove_package() {
    PACKAGE=$1
    echo "Checking if $PACKAGE is installed..."

    # Check if package is installed
    if dpkg -l | grep -q "$PACKAGE"; then
        echo "$PACKAGE is installed, removing it..."
        sudo systemctl stop "$PACKAGE" 2>/dev/null
        sudo systemctl disable "$PACKAGE" 2>/dev/null
        sudo apt-get purge --auto-remove "$PACKAGE" -y
        sudo rm -rf /etc/"$PACKAGE" /var/log/"$PACKAGE" /var/lib/"$PACKAGE"
        echo "$PACKAGE has been removed."
    else
        echo "$PACKAGE is not installed."
    fi
}

# Function to check and remove a directory
remove_directory() {
    DIR=$1
    if [ -d "$DIR" ]; then
        echo "Removing directory $DIR..."
        sudo rm -rf "$DIR"
        echo "$DIR has been removed."
    else
        echo "$DIR does not exist."
    fi
}

# Update and Upgrade System
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

# Remove Nginx if it exists
remove_package "nginx"

# Remove MariaDB if it exists
remove_package "mariadb-server"
remove_package "mariadb-client"

# Remove PHP if it exists
remove_package "php8.2"
remove_package "php8.2-fpm"
remove_package "php8.2-cli"
remove_package "php8.2-mysql"
remove_package "php8.2-common"
remove_package "php8.2-xml"
remove_package "php8.2-mbstring"
remove_package "php8.2-curl"
remove_package "php8.2-zip"

# Remove Composer if it exists
if [ -f /usr/local/bin/composer ]; then
    echo "Removing Composer..."
    sudo rm /usr/local/bin/composer
    echo "Composer has been removed."
else
    echo "Composer is not installed."
fi

# Remove NextPanel directory if it exists
remove_directory "/var/www/nextpanel"

# Install Nginx
echo "Installing Nginx..."
sudo apt install nginx -y
sudo systemctl enable nginx
sudo systemctl start nginx
sudo ufw allow 'Nginx Full'

# Install MariaDB
echo "Installing MariaDB..."
sudo apt install mariadb-server mariadb-client -y
sudo systemctl enable mariadb
sudo systemctl start mariadb

# Wait until MariaDB is running and the socket file exists
echo "Waiting for MariaDB to start..."
MAX_RETRIES=3
RETRY_COUNT=0
MYSQLEDIT_SOCKET_PATH="/var/run/mysqld/mysqld.sock"

while [[ ! -e $MYSQLEDIT_SOCKET_PATH && $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    echo "MariaDB not yet ready, retrying..."
    sudo systemctl restart mariadb
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 5
done

# If MariaDB still isn't ready after retries, exit the script with an error
if [[ ! -e $MYSQLEDIT_SOCKET_PATH ]]; then
    echo "MariaDB failed to start properly. Exiting."
    exit 1
fi

# Secure MariaDB
echo "Securing MariaDB..."

MYSQL_ROOT_PASSWORD="rootsecret"
sudo mysql -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${MYSQL_ROOT_PASSWORD}');"
sudo mysql -u root -p${MYSQL_ROOT_PASSWORD} <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

echo "MariaDB secured successfully!"

# Add PHP Repository
echo "Adding PHP repository..."
sudo add-apt-repository ppa:ondrej/php -y
sudo apt update

# Install PHP
echo "Installing PHP 8.2 and extensions..."
sudo apt install php8.2 php8.2-fpm php8.2-cli php8.2-mysql php8.2-common php8.2-xml php8.2-mbstring php8.2-curl php8.2-zip unzip -y
sudo systemctl enable php8.2-fpm
sudo systemctl start php8.2-fpm

# Install Composer
echo "Installing Composer..."
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer

# Install NextPanel
echo "Installing NextPanel..."
sudo mkdir -p /var/www/nextpanel
cd /var/www/
sudo composer create-project --no-interaction laravel/laravel nextpanel

# Set Permissions
echo "Setting permissions..."
sudo chown -R www-data:www-data /var/www/nextpanel
sudo chmod -R 775 /var/www/nextpanel/storage
sudo chmod -R 775 /var/www/nextpanel/bootstrap/cache

# Configure Nginx for NextPanel on Port 1947
echo "Configuring Nginx for NextPanel on port 1947..."
sudo tee /etc/nginx/sites-available/nextpanel <<EOL
server {
    listen 1947;
    server_name _;  # You can replace _ with your domain name or IP address

    root /var/www/nextpanel/public;

    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOL

# Enable NextPanel Site
echo "Enabling NextPanel site..."
sudo ln -s /etc/nginx/sites-available/nextpanel /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx

# Database Setup
echo "Configuring database..."
sudo mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE DATABASE nextpanel;"
sudo mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "CREATE USER 'nextpanel'@'localhost' IDENTIFIED BY 'nextpanelsecret';"
sudo mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "GRANT ALL PRIVILEGES ON nextpanel.* TO 'nextpanel'@'localhost';"
sudo mysql -u root -p${MYSQL_ROOT_PASSWORD} -e "FLUSH PRIVILEGES;"

# NextPanel Laravel Configuration
SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_TIMEZONE=$(timedatectl show --property=Timezone --value)

echo "Configuring NextPanel..."
cd /var/www/nextpanel
cp .env.example .env
sed -i "s/APP_NAME=.*/APP_NAME=Nextpanel/" .env
sed -i "s/APP_DEBUG=.*/APP_DEBUG=false/" .env
sed -i "s/APP_TIMEZONE=.*/APP_TIMEZONE=${SERVER_TIMEZONE}/" .env
sed -i "s/APP_URL=.*/APP_URL=http://$SERVER_IP/" .env
sed -i "s/DB_CONNECTION=.*/DB_CONNECTION=mysql/" .env
sed -i "s/# DB_HOST=.*/DB_HOST=127.0.0.1/" .env
sed -i "s/# DB_PORT=.*/DB_PORT=3306/" .env
sed -i "s/# DB_DATABASE=.*/DB_DATABASE=nextpanel/" .env
sed -i "s/# DB_USERNAME=.*/DB_USERNAME=nextpanel/" .env
sed -i "s/# DB_PASSWORD=.*/DB_PASSWORD=nextpanelsecret/" .env

php artisan key:generate
php artisan migrate

# Finalize Setup
echo "NextPanel setup complete!"
echo -e "Access Nextpanel at: \033[1;34mhttp://$SERVER_IP:1947\033[0m"
echo -e "Tip: Hold Ctrl and click the link to open it!"
