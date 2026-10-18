#!/bin/bash
#
# cf-ssh-tunnel 一键安装（3X-UI 风格）
#
# 安装:
#   bash <(curl -Ls https://raw.githubusercontent.com/zhang123999-qq/cf-ssh-tunnel/main/install.sh)
#
# 安装后管理:
#   cf-ssh-tunnel
#
# 重要：用户名、密码、域名只打印到控制台一次，密码永不落盘。
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
SKYBLUE='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# ---- 必须 root ----
if [[ $EUID -ne 0 ]]; then
    log_error "请用 root 运行"
    exit 1
fi

echo -e "${SKYBLUE}"
cat << 'EOF'
   ____ _____     ____ ____  _   _   _____                             _
  / ___|  ___|   / ___/ ___|| | | | |_   _|   _ _ __  _ __   ___  | |
 | |   | |_ _____ \___ \___ \| |_| |   | || | | | '_ \| '_ \ / _ \ | |
 | |___|  _|_____|___) |__) |  _  |   | || |_| | | | | | | |  __/ | |
  \____|_|       |____/____/|_| |_|   |_| \__,_|_| |_|_| |_|\___| |_|

        Argo 隧道 SSH · 一键安装
EOF
echo -e "${NC}"

# ---- 交互式输入 ----
echo ""
read -p "请输入 Cloudflare API Token: " CF_TOKEN
[[ -z "$CF_TOKEN" ]] && { log_error "Token 不能为空"; exit 1; }

read -p "请输入域名 (如 yanhuang.cc.cd): " BASE_DOMAIN
[[ -z "$BASE_DOMAIN" ]] && { log_error "域名不能为空"; exit 1; }

# ---- 随机生成 ----
gen_username() { echo "u$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)"; }
gen_password() { tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 20; echo; }
gen_subdomain() { tr -dc '0-9' < /dev/urandom | head -c 10; echo; }

USERNAME=$(gen_username)
PASSWORD=$(gen_password)
SUBDOMAIN=$(gen_subdomain)
HOSTNAME="$SUBDOMAIN.$BASE_DOMAIN"
TUNNEL_NAME="ssh-$SUBDOMAIN"

ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) log_error "不支持的架构: $ARCH"; exit 1 ;;
esac

CF_API="https://api.cloudflare.com/client/v4"

# ---- API 辅助函数 ----
cf_api() {  # $1=method $2=path $3=data
    local method="$1" path="$2" data="$3"
    if [[ -n "$data" ]]; then
        curl -s -X "$method" "$CF_API$path" \
            -H "Authorization: Bearer $CF_TOKEN" \
            -H "Content-Type: application/json" \
            --data "$data"
    else
        curl -s -X "$method" "$CF_API$path" \
            -H "Authorization: Bearer $CF_TOKEN"
    fi
}

echo ""
log_info "正在验证 Token..."

# 获取 account_id
ACCOUNT_ID=$(cf_api GET "/accounts" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['result'][0]['id'] if d.get('success') and d.get('result') else 'ERROR')
" 2>/dev/null)
[[ "$ACCOUNT_ID" == "ERROR" || -z "$ACCOUNT_ID" ]] && { log_error "Token 无效或无账户权限"; exit 1; }
log_info "账户验证通过"

# 获取 zone_id
ROOT_DOMAIN=$(echo "$BASE_DOMAIN" | rev | cut -d. -f1,2,3 | rev)
# 尝试 2 级和 3 级域名匹配
ZONE_ID=""
for try_domain in "$BASE_DOMAIN" "$ROOT_DOMAIN"; do
    ZONE_ID=$(cf_api GET "/zones?name=$try_domain" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['result'][0]['id'] if d.get('success') and d.get('result') else '')
" 2>/dev/null)
    [[ -n "$ZONE_ID" ]] && { BASE_DOMAIN="$try_domain"; break; }
