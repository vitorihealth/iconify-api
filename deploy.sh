#!/bin/bash
# Iconify API Deployment Script with Nginx and Certbot on Docker Compose

# --- 1. CONFIGURATION ---

DOMAIN="iconify.vitorihealth.com"
EMAIL="service@vitorihealth.com"
BOOTSTRAP_NGINX="nginx-bootstrap.conf" # Source template for Phase 1 (Certbot)
HTTPS_NGINX="nginx-https.conf" # Source template for Phase 2 (Final SSL)
NGINX_CONF="nginx.conf" # The actual file mounted into the Nginx container

# Ensure required files exist
REQUIRED_FILES=("docker-compose.yml" "$BOOTSTRAP_NGINX" "$HTTPS_NGINX")
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "Error: Required file '$file' not found in the current directory."
        exit 1
    fi
done

echo "--- Starting deployment for domain: $DOMAIN ---"

# --- 2. PRE-DEPLOYMENT SETUP ---

docker compose down
echo "Cleaned up previous deployment (if any)."

if [ ! -d "certbot/www" ]; then
    mkdir -p certbot/www
    echo "Created persistent directories for Certbot volumes."
fi

# --- 3. PHASE 1: CERTIFICATE ACQUISITION (HTTP-01 Challenge) ---

echo "--- PHASE 1: ACQUIRING SSL CERTIFICATE ---"

# 3.1. Copy the bootstrap config template into the live config file (nginx.conf)
echo "Setting temporary Nginx config for Certbot challenge..."
# NOTE: Using the bootstrap file as source and writing to the live NGINX_CONF file.
cp "$BOOTSTRAP_NGINX" "$NGINX_CONF"

# 3.2. Start Nginx and Iconify API containers 
echo "Starting Iconify API and Nginx on port 80..."
docker compose up -d iconify-api nginx 

if ! docker compose ps -q nginx; then
    echo "Error: Nginx failed to start with temporary config. Check logs."
    exit 1
fi

# 3.3. Run Certbot once to get the certificate (uses --webroot over Port 80)
echo "Running Certbot to obtain initial certificate for $DOMAIN..."
docker compose run --rm certbot certonly --webroot -w /var/www/certbot \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email

CERT_STATUS=$?
if [ $CERT_STATUS -ne 0 ]; then
    echo "Certbot failed to acquire certificate. Check DNS A-Record, firewall, and logs. Aborting."
    docker compose down
    exit 1
fi

echo "Certificate acquired successfully and saved to ./certbot/conf!"

# --- 4. PHASE 2: SECURE DEPLOYMENT (HTTPS Proxy and Renewal) ---

# 4.1. Stop Nginx to apply final SSL configuration
echo "Stopping Nginx to apply final SSL configuration..."
docker compose stop nginx

# 4.2. Copy the final SSL config into the active Nginx config file name
echo "Setting final Nginx config with HTTPS, whitelisting, and proxy..."
# CRITICAL FIX: Use the HTTPS_NGINX (source template) to overwrite the NGINX_CONF (live file).
# Since your templates already have the domain name, 'cp' is the cleanest method here.
cp "$HTTPS_NGINX" "$NGINX_CONF"

# 4.3. Start the entire stack, including the persistent Certbot renewal job
echo "Starting final HTTPS stack (Nginx, Iconify API, and Certbot renewal cron)..."
docker compose up -d

if docker compose ps -q nginx; then
    echo "Deployment successful!"
    echo "---"
    echo "Your Iconify API is now accessible securely at:"
    echo "https://$DOMAIN"
    echo "---"
    echo "Nginx is running with IP Whitelisting enabled in 'nginx.conf'."
    echo "Certbot is running in the background and will automatically renew the certificate."
else
    echo "Fatal Error: Nginx failed to start with the final SSL config. Check logs!"
    exit 1
fi
