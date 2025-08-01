#!/bin/sh

# Certificate paths
CERT_PATH="/ssl/cert.pem"
KEY_PATH="/ssl/key.pem"
CONFIG_PATH="/etc/x-ui/config.json"
LAST_MODIFIED_FILE="/ssl/.last_modified"

# Function to update 3x-ui config
update_config() {
    echo "Updating 3x-ui certificate configuration..."
    
    # Check if jq is installed, if not, install it
    if ! command -v jq >/dev/null 2>&1; then
        apk add --no-cache jq
    fi
    
    # Update the config file with the new certificate paths
    if [ -f "$CONFIG_PATH" ]; then
        # Create a temporary file with updated certificate paths
        jq ".certFile = \"$CERT_PATH\" | .keyFile = \"$KEY_PATH\"" "$CONFIG_PATH" > "$CONFIG_PATH.tmp"
        
        # Replace the original file with the updated one
        mv "$CONFIG_PATH.tmp" "$CONFIG_PATH"
        
        echo "Certificate paths updated in 3x-ui config"
        
        # Signal 3x-ui to reload the configuration
        if pgrep -f "x-ui" > /dev/null; then
            pkill -HUP -f "x-ui"
            echo "Sent reload signal to 3x-ui"
        fi
    else
        echo "Error: 3x-ui config file not found at $CONFIG_PATH"
    fi
}

# Initial check for existing certificates
if [ -f "$CERT_PATH" ] && [ -f "$KEY_PATH" ]; then
    # Record initial timestamps
    stat -c "%Y" "$CERT_PATH" > "$LAST_MODIFIED_FILE"
    update_config
fi

# Install tools for monitoring
apk add --no-cache inotify-tools

# Main monitoring loop
echo "Starting certificate monitor..."
while true; do
    # Monitor the SSL directory for changes
    inotifywait -e modify -e create -e attrib "$CERT_PATH" "$KEY_PATH" 2>/dev/null
    
    # Check if files were actually modified to avoid false triggers
    NEW_TIMESTAMP=$(stat -c "%Y" "$CERT_PATH")
    OLD_TIMESTAMP=$(cat "$LAST_MODIFIED_FILE" 2>/dev/null || echo "0")
    
    if [ "$NEW_TIMESTAMP" != "$OLD_TIMESTAMP" ]; then
        echo "Certificate change detected"
        echo "$NEW_TIMESTAMP" > "$LAST_MODIFIED_FILE"
        update_config
    else
        echo "False trigger, no actual change detected"
    fi
    
    # Small delay to prevent high CPU usage on rapid changes
    sleep 2
done