done
# 如果 BASE_DOMAIN 本身就是 zone（如 yanhuang.cc.cd），上面已处理
if [[ -z "$ZONE_ID" ]]; then
    ZONE_ID=$(cf_api GET "/zones?name=$BASE_DOMAIN" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['result'][0]['id'] if d.get('success') and d.get('result') else '')
" 2>/dev/null)
fi
[[ -z "$ZONE_ID" ]] && { log_error "找不到域名 $BASE_DOMAIN 的 Zone，请确认域名已托管在该 CF 账号"; exit 1; }

# 如果用户输入的是子域名，重新生成完整 hostname
if [[ "$HOSTNAME" != *"$BASE_DOMAIN" ]]; then
    HOSTNAME="$SUBDOMAIN.$BASE_DOMAIN"
fi
log_info "域名 Zone: $BASE_DOMAIN"

# ---- 安装 cloudflared ----
echo ""
log_info "安装 cloudflared..."
if ! command -v cloudflared &>/dev/null; then
    curl -sSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-$ARCH" -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
fi
log_info "cloudflared 就绪"

# ---- 创建系统用户 ----
echo ""
log_info "创建 SSH 用户..."
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash "$USERNAME"
fi
echo "$USERNAME:$PASSWORD" | chpasswd

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-cf-tunnel.conf << EOF
# cf-ssh-tunnel 生成
Match User $USERNAME
    PasswordAuthentication yes
    PubkeyAuthentication no
EOF
systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
log_info "用户 $USERNAME 已创建"

# ---- 创建隧道 ----
echo ""
log_info "创建 Cloudflare 隧道..."
TUNNEL_SECRET=$(openssl rand -base64 32 | tr -d '\n')
TUNNEL_ID=$(cf_api POST "/accounts/$ACCOUNT_ID/cfd_tunnel" "{\"name\":\"$TUNNEL_NAME\",\"tunnel_secret\":\"$TUNNEL_SECRET\"}" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['result']['id'] if d.get('success') else 'ERROR:'+str(d.get('errors')))
" 2>/dev/null)
[[ "$TUNNEL_ID" == ERROR* ]] && { log_error "创建隧道失败: $TUNNEL_ID"; exit 1; }
log_info "隧道已创建: $TUNNEL_NAME"

# 配置 ingress
cf_api PUT "/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
    "{\"config\":{\"ingress\":[{\"hostname\":\"$HOSTNAME\",\"service\":\"ssh://localhost:22\"},{\"service\":\"http_status:404\"}]}}" > /dev/null
log_info "隧道路由已配置"

