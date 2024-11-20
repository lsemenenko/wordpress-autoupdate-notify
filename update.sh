#!/bin/bash

# WordPress Plugin Auto-Update Script
# This script updates WordPress plugins that have auto-updates enabled,
# performs health checks, and sends a report to Mattermost

# Configuration variables
WP_PATH="${WP_PATH:-/var/www/html}"
WP_CLI="${WP_CLI:-/usr/local/bin/wp}"
PHP_BIN="${PHP_BIN:-/usr/bin/php}"
SITE_URL="${SITE_URL:-http://localhost}"
MATTERMOST_WEBHOOK_URL="${MATTERMOST_WEBHOOK_URL:-""}"
LOG_FILE="${LOG_FILE:-/var/log/wp-plugin-updates.log}"
CURL_TIMEOUT="${CURL_TIMEOUT:-30}"

# Initialize report variables
updates_performed=()
failed_updates=()
health_check_status="✅ Passed"

# Function to log messages
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Function to send message to Mattermost
send_to_mattermost() {
    local message="$1"
    if [ -n "$MATTERMOST_WEBHOOK_URL" ]; then
        curl -X POST -H 'Content-Type: application/json' \
             --data "{\"text\": \"$message\"}" \
             "$MATTERMOST_WEBHOOK_URL"
    else
        log_message "Mattermost webhook URL not configured. Skipping notification."
    fi
}

# Function to check site health
check_site_health() {
    local url="$1"
    local response_code=$(curl -sL -w "%{http_code}" "$url" -o /dev/null --max-time "$CURL_TIMEOUT")
    
    if [ "$response_code" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Change to WordPress directory and get owner
cd "$WP_PATH" || {
    log_message "Error: Cannot change to WordPress directory at $WP_PATH"
    exit 1
}

# Get the owner of WP_PATH
WP_OWNER=$(stat -c '%U' "$WP_PATH")
if [ -z "$WP_OWNER" ]; then
    log_message "Error: Could not determine WordPress directory owner"
    exit 1
fi

log_message "WordPress directory owner: $WP_OWNER"

# Check wp-config.php location (could be in WP_PATH or one level up)
WP_CONFIG="$WP_PATH/wp-config.php"
if [ ! -f "$WP_CONFIG" ]; then
    WP_CONFIG="$(dirname "$WP_PATH")/wp-config.php"
    if [ ! -f "$WP_CONFIG" ]; then
        log_message "Error: wp-config.php not found in $WP_PATH or parent directory"
        exit 1
    fi
fi

log_message "Found wp-config.php at: $WP_CONFIG"

if ! grep -q "define.*AUTOMATIC_UPDATER_DISABLED.*true" "$WP_CONFIG"; then
    log_message "AUTOMATIC_UPDATER_DISABLED not found in wp-config.php. Adding it..."
    
    # Create temporary file
    TEMP_CONFIG=$(mktemp)
    
    # Add the define after the custom values line
    awk '
        /Add any custom values between this line and the "stop editing" line/ {
            print
            print "define(\"AUTOMATIC_UPDATER_DISABLED\", true);"
            next
        }
        { print }
    ' "$WP_CONFIG" > "$TEMP_CONFIG"
    
    # Check if awk command succeeded
    if [ $? -ne 0 ]; then
        log_message "Error: Failed to update wp-config.php"
        rm -f "$TEMP_CONFIG"
        exit 1
    fi
    
    # Backup original config
    cp "$WP_CONFIG" "${WP_CONFIG}.backup-$(date +%Y%m%d%H%M%S)"
    
    # Move new config in place with correct permissions
    CURRENT_PERMS=$(stat -c '%a' "$WP_CONFIG")
    mv "$TEMP_CONFIG" "$WP_CONFIG"
    chmod "$CURRENT_PERMS" "$WP_CONFIG"
    chown "$WP_OWNER" "$WP_CONFIG"
    
    log_message "Successfully added AUTOMATIC_UPDATER_DISABLED to wp-config.php"
else
    log_message "AUTOMATIC_UPDATER_DISABLED already set in wp-config.php"
fi

# Check if wp-cli is available
if ! command -v "$WP_CLI" > /dev/null 2>&1; then
    log_message "Error: wp-cli not found at $WP_CLI"
    exit 1
fi

# Get list of plugins with auto-updates enabled
log_message "Getting list of plugins with auto-updates enabled..."
auto_update_plugins=$(sudo -u "$WP_OWNER" "$PHP_BIN" "$WP_CLI" plugin list --field=name --auto_update=on --update=available)

if [ -z "$auto_update_plugins" ]; then
    log_message "No plugins with auto-updates enabled found."
    exit 0
fi

# Update each plugin
for plugin in $auto_update_plugins; do
    log_message "Checking updates for plugin: $plugin"
    
    if sudo -u "$WP_OWNER" "$PHP_BIN" "$WP_CLI" plugin update "$plugin" --quiet; then
        updates_performed+=("✅ $plugin")
        log_message "Successfully updated plugin: $plugin"
    else
        failed_updates+=("❌ $plugin")
        log_message "Failed to update plugin: $plugin"
    fi
done

# Perform health checks
log_message "Performing health checks..."

# Check main site
if ! check_site_health "${SITE_URL}/?no-cache"; then
    health_check_status="❌ Failed - Main site check failed"
    log_message "Health check failed for main site"
fi

# Check wp-admin
if ! check_site_health "${SITE_URL}/wp-admin"; then
    health_check_status="❌ Failed - wp-admin check failed"
    log_message "Health check failed for wp-admin"
fi

# Prepare report
report="### WordPress Plugin Update Report\n"
report+="**Site:** ${SITE_URL}\n"
report+="**Time:** $(date '+%Y-%m-%d %H:%M:%S')\n\n"

report+="**Health Check Status:** ${health_check_status}\n\n"

if [ ${#updates_performed[@]} -gt 0 ]; then
    report+="**Successfully Updated Plugins:**\n"
    for plugin in "${updates_performed[@]}"; do
        report+="- ${plugin}\n"
    done
    report+="\n"
fi

if [ ${#failed_updates[@]} -gt 0 ]; then
    report+="**Failed Updates:**\n"
    for plugin in "${failed_updates[@]}"; do
        report+="- ${plugin}\n"
    done
    report+="\n"
fi

# Log and send report
log_message "Update process completed"
log_message "$report"
send_to_mattermost "$report"

# Exit with error if any updates failed or health checks failed
if [ ${#failed_updates[@]} -gt 0 ] || [ "$health_check_status" != "✅ Passed" ]; then
    exit 1
fi

exit 0