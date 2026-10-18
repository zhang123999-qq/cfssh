#!/bin/bash
#
# cf-ssh-tunnel 卸载脚本
#
# 用法:
#   sudo bash uninstall.sh --cf-token "你的CF Token"
#
# 会删除：系统用户、systemd 服务、cron、隧道、DNS 记录、配置文件
# 注意：此操作不可逆！
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/cf-api.sh"
source "$SCRIPT_DIR/lib/user-mgmt.sh"

CF_TOKEN=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --cf-token) CF_TOKEN="$2"; shift 2 ;;
        *) log_error "未知参数: $1"; exit 1 ;;
    esac
done

[[ -z "$CF_TOKEN" ]] && { log_error "缺少 --cf-token"; exit 1; }
check_root

CONFIG="/etc/cf-ssh-tunnel/config"
if [[ ! -f "$CONFIG" ]]; then
    log_error "未找到配置文件，可能未安装"
    exit 1
fi
source "$CONFIG"

echo "即将删除以下内容："
echo "  用户: $USERNAME"
echo "  域名: $HOSTNAME"
echo "  隧道: $TUNNEL_NAME ($TUNNEL_ID)"
echo ""
read -p "确认卸载？(y/N): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "已取消"; exit 0; }

# 1. 停止服务
log_info "停止隧道服务..."
systemctl stop cf-ssh-tunnel 2>/dev/null
systemctl disable cf-ssh-tunnel 2>/dev/null
rm -f /etc/systemd/system/cf-ssh-tunnel.service
systemctl daemon-reload

# 2. 删除 cron
log_info "删除密码轮换 cron..."
crontab -l 2>/dev/null | grep -v "cf-ssh-rotate" | crontab -
rm -f /usr/local/bin/cf-ssh-rotate.sh

# 3. 删除用户
log_info "删除用户 $USERNAME..."
delete_ssh_user "$USERNAME"

# 4. 删除 Cloudflare 隧道和 DNS
log_info "删除 Cloudflare 隧道..."
ACCOUNT_ID=$(cf_get_account_id "$CF_TOKEN")
cf_delete_tunnel "$CF_TOKEN" "$ACCOUNT_ID" "$TUNNEL_ID"
log_warn "请手动删除 DNS 记录: $HOSTNAME"

# 5. 清理配置
rm -rf /etc/cf-ssh-tunnel

log_info "卸载完成"
