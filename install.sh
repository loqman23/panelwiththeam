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
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}✗ Please run as root${NC}"
        exit 1
    fi
    
    # Check if system is Debian
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
    
    # Create database and user
    mysql -e "CREATE DATABASE ${DB_NAME};"
    mysql -e "CREATE USER '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
    mysql -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -e "FLUSH PRIVILEGES;"
    
    echo -e "${GREEN}✓ Database configured successfully${NC}"
}

# Function to setup SSL
setup_ssl() {
    echo -e "\n${PURPLE}➤ SSL Configuration${NC}"
    
    read -p "Domain name (e.g., panel.domain.com): " DOMAIN
    
    # Install certbot
    apt install -y certbot python3-certbot-nginx
    
    # Get SSL certificate
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email admin@$DOMAIN
    
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
    
    echo -e "${GREEN}✓ Panel base installation complete${NC}"
}

# Function to install theme
install_theme() {
    echo -e "\n${PURPLE}➤ Installing Custom Theme...${NC}"
    
    cd /var/www/pterodactyl
    mkdir -p resources/custom-theme
    curl -Lo theme.tar.gz https://github.com/loqmanas/pterodactyl-theme/releases/latest/download/theme.tar.gz
    tar -xzvf theme.tar.gz -C resources/custom-theme
    
    # Apply theme modifications
    cp -r resources/custom-theme/* resources/views/
    
    echo -e "${GREEN}✓ Theme installed successfully${NC}"
}

# Function to install wings
install_wings() {
    echo -e "\n${PURPLE}➤ Installing Wings...${NC}"
    
    # Install Docker
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
    systemctl enable --now docker
    
    # Install Wings
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
    chmod u+x /usr/local/bin/wings
    
    # Generate config
    read -p "Panel Domain: " PANEL_DOMAIN
    read -p "Application Token: " APP_TOKEN
    
    cat > /etc/pterodactyl/config.yml <<EOF
panel:
  location: https://${PANEL_DOMAIN}
  token: ${APP_TOKEN}
system:
  data: /var/lib/pterodactyl/volumes
  sftp:
    bind_port: 2022
api:
  host: 0.0.0.0
  port: 443
  ssl:
    enabled: false
EOF
    
    # Create systemd service
    cat > /etc/systemd/system/wings.service <<EOF
[Unit]
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
WantedBy=multi-user.target
EOF
    
    systemctl enable --now wings
    
    echo -e "${GREEN}✓ Wings installed successfully${NC}"
}

# Main menu
while true; do
    echo -e "\n${CYAN}Please select an installation option:${NC}"
    echo "1) Install Pterodactyl Panel"
    echo "2) Install Panel with Custom Theme"
    echo "3) Install Wings"
    echo "4) Exit"
    
    read -p "Enter choice [1-4]: " choice
    
    case $choice in
        1)
            check_requirements
            install_panel
            setup_database
            setup_ssl
            setup_admin
            echo -e "\n${GREEN}✓ Pterodactyl Panel installation completed!${NC}"
            echo -e "${YELLOW}Please visit your domain to login with your admin credentials${NC}"
            ;;
        2)
            check_requirements
            install_panel
            setup_database
            setup_ssl
            install_theme
            setup_admin
            echo -e "\n${GREEN}✓ Pterodactyl Panel and Theme installation completed!${NC}"
            echo -e "${YELLOW}Please visit your domain to login with your admin credentials${NC}"
            ;;
        3)
            check_requirements
            install_wings
            echo -e "\n${GREEN}✓ Wings installation completed!${NC}"
            ;;
        4)
            echo -e "\n${GREEN}Thank you for using loqmanas's Pterodactyl installer!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}Invalid option${NC}"
            ;;
    esac
done
