#!/bin/bash

# 增强版启动脚本 - 解决输入法消失问题
# 包含 fcitx 进程持续监控和自动恢复机制

# 设置输入法环境变量
export XMODIFIERS="@im=fcitx"
export GTK_IM_MODULE="fcitx"
export QT_IM_MODULE="fcitx"
export XIM_PROGRAM="fcitx"
export XIM="fcitx"

# Fedora 42 KDE Wayland 兼容性：强制使用 X11 后端
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb

# 确保显示和 DBus 环境正确
export DISPLAY=${DISPLAY:-:1}
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}

# 日志文件路径
LOG_FILE="/var/log/fcitx-monitor.log"
STARTUP_LOG="/tmp/fcitx_startup.log"
ERROR_LOG="/tmp/fcitx_error.log"

# 创建日志目录
mkdir -p /var/log
touch "$LOG_FILE"

# 日志函数
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
}

# 启动 D-Bus 守护进程
start_dbus() {
    if ! pgrep -x "dbus-daemon" > /dev/null; then
        log_message "启动 D-Bus 守护进程..."
        dbus-daemon --session --fork --address="$DBUS_SESSION_BUS_ADDRESS" 2>"$ERROR_LOG"
        if [ $? -eq 0 ]; then
            log_message "D-Bus 守护进程启动成功"
        else
            log_error "D-Bus 守护进程启动失败"
            cat "$ERROR_LOG" >> "$LOG_FILE" 2>&1
        fi
    else
        log_message "D-Bus 守护进程已在运行"
    fi
}

# 清理现有 fcitx 进程和套接字
cleanup_fcitx() {
    log_message "清理现有 fcitx 进程和套接字..."
    pkill -f fcitx 2>/dev/null || true
    rm -rf /tmp/fcitx-* 2>/dev/null || true
    rm -rf ~/.config/fcitx/socket 2>/dev/null || true
    sleep 1
}

# 创建 fcitx 套接字目录
create_fcitx_socket_dir() {
    mkdir -p ~/.config/fcitx/socket
    chmod 755 ~/.config/fcitx/socket
}

# 启动 fcitx 守护进程
start_fcitx() {
    log_message "启动 fcitx 守护进程..."
    fcitx -d --enable=2 2>"$ERROR_LOG" &
    FCITX_PID=$!

    # 等待 fcitx 准备就绪
    timeout=30
    count=0
    while [ $count -lt $timeout ]; do
        if [ "$(fcitx-remote 2>/dev/null)" = "1" ]; then
            log_message "Fcitx 已准备就绪，设置搜狗拼音为默认..."
            fcitx-remote -r 2>/dev/null || true
            if fcitx-remote -s sogoupinyin 2>/dev/null; then
                log_message "成功设置搜狗拼音为默认输入法"
            else
                log_error "设置搜狗拼音为默认失败，将在 WeChat 启动后重试"
            fi
            echo "$FCITX_PID" > /tmp/fcitx.pid
            return 0
        else
            log_message "尝试 $((count + 1)): Fcitx 尚未准备就绪..."
        fi
        count=$((count + 1))
        sleep 1
    done

    if [ $count -ge $timeout ]; then
        log_error "Fcitx 在 $timeout 秒内未能初始化"
        log_error "Fcitx 错误详情:"
        cat "$ERROR_LOG" >> "$LOG_FILE" 2>&1 || true
        return 1
    fi
}

# 检查 fcitx 进程是否健康
check_fcitx_health() {
    local pid_file="/tmp/fcitx.pid"

    # 检查 PID 文件是否存在
    if [ ! -f "$pid_file" ]; then
        log_error "Fcitx PID 文件不存在"
        return 1
    fi

    local fcitx_pid=$(cat "$pid_file")

    # 检查进程是否存在
    if ! kill -0 "$fcitx_pid" 2>/dev/null; then
        log_error "Fcitx 进程 $fcitx_pid 不存在"
        return 1
    fi

    # 检查 fcitx 是否响应
    if [ "$(fcitx-remote 2>/dev/null)" != "1" ]; then
        log_error "Fcitx 进程存在但不响应"
        return 1
    fi

    return 0
}

# 重启 fcitx
restart_fcitx() {
    log_message "检测到 fcitx 异常，正在重启..."

    # 清理现有进程
    cleanup_fcitx

    # 重新启动
    create_fcitx_socket_dir
    if start_fcitx; then
        log_message "Fcitx 重启成功"

        # 尝试重新设置搜狗拼音为默认
        sleep 2
        if fcitx-remote -s sogoupinyin 2>/dev/null; then
            log_message "重启后成功设置搜狗拼音为默认"
        else
            log_error "重启后设置搜狗拼音失败"
        fi
        return 0
    else
        log_error "Fcitx 重启失败"
        return 1
    fi
}

# fcitx 监控进程
fcitx_monitor() {
    log_message "启动 fcitx 监控进程，监控间隔 3 秒"

    while true; do
        if ! check_fcitx_health; then
            restart_fcitx
        else
            # 可选：定期记录状态日志（每5分钟记录一次）
            if [ $(( $(date +%s) % 300 )) -eq 0 ]; then
                log_message "Fcitx 运行正常"
            fi
        fi
        sleep 3
    done
}

# 信号处理函数
cleanup() {
    log_message "接收到退出信号，正在清理..."

    # 停止监控进程
    if [ -n "$MONITOR_PID" ]; then
        kill "$MONITOR_PID" 2>/dev/null || true
    fi

    # 清理 fcitx 进程
    cleanup_fcitx

    log_message "清理完成，退出"
    exit 0
}

# 设置信号处理
trap cleanup SIGTERM SIGINT SIGQUIT

# 主程序
main() {
    log_message "=== 启动增强版 WeChat 容器 ==="

    # 启动 D-Bus
    start_dbus

    # 清理并初始化 fcitx
    cleanup_fcitx
    create_fcitx_socket_dir

    # 启动 fcitx
    if ! start_fcitx; then
        log_error "Fcitx 初始化失败，但继续启动 WeChat"
    fi

    # 启动 fcitx 监控进程（后台）
    fcitx_monitor &
    MONITOR_PID=$!
    log_message "Fcitx 监控进程已启动 (PID: $MONITOR_PID)"

    # 等待 2 秒确保 fcitx 完全准备就绪
    sleep 2

    # 启动 WeChat
    log_message "启动 WeChat..."

    # 在 WeChat 启动后再次尝试设置搜狗输入法
    (sleep 5 && fcitx-remote -s sogoupinyin 2>/dev/null && log_message "WeChat 启动后成功设置搜狗拼音") &

    # 启动 WeChat 主进程
    exec /usr/bin/wechat
}

# 执行主程序
main "$@"