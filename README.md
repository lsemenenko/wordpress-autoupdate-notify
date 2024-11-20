# WordPress Plugin Auto-Update Script

A robust Bash script for automatically updating WordPress plugins with auto-updates enabled. The script performs health checks before and after updates, maintains detailed logs, and sends update reports to Mattermost.

## Description

This script automates the WordPress plugin update process with several key features:
- Updates only plugins that have auto-updates explicitly enabled
- Performs health checks on both the main site and wp-admin
- Generates detailed logs of all operations
- Sends formatted reports to Mattermost
- Handles permissions safely using the WordPress directory owner
- Automatically configures AUTOMATIC_UPDATER_DISABLED in wp-config.php
- Provides comprehensive error handling and status reporting

## Usage

### Environment Variables

Configure the script using the following environment variables (all optional):

```bash
WP_PATH=/var/www/html              # Path to WordPress installation
WP_CLI=/usr/local/bin/wp          # Path to WP-CLI executable
PHP_BIN=/usr/bin/php              # Path to PHP binary
SITE_URL=http://localhost         # WordPress site URL
MATTERMOST_WEBHOOK_URL=""         # Mattermost webhook URL for notifications
LOG_FILE=/var/log/wp-plugin-updates.log  # Log file location
CURL_TIMEOUT=30                   # Timeout for health check requests
```

### Basic Usage

1. Make the script executable:
```bash
chmod +x wp-plugin-update.sh
```

2. Run the script:
```bash
./wp-plugin-update.sh
```

### Cron Usage

#### Using crontab
Add to crontab to run automatically (example for daily at 3 AM):
```bash
0 3 * * * /path/to/wp-plugin-update.sh
```

#### Using /etc/cron.d (Recommended)
Create a new file in `/etc/cron.d/` (example: `/etc/cron.d/wordpress-plugin-updates`):
```bash
# WordPress Plugin Auto-Update Cron Job
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Environment Variables
WP_PATH=/var/www/html
WP_CLI=/usr/local/bin/wp
PHP_BIN=/usr/bin/php
SITE_URL=https://example.com
MATTERMOST_WEBHOOK_URL=https://mattermost.example.com/hooks/your-webhook-id
LOG_FILE=/var/log/wp-plugin-updates.log
CURL_TIMEOUT=30

# Run daily at 3 AM
0 3 * * * root /path/to/wp-plugin-update.sh
```

Make sure to:
1. Set proper permissions:
```bash
chmod 0644 /etc/cron.d/wordpress-plugin-updates
```

2. Ensure the file ends with a newline to avoid cron errors

The script will:
- Update enabled plugins
- Perform health checks
- Generate logs
- Send a Mattermost report
- Exit with status 1 if any updates fail or health checks fail