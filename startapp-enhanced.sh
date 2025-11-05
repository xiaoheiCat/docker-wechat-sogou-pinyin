#!/bin/bash

# Enhanced fcitx monitoring script with 3-second check interval
# Fixes input method disappearing issues

LOG_FILE="/var/log/fcitx-monitor.log"
MONITOR_INTERVAL=3

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to check if fcitx is running
is_fcitx_running() {
    pgrep -x fcitx > /dev/null
}

# Function to check if fcitx is responsive
is_fcitx_responsive() {
    fcitx-remote > /dev/null 2>&1
}

# Function to start fcitx
start_fcitx() {
    log_message "Starting fcitx..."
    nohup fcitx > /dev/null 2>&1 &
    sleep 2  # Give fcitx time to initialize

    # Wait for fcitx to be responsive and set sogoupinyin as default
    local retry_count=0
    local max_retries=20
    while [ $retry_count -lt $max_retries ]; do
        if is_fcitx_responsive; then
            fcitx-remote -s sogoupinyin > /dev/null 2>&1
            log_message "fcitx started successfully and sogoupinyin set as default"
            return 0
        fi
        sleep 0.3
        ((retry_count++))
    done

    log_message "Warning: fcitx started but may not be fully responsive"
    return 1
}

# Function to restart fcitx
restart_fcitx() {
    log_message "fcitx process died or not responsive, restarting..."
    pkill -x fcitx
    sleep 1
    start_fcitx
}

# Cleanup function
cleanup() {
    log_message "Received shutdown signal, cleaning up..."
    pkill -x fcitx
    pkill -f "$(basename "$0")"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGQUIT

# Initialize log file
mkdir -p "$(dirname "$LOG_FILE")"
log_message "=== fcitx Monitor Started (3-second interval) ==="

# Start fcitx for the first time
start_fcitx

# Start monitoring in background
log_message "Starting fcitx monitoring with ${MONITOR_INTERVAL}-second interval..."
(
while true; do
    # Check if fcitx process is running
    if ! is_fcitx_running; then
        restart_fcitx
    elif ! is_fcitx_responsive; then
        log_message "fcitx is running but not responsive, attempting to fix..."
        restart_fcitx
    else
        # fcitx is healthy, ensure sogoupinyin is active
        fcitx-remote -s sogoupinyin > /dev/null 2>&1
    fi

    sleep "$MONITOR_INTERVAL"
done
) &

# Start WeChat as the main process
log_message "Starting WeChat..."
exec /usr/bin/wechat