#!/bin/sh
set -e

# Entry point for keepalived container
# - starts a lightweight syslogd to write keepalived logs to a file
# - writes a logrotate config templated from env vars
# - runs a simple background loop to invoke logrotate on interval

KEEPALIVED_LOG_FILE=${KEEPALIVED_LOG_FILE:-/var/log/keepalived/keepalived.log}
LOGROTATE_INTERVAL=${LOGROTATE_INTERVAL:-86400}

LOGDIR=$(dirname "$KEEPALIVED_LOG_FILE")
mkdir -p "$LOGDIR"
touch "$KEEPALIVED_LOG_FILE"
chmod 644 "$KEEPALIVED_LOG_FILE" || true

# Ensure logrotate state dir exists
mkdir -p /var/lib
touch /var/lib/logrotate.status || true

# Start syslogd (busybox) to capture keepalived syslog output to file
if command -v syslogd >/dev/null 2>&1; then
  # Start syslogd as a daemon writing to the configured file
  syslogd -O "$KEEPALIVED_LOG_FILE" || true
fi

# Create a logrotate config that rotates the keepalived log
cat > /etc/logrotate.d/keepalived <<EOF
$KEEPALIVED_LOG_FILE {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

# Background loop to run logrotate on the configured interval (seconds)
(
  while true; do
    logrotate -s /var/lib/logrotate.status /etc/logrotate.d/keepalived || true
    sleep "$LOGROTATE_INTERVAL"
  done
) &

# Allow overriding keepalived options via KEEPALIVED_OPTS env var
if [ -z "$KEEPALIVED_OPTS" ]; then
  KEEPALIVED_OPTS='-n -l -D -f /usr/local/etc/keepalived/keepalived.conf'
fi

# Exec keepalived with supplied options
exec sh -c "exec keepalived $KEEPALIVED_OPTS"
