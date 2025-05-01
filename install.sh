#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logo and Branding
clear
echo -e "${BLUE}"
cat << "EOF"
 _                                              
| |    ___   __ _ _ __ ___   __ _ _ __   __ _ ___
| |   / _ \ / _` | '_ ` _ \ / _` | '_ \ / _` / __|
| |__| (_) | (_| | | | | | | (_| | | | | (_| \__ \
|_____\___/ \__, |_| |_| |_|\__,_|_| |_|\__,_|___/
            |___/                                   
EOF
echo -e "${NC}"
echo -e "${CYAN}Pterodactyl Panel Installation Script${NC}"
echo -e "${YELLOW}Created by loqmanas${NC}\n"

# Function to check requirements
check_requirements() {
    echo -e "\n${PURPLE}➤ Checking system requirements...${NC}"
    
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}✗ Please run as root${NC}"
        exit 1
    fi
    
    if ! grep -q 'Debian' /etc/os-release; then
        echo -e "${RED}✗ This script only supports Debian systems${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ System requirements met${NC}"
}

# Function to configure database
setup_database() {
    echo -e "\n${PURPLE}➤ Database Configuration${NC}"
    
    read -p "Database Name [pterodactyl]: " DB_NAME
    DB_NAME=${DB_NAME:-pterodactyl}
    
    read -p "Database Username [ptero]: " DB_USER
    DB_USER=${DB_USER:-ptero}
    
    read -s -p "Database Password: " DB_PASS
    echo
    
    mysql -e "CREATE DATABASE ${DB_NAME};"
    mysql -e "CREATE USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -e "FLUSH PRIVILEGES;"
    
    # Create .env file
    cat > /var/www/pterodactyl/.env <<EOF
APP_URL=https://${DOMAIN}
APP_TIMEZONE=UTC
APP_SERVICE_AUTHOR=noreply@example.com
APP_ENVIRONMENT_ONLY=false

DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}

CACHE_DRIVER=file
SESSION_DRIVER=file
QUEUE_CONNECTION=database

MAIL_MAILER=smtp
MAIL_HOST=localhost
MAIL_PORT=25
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=null
MAIL_FROM_ADDRESS=noreply@example.com
MAIL_FROM_NAME="Pterodactyl Panel"
EOF
    
    echo -e "${GREEN}✓ Database configured successfully${NC}"
}

# Function to setup SSL
setup_ssl() {
    echo -e "\n${PURPLE}➤ SSL Configuration${NC}"
    
    read -p "Domain name (e.g., panel.domain.com): " DOMAIN
    
    # Install certbot
    apt install -y certbot python3-certbot-nginx
    
    # Configure Nginx
    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    root /var/www/pterodactyl/public;
    index index.php;

    access_log /var/log/nginx/pterodactyl.app-access.log;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384";
    ssl_prefer_server_ciphers on;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param PHP_VALUE "upload_max_filesize = 100M \n post_max_size=100M";
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
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
EOF

    ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Get SSL certificate
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
    
    systemctl restart nginx
    
    echo -e "${GREEN}✓ SSL certificate installed${NC}"
}

# Function to setup admin account
setup_admin() {
    echo -e "\n${PURPLE}➤ Admin Account Setup${NC}"
    
    read -p "Admin Username: " ADMIN_USER
    read -p "Admin Email: " ADMIN_EMAIL
    read -s -p "Admin Password (min 8 characters): " ADMIN_PASS
    echo
    
    cd /var/www/pterodactyl
    php artisan p:user:make \
        --email="$ADMIN_EMAIL" \
        --username="$ADMIN_USER" \
        --name-first="Admin" \
        --name-last="User" \
        --password="$ADMIN_PASS" \
        --admin=1
    
    echo -e "${GREEN}✓ Admin account created successfully${NC}"
}

# Main installation function
install_panel() {
    echo -e "\n${PURPLE}➤ Installing Pterodactyl Panel...${NC}"
    
    # Update system
    apt update && apt upgrade -y
    
    # Install dependencies
    apt install -y software-properties-common curl apt-transport-https ca-certificates gnupg
    
    # Install PHP 8.1
    curl -sSL https://packages.sury.org/php/apt.gpg -o /etc/apt/trusted.gpg.d/php.gpg
    echo "deb https://packages.sury.org/php/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/php.list
    apt update
    apt install -y php8.1 php8.1-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip}
    
    # Install Composer
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    
    # Install MariaDB
    apt install -y mariadb-server
    
    # Install Nginx
    apt install -y nginx
    
    # Download and install panel
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    
    # Install dependencies
    composer install --no-dev --optimize-autoloader
    
    # Generate key and setup database
    php artisan key:generate --force
    php artisan migrate --seed --force
    
    # Set permissions
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    echo -e "${GREEN}✓ Panel base installation complete${NC}"
}

# Function to install theme
install_theme() {
    echo -e "\n${PURPLE}➤ Installing Custom Theme...${NC}"
    
    cd /var/www/pterodactyl
    
    # Copy theme files
    cp -r admin/admin.style.css public/themes/
    cp -r client/client.style.css public/themes/
    
    # Update panel configuration
    php artisan config:cache
    php artisan view:cache
    
    echo -e "${GREEN}✓ Theme installed successfully${NC}"
}

# Main menu
while true; do
    echo -e "\n${CYAN}Please select an installation option:${NC}"
    echo "1) Install Pterodactyl Panel"
    echo "2) Install Panel with Custom Theme"
    echo "3) Exit"
    
    read -p "Enter choice [1-3]: " choice
    
    case $choice in
        1)
            check_requirements
            install_panel
            setup_database
            setup_ssl
            setup_admin
            echo -e "\n${GREEN}✓ Pterodactyl Panel installation completed!${NC}"
            echo -e "${YELLOW}Panel is now accessible at: https://${DOMAIN}${NC}"
            break
            ;;
        2)
            check_requirements
            install_panel
            setup_database
            setup_ssl
            install_theme
            setup_admin
            echo -e "\n${GREEN}✓ Pterodactyl Panel and Theme installation completed!${NC}"
            echo -e "${YELLOW}Panel is now accessible at: https://${DOMAIN}${NC}"
            break
            ;;
        3)
            echo -e "\n${GREEN}Thank you for using loqmanas's Pterodactyl installer!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}Invalid option${NC}"
            ;;
    esac
done
