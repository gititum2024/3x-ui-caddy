#!/bin/bash

# Load environment variables from .env file
if [ -f .env ]; then
    export $(cat .env | sed 's/#.*//g' | xargs)
fi

if [ -z "$DOMAIN" ]; then
    echo "Error: DOMAIN is not set. Please create a .env file with DOMAIN=your-domain.com"
    exit 1
fi

# Paths
DB_PATH="./db/x-ui.db"
CERT_FILE="/certs/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.crt"
KEY_FILE="/certs/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.key"
DOCKER_CERT_PATH="./data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.crt"

echo "Waiting for certificate for $DOMAIN to be created by Caddy..."
echo "This can take a few minutes on the first run."

# Loop until the certificate file is found
while [ ! -f "$DOCKER_CERT_PATH" ]; do
    sleep 5
    echo -n "."
done

echo -e "\nCertificate found! Updating 3x-ui database..."

# Check if sqlite3 is installed
if ! command -v sqlite3 &> /dev/null; then
    echo "sqlite3 command could not be found. Please install it."
    echo "On Debian/Ubuntu: sudo apt-get update && sudo apt-get install sqlite3"
    echo "On CentOS/RHEL: sudo yum install sqlite"
    exit 1
fi

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    echo "Error: Database file not found at $DB_PATH"
    echo "Please make sure you have run 'docker-compose up -d' at least once to generate the database."
    exit 1
fi

# Update the settings in the x-ui database
sqlite3 $DB_PATH <<EOF
UPDATE settings SET value = '${CERT_FILE}' WHERE "key" = 'webCertFile';
UPDATE settings SET value = '${KEY_FILE}' WHERE "key" = 'webKeyFile';
EOF

if [ $? -eq 0 ]; then
    echo "✅ Successfully updated certificate paths in 3x-ui."
    echo "Restarting 3x-ui container to apply changes..."
    docker-compose restart 3x-ui
    echo "All done! Your panel and inbounds can now use the SSL certificate."
else
    echo "❌ Failed to update the database."
fi
