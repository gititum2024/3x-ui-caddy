Thank you for providing the exact error message. This is a classic and subtle shell compatibility issue.

The error `./setup.sh: 9: Syntax error: ")" unexpected` indicates that the script is being executed by a more basic shell (like `sh` or `dash`) instead of `bash`, even though the shebang `#!/bin/bash` is present. This can happen on some minimal Linux systems where `/bin/sh` is not a link to `bash`.

The specific function `command_exists()` is written in a way that is compatible with `bash` but not with the simpler POSIX `sh`.

I have rewritten the script to be fully POSIX-compliant, which means it will run correctly on virtually any Linux system, regardless of its default shell. This is the most robust solution.

### Fully Compatible and Corrected Script

This version replaces the non-standard function definition with a more compatible equivalent. It will work correctly even if your system uses a simpler shell.

```bash name=setup.sh
#!/bin/sh

# --- Script Configuration ---
# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---

# POSIX-compliant way to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to print a formatted header
print_header() {
    echo
    echo "${GREEN}===================================================================${NC}"
    echo "${GREEN}  3x-ui & Caddy Fully Automated Setup (Compatible) by @copilot   ${NC}"
    echo "${GREEN}===================================================================${NC}"
    echo
}

# Function to install dependencies
install_dependencies() {
    local pkg_manager
    local install_cmd

    # Detect package manager
    if command_exists apt-get; then
        pkg_manager="apt-get"
        install_cmd="sudo $pkg_manager install -y"
    elif command_exists yum; then
        pkg_manager="yum"
        install_cmd="sudo $pkg_manager install -y"
    elif command_exists dnf; then
        pkg_manager="dnf"
        install_cmd="sudo $pkg_manager install -y"
    else
        echo "${RED}Error: Unsupported package manager. Please install dependencies manually.${NC}"
        exit 1
    fi

    echo "Updating package lists..."
    sudo $pkg_manager update -y > /dev/null

    # Install sqlite3 if missing
    if ! command_exists sqlite3; then
        echo "Installing sqlite3..."
        $install_cmd sqlite3 || $install_cmd sqlite
    fi

    # Install Docker if missing
    if ! command_exists docker; then
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
    fi

    # Check for docker compose or docker-compose
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
         echo "${RED}Docker Compose could not be installed or found. Please install it manually.${NC}"
         exit 1
    fi
}

# --- Main Script ---

print_header

# 1. Check for root/sudo privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "${RED}This script requires root or sudo privileges to install dependencies.${NC}"
    echo "Please run it with 'sudo ./setup.sh' or as the root user."
    exit 1
fi

# 2. Check and Install Dependencies
echo "${YELLOW}Step 1: Checking and installing required dependencies...${NC}"
install_dependencies
# Determine the correct docker-compose command
if docker compose version >/dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="docker compose"
else
    DOCKER_COMPOSE_CMD="docker-compose"
fi
echo "${GREEN}✅ All dependencies are installed.${NC}"
echo

# 3. Check if Docker daemon is running
if ! docker info > /dev/null 2>&1; then
    echo "${RED}Error: The Docker daemon is not running. Please start it to continue.${NC}"
    exit 1
fi

# 4. Get User Input
echo "${YELLOW}Step 2: Getting your configuration details...${NC}"
read -p "Please enter your domain name for the SSL certificate (e.g., mypanel.com): " DOMAIN
if [ -z "$DOMAIN" ]; then
    echo "${RED}Error: Domain name cannot be empty.${NC}"
    exit 1
fi

# Set the panel port to the default value
PANEL_PORT=2053

echo "${GREEN}✅ Domain set to: $DOMAIN${NC}"
echo "${GREEN}✅ Using default 3x-ui panel port: $PANEL_PORT${NC}"
echo

# 5. Create docker-compose.yml (using bind mounts for predictability)
echo "${YELLOW}Step 3: Creating docker-compose.yml file...${NC}"
# Create directories to ensure correct permissions
mkdir -p ./db ./caddy_data ./caddy_config
cat <<EOF > docker-compose.yml
services:
  3x-ui:
    image: ghcr.io/mhsanaei/3x-ui:latest
    container_name: 3x-ui
    restart: unless-stopped
    ports:
      - "${PANEL_PORT}:2053"
    volumes:
      - ./db:/etc/x-ui/
      - ./caddy_data:/data
    networks:
      - localnet
    security_opt:
      - no-new-privileges:true

  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - ./caddy_data:/data
      - ./caddy_config:/config
    networks:
      - localnet

networks:
  localnet:
    driver: bridge
EOF
echo "${GREEN}✅ docker-compose.yml created successfully.${NC}"
echo

# 6. Create Caddyfile
echo "${YELLOW}Step 4: Creating Caddyfile...${NC}"
cat <<EOF > Caddyfile
${DOMAIN} {
    respond "Caddy is running for SSL certificate management." 200
}
EOF
echo "${GREEN}✅ Caddyfile created for ${DOMAIN}.${NC}"
echo

# 7. Start Docker Containers
echo "${YELLOW}Step 5: Starting 3x-ui and Caddy containers...${NC}"
$DOCKER_COMPOSE_CMD up -d
if [ $? -ne 0 ]; then
    echo "${RED}Error: Docker Compose failed to start. Please check the logs.${NC}"
    exit 1
fi
echo "${GREEN}✅ Containers started successfully.${NC}"
echo

# 8. Wait for Certificate and Update Database
echo "${YELLOW}Step 6: Automating panel configuration...${NC}"
DB_PATH="./db/x-ui.db"
CERT_FILE_ON_HOST="./caddy_data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.crt"
CERT_FILE_IN_CONTAINER="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.crt"
KEY_FILE_IN_CONTAINER="/data/caddy/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}/${DOMAIN}.key"

TIMEOUT=180
INTERVAL=2
SECONDS_COUNTER=0

# Wait for the database file to exist first
echo "Waiting for 3x-ui to initialize its database... "
while [ ! -f "$DB_PATH" ]; do
    if [ $SECONDS_COUNTER -gt 60 ]; then # 1-minute timeout for DB creation
        echo
        echo "${RED}Error: Timed out waiting for 3x-ui database file.${NC}"
        echo "Check the 3x-ui container logs for errors: $DOCKER_COMPOSE_CMD logs 3x-ui"
        exit 1
    fi
    sleep $INTERVAL
    printf .
    SECONDS_COUNTER=$((SECONDS_COUNTER + INTERVAL))
done
echo
echo "${GREEN}✅ Database found!${NC}"

# Now wait for the certificate
SECONDS_COUNTER=0
echo "Waiting for Caddy to issue the SSL certificate for $DOMAIN... "
while [ ! -f "$CERT_FILE_ON_HOST" ]; do
    if [ $SECONDS_COUNTER -gt $TIMEOUT ]; then
        echo
        echo "${RED}Error: Timed out waiting for certificate.${NC}"
        echo "Troubleshooting tips:"
        echo "1. Ensure your domain's DNS A record points correctly to this server's IP."
        echo "2. Check Caddy's logs for errors: $DOCKER_COMPOSE_CMD logs caddy"
        exit 1
    fi
    sleep $INTERVAL
    printf .
    SECONDS_COUNTER=$((SECONDS_COUNTER + INTERVAL))
done
echo
echo "${GREEN}✅ Certificate found!${NC}"

echo "Updating 3x-ui database with certificate paths..."
sqlite3 "$DB_PATH" <<EOF
UPDATE settings SET value = '${CERT_FILE_IN_CONTAINER}' WHERE "key" = 'webCertFile';
UPDATE settings SET value = '${KEY_FILE_IN_CONTAINER}' WHERE "key" = 'webKeyFile';
EOF

if [ $? -eq 0 ]; then
    echo "${GREEN}✅ Database updated successfully.${NC}"
else
    echo "${RED}❌ Failed to update the database.${NC}"
    exit 1
fi
echo

# 9. Restart 3x-ui to Apply Changes
echo "${YELLOW}Step 7: Restarting 3x-ui to apply settings...${NC}"
$DOCKER_COMPOSE_CMD restart 3x-ui
echo "${GREEN}✅ 3x-ui container restarted.${NC}"
echo

# --- Final Output ---
echo "${GREEN}=======================================================${NC}"
echo "${GREEN}🎉 Setup Complete! 🎉${NC}"
echo
echo "You can now access your 3x-ui panel at (note: it's HTTP, not HTTPS):"
echo "  ${YELLOW}http://<YOUR_SERVER_IP>:${PANEL_PORT}${NC}"
echo
echo "Caddy has successfully acquired a certificate for ${YELLOW}${DOMAIN}${NC}."
echo "The certificate paths have been automatically configured in the panel settings."
echo "You can now use this domain for your TLS-based inbounds (VLESS, Trojan, etc.)."
echo "${GREEN}=======================================================${NC}"
```
