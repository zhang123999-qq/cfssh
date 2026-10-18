#!/bin/bash
#
# cf-ssh-tunnel 一键安装脚本
#
# 用法:
#   curl -sSL https://raw.githubusercontent.com/USER/cf-ssh-tunnel/main/install.sh | sudo bash -s -- \
#     --cf-token "你的CF Token" \
#     --domain "zhtest.cc.cd" \
#     --notify-email "you@example.com"
#
# 重要：用户名、密码、域名只打印到控制台一次，密码永不落盘。
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/cf-api.sh"
source "$SCRIPT_DIR/lib/user-mgmt.sh"

# 默认值
CF_TOKEN=""
BASE_DOMAIN=""
NOTIFY_EMAIL=""

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --cf-token) CF_TOKEN="$2"; shift 2 ;;
        --domain) BASE_DOMAIN="$2"; shift 2 ;;
        --notify-email) NOTIFY_EMAIL="$2"; shift 2 ;;
        *) log_error "未知参数: $1"; exit 1 ;;
    esac
done

# 检查必要参数
[[ -z "$CF_TOKEN" ]] && { log_error "缺少 --cf-token"; exit 1; }
[[ -z "$BASE_DOMAIN" ]] && { log_error "缺少 --domain"; exit 1; }
[[ -z "$NOTIFY_EMAIL" ]] && { log_error "缺少 --notify-email"; exit 1; }

check_root
ARCH=$(get_arch)
OS=$(check_os)
log_info "系统: $OS, 架构: $ARCH"

# ============ 1. 安装 cloudflared ============
log_info "安装 cloudflared..."
if ! command -v cloudflared &>/dev/null; then
    CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH"
    curl -sSL "$CF_URL" -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
    log_info "cloudflared 已安装: $(cloudflared --version 2>&1 | head -1)"
else
    log_info "cloudflared 已存在，跳过安装"
fi

# ============ 2. 生成随机凭证 ============
USERNAME=$(gen_username)
PASSWORD=$(gen_password)
SUBDOMAIN=$(gen_subdomain)
HOSTNAME="$SUBDOMAIN.$BASE_DOMAIN"
TUNNEL_NAME="ssh-$SUBDOMAIN"
log_info "已生成随机凭证"

# ============ 3. 创建系统用户 ============
log_info "创建 SSH 用户..."
create_ssh_user "$USERNAME" "$PASSWORD"

# ============ 4. 创建 Cloudflare 隧道 ============
log_info "获取 Cloudflare 账户信息..."
ACCOUNT_ID=$(cf_get_account_id "$CF_TOKEN")
[[ "$ACCOUNT_ID" == "ERROR" ]] && { log_error "Token 无效或无账户权限"; exit 1; }

ZONE_ID=$(cf_get_zone_id "$CF_TOKEN" "$BASE_DOMAIN")
[[ "$ZONE_ID" == "ERROR" ]] && { log_error "找不到域名 $BASE_DOMAIN 的 Zone"; exit 1; }

log_info "创建隧道 $TUNNEL_NAME..."
TUNNEL_ID=$(cf_create_tunnel "$CF_TOKEN" "$ACCOUNT_ID" "$TUNNEL_NAME")
[[ "$TUNNEL_ID" == ERROR* ]] && { log_error "创建隧道失败: $TUNNEL_ID"; exit 1; }

log_info "配置隧道 ingress..."
cf_set_ingress "$CF_TOKEN" "$ACCOUNT_ID" "$TUNNEL_ID" "$HOSTNAME" > /dev/null

log_info "创建 DNS 记录..."
cf_create_dns "$CF_TOKEN" "$ZONE_ID" "$HOSTNAME" "$TUNNEL_ID"

log_info "获取隧道 Token..."
TUNNEL_TOKEN=$(cf_get_tunnel_token "$CF_TOKEN" "$ACCOUNT_ID" "$TUNNEL_ID")
[[ "$TUNNEL_TOKEN" == "ERROR" ]] && { log_error "获取隧道 Token 失败"; exit 1; }

# ============ 5. 安装 systemd 服务 ============
log_info "安装 cloudflared 系统服务..."
sed "s|__TUNNEL_TOKEN__|$TUNNEL_TOKEN|" "$SCRIPT_DIR/templates/cloudflared.service" > /etc/systemd/system/cf-ssh-tunnel.service
systemctl daemon-reload
systemctl enable cf-ssh-tunnel 2>/dev/null
systemctl restart cf-ssh-tunnel
sleep 3
systemctl is-active cf-ssh-tunnel > /dev/null && log_info "隧道服务运行中" || log_warn "隧道服务启动可能有问题，请检查"

# ============ 6. 安装密码轮换 ============
log_info "配置每日密码轮换..."
mkdir -p /etc/cf-ssh-tunnel
cat > /etc/cf-ssh-tunnel/config << EOF
# cf-ssh-tunnel 配置（不含密码！）
USERNAME="$USERNAME"
HOSTNAME="$HOSTNAME"
NOTIFY_EMAIL="$NOTIFY_EMAIL"
TUNNEL_ID="$TUNNEL_ID"
TUNNEL_NAME="$TUNNEL_NAME"
EOF
chmod 600 /etc/cf-ssh-tunnel/config

cp "$SCRIPT_DIR/cron/rotate-password.sh" /usr/local/bin/cf-ssh-rotate.sh
chmod +x /usr/local/bin/cf-ssh-rotate.sh

# 添加 cron（每天 00:00）
(crontab -l 2>/dev/null | grep -v "cf-ssh-rotate"; echo "0 0 * * * /usr/local/bin/cf-ssh-rotate.sh") | crontab -
log_info "密码轮换 cron 已添加（每天 00:00）"

# ============ 7. 输出凭证（仅此一次！） ============
echo ""
echo "=============================================="
echo "  安装完成！请保存以下信息（只显示一次）"
echo "=============================================="
echo ""
echo "  域名:     $HOSTNAME"
echo "  用户名:   $USERNAME"
echo "  密码:     $PASSWORD"
echo ""
echo "  连接命令:"
echo "  ssh -o ProxyCommand=\"cloudflared access ssh --hostname $HOSTNAME\" $USERNAME@$HOSTNAME"
echo ""
echo "  或加入 ~/.ssh/config:"
echo "  Host myserver"
echo "      HostName $HOSTNAME"
echo "      User $USERNAME"
echo "      ProxyCommand cloudflared access ssh --hostname %h"
echo ""
echo "  注意："
echo "  - 密码每天 00:00 自动更换，新密码发到 $NOTIFY_EMAIL"
echo "  - 密码不会保存在服务器上，请妥善保管本次输出"
echo "  - 客户端需要安装 cloudflared"
echo ""
echo "=============================================="