# 创建 DNS
DNS_RESULT=$(cf_api POST "/zones/$ZONE_ID/dns_records" \
    "{\"type\":\"CNAME\",\"name\":\"$HOSTNAME\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('OK' if d.get('success') else 'ERROR:'+str(d.get('errors')))
" 2>/dev/null)
[[ "$DNS_RESULT" != "OK" ]] && log_warn "DNS 创建可能失败: $DNS_RESULT" || log_info "DNS 记录已创建"

# 获取隧道 Token
TUNNEL_TOKEN=$(cf_api GET "/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/token" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['result'] if d.get('success') else 'ERROR')
" 2>/dev/null)
[[ "$TUNNEL_TOKEN" == "ERROR" || -z "$TUNNEL_TOKEN" ]] && { log_error "获取隧道 Token 失败"; exit 1; }

# ---- systemd 服务 ----
log_info "启动隧道服务..."
cat > /etc/systemd/system/cf-ssh-tunnel.service << EOF
[Unit]
Description=Cloudflare Tunnel for SSH
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate run --token $TUNNEL_TOKEN
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
chmod 600 /etc/systemd/system/cf-ssh-tunnel.service
systemctl daemon-reload
systemctl enable cf-ssh-tunnel 2>/dev/null
systemctl restart cf-ssh-tunnel
sleep 3
systemctl is-active cf-ssh-tunnel &>/dev/null && log_info "隧道运行中" || log_warn "隧道启动异常，请检查"

# ---- 保存配置（不含密码） ----
mkdir -p /etc/cf-ssh-tunnel
cat > /etc/cf-ssh-tunnel/config << EOF
USERNAME="$USERNAME"
HOSTNAME="$HOSTNAME"
TUNNEL_ID="$TUNNEL_ID"
TUNNEL_NAME="$TUNNEL_NAME"
EOF
chmod 600 /etc/cf-ssh-tunnel/config

# ---- 安装管理命令 ----
cat > /usr/local/bin/cf-ssh-tunnel << 'MANAGER_EOF'
#!/bin/bash
# cf-ssh-tunnel 管理菜单
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; SKYBLUE='\033[0;36m'; NC='\033[0m'
CONFIG="/etc/cf-ssh-tunnel/config"
[[ -f "$CONFIG" ]] && source "$CONFIG"

show_menu() {
    echo -e "${SKYBLUE}"
    echo "  cf-ssh-tunnel 管理面板"
    echo -e "${NC}"
    echo "  1. 查看连接信息"
    echo "  2. 更换密码"
    echo "  3. 重启隧道"
    echo "  4. 查看隧道状态"
    echo "  5. 查看隧道日志"
    echo "  0. 卸载"
    echo ""
}

show_info() {
    echo ""
    echo -e "${GREEN}连接信息：${NC}"
    echo "  域名:     $HOSTNAME"
    echo "  用户名:   $USERNAME"
    echo "  密码:     (安装时已打印，服务器不保存)"
    echo ""
    echo "  SSH 命令:"
    echo "  ssh -o ProxyCommand=\"cloudflared access ssh --hostname $HOSTNAME\" $USERNAME@$HOSTNAME"
    echo ""
}

rotate_pass() {
    [[ $EUID -ne 0 ]] && { echo "请用 root 运行"; return; }
    NEW_PASS=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 20)
    echo "$USERNAME:$NEW_PASS" | chpasswd
    echo ""
    echo -e "${GREEN}密码已更换（只显示一次）：${NC}"
    echo "  新密码: $NEW_PASS"
    echo ""
}

while true; do
    show_menu
    read -p "请选择 [0-5]: " choice
    case $choice in
        1) show_info ;;
        2) rotate_pass ;;
        3) systemctl restart cf-ssh-tunnel && echo "已重启" ;;
        4) systemctl status cf-ssh-tunnel --no-pager -l | head -20 ;;
        5) journalctl -u cf-ssh-tunnel -n 50 --no-pager ;;
        0)
            read -p "确认卸载？(y/N): " c
            [[ "$c" == "y" || "$c" == "Y" ]] && {
                echo "请输入 Cloudflare API Token 以删除隧道:"
                read -p "Token: " DEL_TOKEN
                bash <(curl -Ls https://raw.githubusercontent.com/zhang123999-qq/cf-ssh-tunnel/main/uninstall.sh) --cf-token "$DEL_TOKEN"
                exit 0
            }
            ;;
        *) echo "无效选择" ;;
    esac
    echo ""
    read -p "按回车继续..."
    clear
done
MANAGER_EOF
chmod +x /usr/local/bin/cf-ssh-tunnel

# ---- 完成，打印凭证 ----
echo ""
echo -e "${GREEN}=============================================="
echo "  安装完成！"
echo -e "==============================================${NC}"
echo ""
echo "  域名:     $HOSTNAME"
echo "  用户名:   $USERNAME"
echo "  密码:     $PASSWORD"
echo ""
echo "  连接命令:"
echo "  ssh -o ProxyCommand=\"cloudflared access ssh --hostname $HOSTNAME\" $USERNAME@$HOSTNAME"
echo ""
echo -e "  管理面板: ${SKYBLUE}cf-ssh-tunnel${NC}"
echo ""
echo -e "  ${YELLOW}注意：密码只显示一次，服务器不保存，请立即记录！${NC}"
echo ""
