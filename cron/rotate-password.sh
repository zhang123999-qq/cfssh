#!/bin/bash
# 每日密码轮换脚本
# 由 install.sh 安装到 /usr/local/bin/cf-ssh-rotate.sh
# cron: 0 0 * * * /usr/local/bin/cf-ssh-rotate.sh
#
# 重要：密码永不落盘，只通过邮件发送

set -e

CONFIG_FILE="/etc/cf-ssh-tunnel/config"
source "$CONFIG_FILE"  # 提供 USERNAME, NOTIFY_EMAIL, HOSTNAME

# 生成新密码
NEW_PASS=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 20)

# 设置新密码
echo "$USERNAME:$NEW_PASS" | chpasswd

# 发送邮件通知
DATE=$(date +%Y-%m-%d)
SUBJECT="SSH 隧道新密码 ($DATE)"
BODY="你的 SSH 隧道密码已轮换（$DATE）：

域名: $HOSTNAME
用户名: $USERNAME
新密码: $NEW_PASS

连接命令：
ssh -o ProxyCommand=\"cloudflared access ssh --hostname $HOSTNAME\" $USERNAME@$HOSTNAME

旧密码已失效，请使用新密码登录。
"

if command -v sendmail &>/dev/null; then
    echo -e "Subject: $SUBJECT\n\n$BODY" | sendmail "$NOTIFY_EMAIL"
elif command -v mail &>/dev/null; then
    echo "$BODY" | mail -s "$SUBJECT" "$NOTIFY_EMAIL"
else
    # 无邮件工具时，记录到系统日志（不含密码）
    logger -t cf-ssh-tunnel "密码已轮换，但无邮件工具，无法通知 $NOTIFY_EMAIL"
fi

logger -t cf-ssh-tunnel "密码轮换完成 ($DATE)"
