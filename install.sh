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

# Function to install PHP 8.2
install_php() {
    echo -e "\n${PURPLE}➤ Installing PHP 8.2...${NC}"
    
    # Add Sury PHP repository
    apt -y install lsb-release ca-certificates apt-transport-https software-properties-common
    curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
    echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list
    
    apt update
    apt install -y php8.2 php8.2-{cli,common,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip,intl}
    
    # Update alternatives to use PHP 8.2
    update-alternatives --set php /usr/bin/php8.2
    
    echo -e "${GREEN}✓ PHP 8.2 installed successfully${NC}"
}

# Function to configure database
setup_database() {
    echo -e "\n${PURPLE}➤ Database Configuration${NC}"
    
    DB_NAME="pterodactyl"
    DB_USER="pterodactyl"
    DB_PASS=$(openssl rand -base64 32)
    
    # Install MariaDB if not installed
    if ! command -v mysql &> /dev/null; then
        apt install -y mariadb-server
        systemctl enable --now mariadb
    fi
    
    # Secure MariaDB installation
    mysql_secure_installation <<EOF

y
y
y
y
y
EOF
    
    # Create database and user
    mysql -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};"
    mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -e "FLUSH PRIVILEGES;"
    
    echo -e "${GREEN}✓ Database configured successfully${NC}"
}

# Function to install panel
install_panel() {
    echo -e "\n${PURPLE}➤ Installing Pterodactyl Panel...${NC}"
    
    # Install dependencies
    apt update && apt upgrade -y
    apt install -y nginx tar unzip git curl
    
    # Install composer
    if ! command -v composer &> /dev/null; then
        curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    fi
    
    # Download panel files
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage/* bootstrap/cache/
    
    # Install composer dependencies
    composer install --no-dev --optimize-autoloader
    
    # Copy environment file
    cp .env.example .env
    
    # Generate application key
    php artisan key:generate --force
    
    # Create storage link
    php artisan storage:link
    
    # Set permissions
    chown -R www-data:www-data /var/www/pterodactyl/*
    
    echo -e "${GREEN}✓ Panel installed successfully${NC}"
}

# Function to configure Nginx
setup_nginx() {
    echo -e "\n${PURPLE}➤ Configuring Nginx...${NC}"
    
    read -p "Enter domain name (e.g., panel.domain.com): " DOMAIN
    
    # Create Nginx config
    cat > /etc/nginx/sites-available/pterodactyl.conf <<EOF
server {
    listen 80;
    server_name ${DOMAIN};
    root /var/www/pterodactyl/public;
    index index.html index.htm index.php;
    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    access_log off;
    error_log  /var/log/nginx/pterodactyl.app-error.log error;

    client_max_body_size 100m;
    client_body_timeout 120s;

    sendfile off;

    location ~ \.php$ {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
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
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
    
    # Enable site and remove default
    ln -sf /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/
    rm -f /etc/nginx/sites-enabled/default
    
    # Test and reload Nginx
    nginx -t && systemctl restart nginx
    
    echo -e "${GREEN}✓ Nginx configured successfully${NC}"
}

# Function to setup SSL with Certbot
setup_ssl() {
    echo -e "\n${PURPLE}➤ Setting up SSL...${NC}"
    
    # Install certbot
    apt install -y certbot python3-certbot-nginx
    
    # Obtain and install certificate
    certbot --nginx --non-interactive --agree-tos --redirect --email admin@${DOMAIN} -d ${DOMAIN}
    
    echo -e "${GREEN}✓ SSL certificate installed successfully${NC}"
}

# Function to setup admin account
setup_admin() {
    echo -e "\n${PURPLE}➤ Creating admin account...${NC}"
    
    read -p "Admin email: " ADMIN_EMAIL
    read -p "Admin username: " ADMIN_USER
    read -s -p "Admin password (min 8 chars): " ADMIN_PASS
    echo
    
    php artisan p:user:make \
        --email="$ADMIN_EMAIL" \
        --username="$ADMIN_USER" \
        --name-first="Admin" \
        --name-last="User" \
        --password="$ADMIN_PASS" \
        --admin=1
    
    echo -e "${GREEN}✓ Admin account created successfully${NC}"
}

# Function to remove panel
remove_panel() {
    echo -e "\n${RED}➤ WARNING: This will completely remove Pterodactyl Panel!${NC}"
    read -p "Are you sure you want to continue? (y/N): " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "\n${PURPLE}➤ Removing Pterodactyl Panel...${NC}"
        
        # Stop services
        systemctl stop nginx
        systemctl stop php8.2-fpm
        
        # Remove files
        rm -rf /var/www/pterodactyl
        rm -f /etc/nginx/sites-enabled/pterodactyl.conf
        rm -f /etc/nginx/sites-available/pterodactyl.conf
        
        # Remove SSL certificates
        certbot delete --cert-name ${DOMAIN} --non-interactive
        
        # Remove database
        mysql -e "DROP DATABASE IF EXISTS pterodactyl;"
        mysql -e "DROP USER IF EXISTS 'pterodactyl'@'127.0.0.1';"
        
        # Restart services
        systemctl restart nginx
        
        echo -e "${GREEN}✓ Pterodactyl Panel removed successfully${NC}"
    else
        echo -e "${YELLOW}Operation cancelled${NC}"
    fi
}

# Main menu
while true; do
    echo -e "\n${CYAN}Please select an option:${NC}"
    echo "1) Install Pterodactyl Panel"
    echo "2) Remove Pterodactyl Panel"
    echo "3) Exit"
    
    read -p "Enter choice [1-3]: " choice
    
    case $choice in
        1)
            check_requirements
            install_php
            setup_database
            install_panel
            setup_nginx
            setup_ssl
            setup_admin
            echo -e "\n${GREEN}✓ Pterodactyl Panel installation completed!${NC}"
            echo -e "${YELLOW}Panel is now accessible at: https://${DOMAIN}${NC}"
            break
            ;;
        2)
            remove_panel
            break
            ;;
        3)
            echo -e "\n${GREEN}Thank you for using the installer!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}Invalid option${NC}"
            ;;
    esac
done
