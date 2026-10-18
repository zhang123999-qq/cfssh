#!/bin/bash
#
# cfssh 一键安装（3X-UI 风格）
#
# 安装:
#   bash <(curl -Ls https://raw.githubusercontent.com/zhang123999-qq/cfssh/main/install.sh)
#
# 安装后管理:
#   cfssh
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

# ---- 依赖检查 ----
command -v python3 &>/dev/null || { log_error "需要 python3，请先安装"; exit 1; }
command -v curl &>/dev/null || { log_error "需要 curl，请先安装"; exit 1; }
command -v openssl &>/dev/null || { log_error "需要 openssl，请先安装"; exit 1; }

# ---- 防止重复安装 ----
if [[ -f /etc/cfssh/config ]]; then
    log_error "检测到已安装。如需重装请先运行 cfssh -> 0 卸载"
    exit 1
fi

# ---- 交互式输入 ----
echo ""
read -s -p "请输入 Cloudflare API Token: " CF_TOKEN
echo ""
[[ -z "$CF_TOKEN" ]] && { log_error "Token 不能为空"; exit 1; }

read -p "请输入域名 (如 yanhuang.cc.cd): " BASE_DOMAIN
[[ -z "$BASE_DOMAIN" ]] && { log_error "域名不能为空"; exit 1; }

