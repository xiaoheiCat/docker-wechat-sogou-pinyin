#!/bin/bash

# Enhanced startup script with fcitx monitoring and auto-recovery
# Author: Generated with Claude Code
# Purpose: Fix input method disappearing issue

set -e

# Set environment variables for input method
export XMODIFIERS="@im=fcitx"
export GTK_IM_MODULE="fcitx"
export QT_IM_MODULE="fcitx"
export XIM_PROGRAM="fcitx"
export XIM="fcitx"

# Log file for monitoring
LOG_FILE="/var/log/fcitx-monitor.log"
FCITX_STARTUP_LOG="/tmp/fcitx_startup.log"

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if fcitx is running
is_fcitx_running() {
is_fcitx_running() {
    # 添加更详细的检查，包括进程状态验证
    if pgrep -x fcitx > /dev/null 2>&1; then
        # 检查 fcitx-remote 是否响应
        fcitx-remote > /dev/null 2>&1
        return $?
    fi
    return 1
}
}

# Function to start fcitx
start_fcitx() {
    log_message "Starting fcitx daemon..."
start_fcitx() {
    log_message "Starting fcitx daemon..."
    
    # 清理可能存在的僵尸进程
    pkill -x fcitx 2>/dev/null || true
    sleep 1
    
    if fcitx -d 2>>"$LOG_FILE"; then
        log_message "Fcitx daemon started successfully"
        return 0
    else
        log_message "ERROR: Failed to start fcitx daemon"
        return 1
    fi
}
        log_message "Fcitx daemon started successfully"
        return 0
    else
        log_message "ERROR: Failed to start fcitx daemon"
        return 1
    fi
}

# Function to wait for fcitx to be ready and configure sogoupinyin
configure_fcitx() {
    log_message "Waiting for fcitx to initialize..."
    timeout=30
    count=0

    while [ $count -lt $timeout ]; do
        if [ "$(fcitx-remote 2>/dev/null)" = "1" ]; then
            log_message "Fcitx is ready, setting sogoupinyin as default..."
            if fcitx-remote -s sogoupinyin 2>/dev/null; then
                log_message "Successfully set sogoupinyin as default input method"
            else
                log_message "Warning: Failed to set sogoupinyin as default input method"
            fi
            return 0
        fi
        count=$((count + 1))
        sleep 1
    done

    log_message "ERROR: Fcitx failed to initialize within $timeout seconds"
    return 1
}

# Function to monitor fcitx and auto-recover
monitor_fcitx() {
    log_message "Starting fcitx monitoring daemon..."

    while true; do
        if ! is_fcitx_running; then
            log_message "WARNING: Fcitx process is not running, attempting to restart..."
            if start_fcitx; then
                configure_fcitx
                log_message "Fcitx recovery completed successfully"
            else
                log_message "ERROR: Failed to recover fcitx"
            fi
        fi

        # Check every 30 seconds
        sleep 30
    done
}

# Function to handle cleanup on exit
cleanup() {
    log_message "Received shutdown signal, cleaning up..."
    # Kill the monitor process
    if [ -n "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi
    log_message "Cleanup completed"
    exit 0
}

# Set up signal handlers
trap cleanup SIGTERM SIGINT SIGQUIT

# Main execution
log_message "=== Enhanced WeChat Startup Script ==="
log_message "Starting WeChat with fcitx monitoring..."

# Start fcitx
if start_fcitx; then
    # Wait for fcitx to be ready and configure
    if configure_fcitx; then
        log_message "Fcitx initialization completed successfully"
    else
        log_message "WARNING: Fcitx initialization had issues, but continuing..."
    fi
else
    log_message "ERROR: Initial fcitx startup failed"
    exit 1
fi

# Start monitoring in background
monitor_fcitx &
MONITOR_PID=$!

log_message "Fcitx monitoring started (PID: $MONITOR_PID)"
log_message "Starting WeChat application..."

# Start WeChat as the main process
exec /usr/bin/wechat