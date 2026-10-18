#!/bin/bash
# 手动密码轮换脚本
# 用法: sudo cf-ssh-rotate.sh
# 新密码直接打印到控制台，不发送、不保存
#
# 重要：密码永不落盘，只打印一次

set -e

CONFIG_FILE="/etc/cf-ssh-tunnel/config"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误：未找到配置文件 $CONFIG_FILE" >&2
    exit 1
fi
source "$CONFIG_FILE"  # 提供 USERNAME, HOSTNAME

if [[ $EUID -ne 0 ]]; then
    echo "请用 root 运行：sudo cf-ssh-rotate.sh" >&2
    exit 1
fi

# 生成新密码
NEW_PASS=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 20)

# 设置新密码
echo "$USERNAME:$NEW_PASS" | chpasswd

# 打印到控制台（仅此一次）
echo ""
echo "=============================================="
echo "  密码已更换！请保存（只显示一次）"
echo "=============================================="
echo ""
echo "  域名:     $HOSTNAME"
echo "  用户名:   $USERNAME"
echo "  新密码:   $NEW_PASS"
echo ""
echo "=============================================="