# 严格校验域名格式（防命令注入）
if ! [[ "$BASE_DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    log_error "域名格式非法"
    exit 1
fi

# ---- 随机生成 ----
gen_username() { echo "u$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)"; }
gen_password() { tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 20; echo; }
gen_subdomain() { tr -dc '0-9' < /dev/urandom | head -c 10; echo; }

USERNAME=$(gen_username)
PASSWORD=$(gen_password)
SUBDOMAIN=$(gen_subdomain)
TUNNEL_NAME="ssh-$SUBDOMAIN"
# HOSTNAME 在 zone 查找到后生成

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

# 获取 zone_id（从完整域名逐级向上查找）
ZONE_ID=""
check_domain="$BASE_DOMAIN"
while [[ -n "$check_domain" ]]; do
    ZONE_ID=$(cf_api GET "/zones?name=$check_domain" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['result'][0]['id'] if d.get('success') and d.get('result') else '')
" 2>/dev/null)
    if [[ -n "$ZONE_ID" ]]; then
        ZONE_NAME="$check_domain"
        break
    fi
    # 去掉最左一段，继续向上找
    if [[ "$check_domain" == *.*.* ]]; then
        check_domain="${check_domain#*.}"
    else
        break
    fi
done
[[ -z "$ZONE_ID" ]] && { log_error "找不到域名 $BASE_DOMAIN 的 Zone，请确认域名已托管在该 CF 账号"; exit 1; }

# 完整 hostname：随机前缀 + zone 域名
HOSTNAME="$SUBDOMAIN.$ZONE_NAME"
log_info "域名 Zone: $ZONE_NAME"

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
# cfssh 生成
Match User $USERNAME
    PasswordAuthentication yes
    PubkeyAuthentication yes
EOF
systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
log_info "用户 $USERNAME 已创建"

# ---- 密码 24 小时后失效（systemd timer 一次性任务） ----
log_info "设置密码 24 小时有效期..."
cat > /etc/systemd/system/cfssh-expire.service << EOF
[Unit]
Description=Expire cfssh password after 24h

[Service]
Type=oneshot
ExecStart=/usr/sbin/passwd -l $USERNAME
ExecStartPost=/usr/bin/logger -t cfssh "Password expired for $USERNAME (24h)"
EOF
cat > /etc/systemd/system/cfssh-expire.timer << EOF
[Unit]
Description=Expire cfssh password 24h after install

[Timer]
OnActiveSec=24h
Unit=cfssh-expire.service

[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now cfssh-expire.timer 2>/dev/null
log_info "密码将在 24 小时后自动失效"

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
DNS_RESP=$(cf_api POST "/zones/$ZONE_ID/dns_records" \
    "{\"type\":\"CNAME\",\"name\":\"$HOSTNAME\",\"content\":\"$TUNNEL_ID.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")
DNS_RECORD_ID=$(echo "$DNS_RESP" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['result']['id'] if d.get('success') else '')
" 2>/dev/null)
[[ -z "$DNS_RECORD_ID" ]] && log_warn "DNS 创建可能失败" || log_info "DNS 记录已创建"

# 获取隧道 Token
TUNNEL_TOKEN=$(cf_api GET "/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/token" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['result'] if d.get('success') else 'ERROR')
" 2>/dev/null)
[[ "$TUNNEL_TOKEN" == "ERROR" || -z "$TUNNEL_TOKEN" ]] && { log_error "获取隧道 Token 失败"; exit 1; }

# ---- systemd 服务 ----
log_info "启动隧道服务..."
cat > /etc/systemd/system/cfssh.service << EOF
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
chmod 600 /etc/systemd/system/cfssh.service
systemctl daemon-reload
systemctl enable cfssh 2>/dev/null
systemctl restart cfssh
sleep 3
systemctl is-active cfssh &>/dev/null && log_info "隧道运行中" || log_warn "隧道启动异常，请检查"

# ---- 保存配置（不含密码） ----
mkdir -p /etc/cfssh
cat > /etc/cfssh/config << EOF
USERNAME="$USERNAME"
HOSTNAME="$HOSTNAME"
TUNNEL_ID="$TUNNEL_ID"
TUNNEL_NAME="$TUNNEL_NAME"
ZONE_ID="$ZONE_ID"
DNS_RECORD_ID="$DNS_RECORD_ID"
EOF
chmod 600 /etc/cfssh/config

# ---- 安装管理命令 ----
cat > /usr/local/bin/cfssh << 'MANAGER_EOF'
#!/bin/bash
# cfssh 管理菜单
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; SKYBLUE='\033[0;36m'; NC='\033[0m'
CONFIG="/etc/cfssh/config"
[[ -f "$CONFIG" ]] && source "$CONFIG"

show_menu() {
    echo -e "${SKYBLUE}"
    echo "  cfssh 管理面板"
    echo -e "${NC}"
    echo "  1. 查看连接信息"
    echo "  2. 更换密码（重置24小时有效期）"
    echo "  3. 添加 SSH 公钥"
    echo "  4. 重启隧道"
    echo "  5. 查看隧道状态"
    echo "  6. 查看隧道日志"
    echo "  0. 卸载"
    echo ""
}

show_info() {
    echo ""
    echo -e "${GREEN}连接信息：${NC}"
    echo "  域名:     $HOSTNAME"
    echo "  用户名:   $USERNAME"
    echo "  密码:     (安装时已打印，服务器不保存，24小时后失效)"
    echo ""
    echo "  SSH 命令:"
    echo "  ssh -o ProxyCommand=\"cloudflared access ssh --hostname $HOSTNAME\" $USERNAME@$HOSTNAME"
    echo ""
    echo -e "  ${YELLOW}建议配置 SSH 密钥以免密码过期后无法登录${NC}"
    echo ""
}

rotate_pass() {
    [[ $EUID -ne 0 ]] && { echo "请用 root 运行"; return; }
    NEW_PASS=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 20)
    # 解锁（如果已过期）并设置新密码
    passwd -u "$USERNAME" 2>/dev/null
    echo "$USERNAME:$NEW_PASS" | chpasswd
    # 重置 24 小时计时器
    systemctl restart cfssh-expire.timer 2>/dev/null
    echo ""
    echo -e "${GREEN}密码已更换（只显示一次，24小时后失效）：${NC}"
    echo "  新密码: $NEW_PASS"
    echo ""
}

add_pubkey() {
    [[ $EUID -ne 0 ]] && { echo "请用 root 运行"; return; }
    echo ""
    echo "请粘贴 SSH 公钥（以 ssh- 开头的一整行），Ctrl+D 结束："
    PUBKEY=$(cat)
    if [[ "$PUBKEY" =~ ^ssh-(rsa|ed25519|ecdsa) ]]; then
        USER_HOME=$(eval echo ~$USERNAME)
        mkdir -p "$USER_HOME/.ssh"
        echo "$PUBKEY" >> "$USER_HOME/.ssh/authorized_keys"
        chmod 700 "$USER_HOME/.ssh"
        chmod 600 "$USER_HOME/.ssh/authorized_keys"
        chown -R "$USERNAME:$USERNAME" "$USER_HOME/.ssh"
        echo -e "${GREEN}公钥已添加，密钥登录不受 24 小时限制${NC}"
    else
        echo -e "${RED}公钥格式不正确${NC}"
    fi
    echo ""
}

while true; do
    show_menu
    read -p "请选择 [0-6]: " choice
    case $choice in
        1) show_info ;;
        2) rotate_pass ;;
        3) add_pubkey ;;
        4) systemctl restart cfssh && echo "已重启" ;;
        5) systemctl status cfssh --no-pager -l | head -20 ;;
        6) journalctl -u cfssh -n 50 --no-pager ;;
        0)
            read -p "确认卸载？(y/N): " c
            [[ "$c" == "y" || "$c" == "Y" ]] && {
                echo "请输入 Cloudflare API Token 以删除隧道:"
                read -s -p "Token: " DEL_TOKEN
                echo ""
                curl -Ls https://raw.githubusercontent.com/zhang123999-qq/cfssh/main/uninstall.sh | bash -s -- --cf-token "$DEL_TOKEN"
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
chmod +x /usr/local/bin/cfssh

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
echo -e "  管理面板: ${SKYBLUE}cfssh${NC}"
echo ""
echo -e "  ${YELLOW}注意：${NC}"
echo -e "  - 密码只显示一次，服务器不保存，请立即记录！"
echo -e "  - ${RED}密码 24 小时后自动失效${NC}，到期后用 cfssh -> 2 换新密码"
echo -e "  - 建议用 cfssh -> 3 添加 SSH 公钥，密钥登录不受时间限制"
echo ""
