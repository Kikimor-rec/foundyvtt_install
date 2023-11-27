#!/usr/bin/env bash

# Update package lists
sudo apt update
# Install necessary dependencies
sudo apt install -y wget

# Setup Caddy repository and install Caddy
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install -y caddy

# FoundryVTT download URL
FOUNDRY_URL=""
# Your desired hostname for Foundry example="foundry.example.com" default=""
FOUNDRY_HOSTNAME=""
# Location to save FoundryVTT app default="/opt/foundryvtt"
FOUNDRY_APP_DIR="/opt/foundryvtt"
# Location to save FoundryVTT assets/modules/systems default="/opt/foundrydata"
# Prompt for FoundryVTT download URL
read -p 'Enter the FoundryVTT download URL: ' FOUNDRY_URL
FOUNDRY_DATA_DIR="/opt/foundrydata"
# Port number for FoundryVTT default="30000" increment by 1 for additional instances
FOUNDRY_PORT="30000"
# Name for PM2 for daemon management default="foundry"
FOUNDRY_PM2_NAME="foundry"
# Username of non-root user to manage Foundry default="foundry"
FOUNDRY_USER="foundry"

# Perform initial setup for new Foundry installs
while true; do
    read -p "Is this the first install? (y/n) " yn
    case $yn in 
        [yY] ) 
            echo "Setting up first install..."

            # Setup Node prerequisites
            curl -sL https://deb.nodesource.com/setup_16.x | sudo bash -
            
            # Setup Caddy prerequisites
            sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
            sudo apt update
            
            # Install Caddy and Node
            sudo apt install -y libssl-dev unzip nodejs caddy

            break;;
        [nN] ) 
            echo "Installing additional instance..."
            break;;
        * ) 
            echo invalid response
    esac
done

# Create system user to manage Foundry and set password
sudo useradd -m foundry
sudo passwd foundry
sudo usermod -aG sudo foundry

# Set ownership and permissions for Foundry directories
sudo mkdir -p /opt/foundryvtt
sudo mkdir -p /opt/foundrydata
sudo chown -R foundry:foundry /opt/foundryvtt
sudo chown -R foundry:foundry /opt/foundrydata
sudo chmod -R 755 /opt/foundryvtt
sudo chmod -R 755 /opt/foundrydata

# Install PM2 for daemon management
sudo npm install pm2@latest -g

# Allow PM2 to start at boot
sudo pm2 startup

# Install Foundry
sudo mkdir -p "$FOUNDRY_APP_DIR" "$FOUNDRY_DATA_DIR"
sudo wget -O "$FOUNDRY_APP_DIR/foundryvtt.zip" "$FOUNDRY_URL"
sudo unzip "$FOUNDRY_APP_DIR/foundryvtt.zip" -d "$FOUNDRY_APP_DIR"

# Give non-root user ownership for Foundry directories
sudo chown -R $FOUNDRY_USER:$FOUNDRY_USER "$FOUNDRY_APP_DIR" "$FOUNDRY_DATA_DIR"

# Give Foundry time to generate the options.json file
echo "Initializing FoundryVTT..."
sudo timeout 10 node $FOUNDRY_APP_DIR/resources/app/main.js

# Initialize Foundry with PM2 for daemon management
sudo -u foundry pm2 start "$FOUNDRY_APP_DIR/resources/app/main.js" --name $FOUNDRY_PM2_NAME -- --dataPath="$FOUNDRY_DATA_DIR"
sudo pm2 save
sudo sleep 3
sudo pm2 stop $FOUNDRY_PM2_NAME

# Configure Caddy for HTTPS proxying
sudo bash -c 'cat >> /etc/caddy/Caddyfile <<EOF
${FOUNDRY_HOSTNAME} {
  @http {
    protocol http
  }
  redir @http https://${FOUNDRY_HOSTNAME}
  reverse_proxy localhost:$FOUNDRY_PORT
}
EOF'

# Configure Foundry for HTTPS proxying
sudo bash -c 'cat > "$FOUNDRY_DATA_DIR/Config/options.json" <<EOF
{
  "dataPath": "${FOUNDRY_DATA_DIR}",
  "compressStatic": true,
  "fullscreen": false,
  "hostname": "${FOUNDRY_HOSTNAME}",
  "language": "en.core",
  "localHostname": null,
  "port": $FOUNDRY_PORT,
  "protocol": null,
  "proxyPort": null,
  "proxySSL": false,
  "routePrefix": null,
  "updateChannel": "stable",
  "upnp": true,
  "upnpLeaseDuration": null,
  "awsConfig": null,
  "passwordSalt": null,
  "sslCert": null,
  "sslKey": null,
  "world": null,
  "serviceConfig": null
}
EOF'

# Restart Foundry to take proxying into account
sudo pm2 start $FOUNDRY_PM2_NAME

# Re-start Caddy
sudo systemctl restart caddy

echo "FoundryVTT setup complete! Please access your instance online here: https://$FOUNDRY_HOSTNAME or locally here: localhost:$FOUNDRY_PORT"
