#!/usr/bin/env bash

# Update package lists
apt update
# Install necessary dependencies
apt install -y wget curl

# Setup Caddy repository and install Caddy
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy

# FoundryVTT download URL
FOUNDRY_URL=""
# Your desired hostname for Foundry example="foundry.example.com" default=""
FOUNDRY_HOSTNAME=""
# Location to save FoundryVTT app default="/opt/foundryvtt"
FOUNDRY_APP_DIR="/opt/foundryvtt"
# Location to save FoundryVTT data default="/opt/foundrydata"
FOUNDRY_DATA_DIR="/opt/foundrydata"
# Port number for FoundryVTT default="30000" increment by 1 for additional instances
FOUNDRY_PORT="30000"
# Name for PM2 for daemon management default="foundry"
FOUNDRY_PM2_NAME="foundry"
# Username of non-root user to manage Foundry default="foundry"
FOUNDRY_USER="foundry"

# Prompt for FoundryVTT download URL
read -p 'Enter the FoundryVTT download URL: ' FOUNDRY_URL

# Perform initial setup for new Foundry installs
while true; do
    read -p "Is this the first install? (y/n) " yn
    case $yn in 
        [yY] ) 
            echo "Setting up first install..."

            # Setup Node prerequisites
            curl -sL https://deb.nodesource.com/setup_16.x | bash -
            
            # Setup Caddy prerequisites
            apt install -y debian-keyring debian-archive-keyring apt-transport-https
            
            # Install Caddy and Node
            apt install -y libssl-dev unzip nodejs caddy

            break;;
        [nN] ) 
            echo "Installing additional instance..."
            break;;
        * ) 
            echo "Invalid response"
    esac
done

# Create system user to manage Foundry and set password
useradd -m foundry
passwd foundry
usermod -aG foundry foundry

# Set ownership and permissions for Foundry directories
mkdir -p /opt/foundryvtt
mkdir -p /opt/foundrydata
chown -R foundry:foundry /opt/foundryvtt
chown -R foundry:foundry /opt/foundrydata
chmod -R 755 /opt/foundryvtt
chmod -R 755 /opt/foundrydata

# Install PM2 for daemon management
npm install pm2@latest -g

# Allow PM2 to start at boot
pm2 startup

# Install Foundry
mkdir -p "$FOUNDRY_APP_DIR" "$FOUNDRY_DATA_DIR"
wget -O "$FOUNDRY_APP_DIR/foundryvtt.zip" "$FOUNDRY_URL"
unzip "$FOUNDRY_APP_DIR/foundryvtt.zip" -d "$FOUNDRY_APP_DIR"

# Give non-root user ownership for Foundry directories
chown -R $FOUNDRY_USER:$FOUNDRY_USER "$FOUNDRY_APP_DIR" "$FOUNDRY_DATA_DIR"

# Give Foundry time to generate the options.json file
echo "Initializing FoundryVTT..."
timeout 10 node $FOUNDRY_APP_DIR/resources/app/main.js

# Initialize Foundry with PM2 for daemon management
pm2 start "$FOUNDRY_APP_DIR/resources/app/main.js" --name $FOUNDRY_PM2_NAME -- --dataPath="$FOUNDRY_DATA_DIR"
pm2 save
sleep 3
pm2 stop $FOUNDRY_PM2_NAME

# Configure Caddy for HTTPS proxying
bash -c 'cat >> /etc/caddy/Caddyfile <<EOF
${FOUNDRY_HOSTNAME} {
  @http {
    protocol http
  }
  redir @http https://${FOUNDRY_HOSTNAME}
  reverse_proxy localhost:$FOUNDRY_PORT
}
EOF'

# Restart Caddy to apply the configuration
systemctl restart caddy

echo "FoundryVTT setup complete! Please access your instance online here: https://${FOUNDRY_HOSTNAME} or locally here: localhost:$FOUNDRY_PORT"
