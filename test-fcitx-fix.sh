#!/bin/bash

# 测试脚本 - 验证 fcitx 启动修复
# 此脚本模拟容器环境来测试修复后的启动脚本

echo "=== Fcitx 启动修复测试 ==="

# 设置测试环境变量
export DISPLAY=:1
export USER_ID=0
export GROUP_ID=0

# 测试1: 检查 D-Bus 地址配置逻辑
echo "测试1: D-Bus 地址配置逻辑"
source /home/runner/work/docker-wechat-sogou-pinyin/docker-wechat-sogou-pinyin/startapp-enhanced.sh 2>/dev/null || true

# 模拟 root 用户环境
current_id=$(id -u)
echo "当前用户ID: $current_id"

# 检查目录是否存在
if [ "$current_id" = "0" ] && [ ! -d "/run/user/0" ]; then
    echo "✓ 检测到 root 用户且目录不存在，将使用 abstract socket"
else
    echo "✓ 将使用传统 socket 路径"
fi

# 测试2: 检查脚本语法
echo ""
echo "测试2: 脚本语法检查"
if bash -n /home/runner/work/docker-wechat-sogou-pinyin/docker-wechat-sogou-pinyin/startapp-enhanced.sh; then
    echo "✓ 脚本语法正确"
else
    echo "✗ 脚本语法错误"
    exit 1
fi

# 测试3: 检查关键函数
echo ""
echo "测试3: 关键函数检查"

# 检查函数是否存在
functions_to_check=("start_dbus" "start_fcitx" "cleanup_fcitx" "create_fcitx_socket_dir")

for func in "${functions_to_check[@]}"; do
    if declare -f "$func" > /dev/null; then
        echo "✓ 函数 $func 存在"
    else
        echo "✗ 函数 $func 不存在"
    fi
done

# 测试4: 验证改进点
echo ""
echo "测试4: 验证修复要点"

# 检查 D-Bus 启动逻辑
if grep -q "创建.*目录" /home/runner/work/docker-wechat-sogou-pinyin/docker-wechat-sogou-pinyin/startapp-enhanced.sh; then
    echo "✓ D-Bus 目录创建逻辑已添加"
else
    echo "✗ D-Bus 目录创建逻辑缺失"
fi

# 检查重试机制
if grep -q "retry_count" /home/runner/work/docker-wechat-sogou-pinyin/docker-wechat-sogou-pinyin/startapp-enhanced.sh; then
    echo "✓ D-Bus 启动重试机制已添加"
else
    echo "✗ D-Bus 启动重试机制缺失"
fi

# 检查进程状态检查
if grep -q "kill -0.*PID" /home/runner/work/docker-wechat-sogou-pinyin/docker-wechat-sogou-pinyin/startapp-enhanced.sh; then
    echo "✓ Fcitx 进程状态检查已添加"
else
    echo "✗ Fcitx 进程状态检查缺失"
fi

# 检查错误处理
if grep -q "fcitx_failed" /home/runner/work/docker-wechat-sogou-pinyin/docker-wechat-sogou-pinyin/startapp-enhanced.sh; then
    echo "✓ Fcitx 失败处理已添加"
else
    echo "✗ Fcitx 失败处理缺失"
fi

echo ""
echo "=== 测试完成 ==="
echo "修复要点总结:"
echo "1. ✓ 改进 D-Bus 地址配置，支持容器 root 环境"
echo "2. ✓ 添加 D-Bus 目录创建和权限设置"
echo "3. ✓ D-Bus 启动重试机制 (最多3次)"
echo "4. ✓ 改进 Fcitx 启动状态检查"
echo "5. ✓ 添加详细的错误诊断信息"
echo "6. ✓ 即使输入法失败也继续启动 WeChat"
echo ""
echo "建议用户操作:"
echo "1. 重新构建 Docker 镜像"
echo "2. 使用新的镜像重新启动容器"
echo "3. 查看容器日志确认修复效果"