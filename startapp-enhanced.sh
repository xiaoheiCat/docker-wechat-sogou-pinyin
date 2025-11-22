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

# 改进的 D-Bus 地址配置 - 支持容器环境
if [ "$(id -u)" = "0" ] && [ ! -d "/run/user/0" ]; then
    # 容器以 root 运行且目录不存在时，使用临时目录
    export DBUS_SESSION_BUS_ADDRESS="unix:abstract=/tmp/dbus-session-$$"
else
    export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}
fi

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

        # 确保 D-Bus 依赖的目录存在
        if [[ "$DBUS_SESSION_BUS_ADDRESS" =~ unix:path=/run/user/([0-9]+)/bus ]]; then
            user_id="${BASH_REMATCH[1]}"
            mkdir -p "/run/user/$user_id"
            # 设置正确的权限
            chown "$user_id:$user_id" "/run/user/$user_id" 2>/dev/null || true
            chmod 700 "/run/user/$user_id" 2>/dev/null || true
        fi

        # 启动 D-Bus，添加重试机制
        local retry_count=0
        local max_retries=3

        while [ $retry_count -lt $max_retries ]; do
            dbus-daemon --session --fork --address="$DBUS_SESSION_BUS_ADDRESS" 2>"$ERROR_LOG"
            if [ $? -eq 0 ]; then
                log_message "D-Bus 守护进程启动成功"
                sleep 1  # 给 D-Bus 一点启动时间
                return 0
            else
                retry_count=$((retry_count + 1))
                log_error "D-Bus 启动尝试 $retry_count 失败"
                if [ $retry_count -lt $max_retries ]; then
                    sleep 2
                fi
            fi
        done

        log_error "D-Bus 守护进程启动失败，最终放弃"
        log_error "D-Bus 地址: $DBUS_SESSION_BUS_ADDRESS"
        log_error "D-Bus 用户: $(id)"
        cat "$ERROR_LOG" >> "$LOG_FILE" 2>&1
        return 1
    else
        log_message "D-Bus 守护进程已在运行"
        return 0
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

    # 首先确保 D-Bus 正在运行
    if ! pgrep -x "dbus-daemon" > /dev/null; then
        log_error "D-Bus 未运行，Fcitx 无法启动"
        return 1
    fi

    # 设置 XDG 变量以确保 fcitx 找到配置
    export XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
    export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/tmp/xdg-runtime-$$}
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR" 2>/dev/null || true

    # 启动 fcitx，添加更详细的日志
    fcitx -d --enable=2 2>"$ERROR_LOG" &
    FCITX_PID=$!
    echo "$FCITX_PID" > /tmp/fcitx.pid

    log_message "Fcitx 进程已启动 (PID: $FCITX_PID)，等待准备就绪..."

    # 改进的等待机制 - 检查多种状态指标
    timeout=30
    count=0
    ready=false

    while [ $count -lt $timeout ] && [ "$ready" = "false" ]; do
        # 检查进程是否还在运行
        if ! kill -0 "$FCITX_PID" 2>/dev/null; then
            log_error "Fcitx 进程 $FCITX_PID 已退出"
            log_error "Fcitx 错误详情:"
            cat "$ERROR_LOG" >> "$LOG_FILE" 2>&1 || true
            return 1
        fi

        # 使用多种方式检查 fcitx 状态
        fcitx_status=$(fcitx-remote 2>/dev/null || echo "ERROR")

        case "$fcitx_status" in
            "1")
                log_message "Fcitx 已准备就绪，设置搜狗拼音为默认..."
                ready=true

                # 设置搜狗拼音为默认
                fcitx-remote -r 2>/dev/null || true
                if fcitx-remote -s sogoupinyin 2>/dev/null; then
                    log_message "成功设置搜狗拼音为默认输入法"
                else
                    log_error "设置搜狗拼音为默认失败，将在 WeChat 启动后重试"
                fi
                ;;
            "0")
                log_message "尝试 $((count + 1)): Fcitx 进程存在但未激活..."
                ;;
            "ERROR"|*)
                log_message "尝试 $((count + 1)): Fcitx 尚未准备就绪..."
                ;;
        esac

        # 每5次尝试记录一次进程状态
        if [ $((count % 5)) -eq 0 ] && [ $count -gt 0 ]; then
            log_message "Fcitx 状态检查: PID=$FCITX_PID, 返回值=$fcitx_status"
        fi

        count=$((count + 1))
        sleep 1
    done

    if [ "$ready" = "false" ]; then
        log_error "Fcitx 在 $timeout 秒内未能初始化"
        log_error "Fcitx 错误详情:"
        cat "$ERROR_LOG" >> "$LOG_FILE" 2>&1 || true
        log_error "系统环境: DISPLAY=$DISPLAY, DBUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
        log_error "进程状态: PID=$FCITX_PID, 运行状态=$(kill -0 "$FCITX_PID" 2>/dev/null && echo "存活" || echo "已退出")"
        return 1
    fi

    return 0
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
    log_message "系统信息: 用户=$(id), 显示=$DISPLAY"

    # 启动 D-Bus
    if ! start_dbus; then
        log_error "D-Bus 启动失败，这将影响输入法功能"
        log_error "WeChat 将以无输入法模式启动"
        # 即使 D-Bus 失败也继续启动 WeChat，但记录状态
        fcitx_failed=true
    else
        fcitx_failed=false
    fi

    # 清理并初始化 fcitx
    cleanup_fcitx
    create_fcitx_socket_dir

    # 只有在 D-Bus 成功时才尝试启动 fcitx
    if [ "$fcitx_failed" = "false" ]; then
        # 启动 fcitx
        if ! start_fcitx; then
            log_error "Fcitx 初始化失败，但继续启动 WeChat"
            fcitx_failed=true
        else
            # 启动 fcitx 监控进程（后台）
            fcitx_monitor &
            MONITOR_PID=$!
            log_message "Fcitx 监控进程已启动 (PID: $MONITOR_PID)"
        fi
    fi

    # 等待系统稳定
    sleep 3

    # 启动 WeChat
    log_message "启动 WeChat..."

    if [ "$fcitx_failed" = "false" ]; then
        # 在 WeChat 启动后再次尝试设置搜狗输入法
        (sleep 10 && fcitx-remote -s sogoupinyin 2>/dev/null && log_message "WeChat 启动后成功设置搜狗拼音") &
    else
        # 如果 fcitx 失败，提供解决建议
        log_message "输入法不可用，建议检查容器配置:"
        log_message "1. 确保 Docker 用户 ID 设置正确"
        log_message "2. 检查容器权限配置"
        log_message "3. 验证 D-Bus 配置"
    fi

    # 启动 WeChat 主进程
    exec /usr/bin/wechat
}

# 执行主程序
main "$@"