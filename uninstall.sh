#!/bin/bash
#
# cfssh 卸载
#
# 可单独运行:
#   bash <(curl -Ls https://raw.githubusercontent.com/zhang123999-qq/cfssh/main/uninstall.sh) --cf-token "你的Token"
#
# 或通过管理面板: cfssh -> 0
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}请用 root 运行${NC}"; exit 1; }

# 依赖检查（卸载只需要 curl 和 python3，缺了就报错不自动装）
command -v python3 &>/dev/null || { echo -e "${RED}需要 python3${NC}"; exit 1; }
command -v curl &>/dev/null || { echo -e "${RED}需要 curl${NC}"; exit 1; }

CF_TOKEN=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --cf-token) CF_TOKEN="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "$CF_TOKEN" ]]; then
    read -s -p "请输入 Cloudflare API Token: " CF_TOKEN
    echo ""
    [[ -z "$CF_TOKEN" ]] && { echo -e "${RED}Token 不能为空${NC}"; exit 1; }
fi

CONFIG="/etc/cfssh/config"
if [[ ! -f "$CONFIG" ]]; then
    echo -e "${YELLOW}未找到安装记录，可能未安装${NC}"
    exit 1
fi
source "$CONFIG"

echo ""
echo -e "${YELLOW}即将删除：${NC}"
echo "  用户: $USERNAME"
echo "  域名: $HOSTNAME"
echo "  隧道: $TUNNEL_NAME"
echo ""
read -p "确认卸载？(y/N): " confirm
[[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "已取消"; exit 0; }

CF_API="https://api.cloudflare.com/client/v4"

# 停止服务
echo -e "${GREEN}[1/5]${NC} 停止隧道服务..."
systemctl stop cfssh 2>/dev/null
systemctl disable cfssh 2>/dev/null
rm -f /etc/systemd/system/cfssh.service
# 停止并删除密码过期计时器
systemctl stop cfssh-expire.timer 2>/dev/null
systemctl disable cfssh-expire.timer 2>/dev/null
rm -f /etc/systemd/system/cfssh-expire.timer /etc/systemd/system/cfssh-expire.service
systemctl daemon-reload

# 删除管理命令
echo -e "${GREEN}[2/5]${NC} 删除管理命令..."
rm -f /usr/local/bin/cfssh

# 删除用户
echo -e "${GREEN}[3/5]${NC} 删除用户 $USERNAME..."
userdel -r "$USERNAME" 2>/dev/null
rm -f /etc/ssh/sshd_config.d/99-cf-tunnel.conf
systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null

# 删除 CF 隧道和 DNS
echo -e "${GREEN}[4/5]${NC} 删除 Cloudflare 隧道和 DNS..."
ACCOUNT_ID=$(curl -s "$CF_API/accounts" -H "Authorization: Bearer $CF_TOKEN" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d['result'][0]['id'] if d.get('success') and d.get('result') else '')
" 2>/dev/null)
if [[ -n "$ACCOUNT_ID" ]]; then
    curl -s -X DELETE "$CF_API/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID?cascade=true" \
        -H "Authorization: Bearer $CF_TOKEN" > /dev/null
    echo "  隧道已删除"
    # 删除 DNS 记录
    if [[ -n "$ZONE_ID" && -n "$DNS_RECORD_ID" ]]; then
        curl -s -X DELETE "$CF_API/zones/$ZONE_ID/dns_records/$DNS_RECORD_ID" \
            -H "Authorization: Bearer $CF_TOKEN" > /dev/null
        echo "  DNS 记录已删除"
    fi
else
    echo -e "  ${YELLOW}Token 无效，跳过隧道删除（请手动在 CF 后台删）${NC}"
fi

# 清理配置
echo -e "${GREEN}[5/5]${NC} 清理配置文件..."
rm -rf /etc/cfssh

echo ""
echo -e "${GREEN}卸载完成${NC}"
