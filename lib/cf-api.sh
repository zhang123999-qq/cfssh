#!/bin/bash
# Cloudflare API 封装

CF_API="https://api.cloudflare.com/client/v4"

# 创建隧道，返回 tunnel_id
# 需要 Token 权限: Tunnel:Edit
cf_create_tunnel() {
    local token="$1"
    local account_id="$2"
    local name="$3"
    local resp=$(curl -s -X POST "$CF_API/accounts/$account_id/cfd_tunnel" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        --data "{\"name\":\"$name\",\"tunnel_secret\":\"$(openssl rand -base64 32 | tr -d '\n')\"}")
    echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['id'] if d.get('success') else 'ERROR:'+str(d.get('errors')))"
}

# 获取隧道 Token（用于 cloudflared run --token）
# 需要 Token 权限: Tunnel:Read
cf_get_tunnel_token() {
    local token="$1"
    local account_id="$2"
    local tunnel_id="$3"
    local resp=$(curl -s "$CF_API/accounts/$account_id/cfd_tunnel/$tunnel_id/token" \
        -H "Authorization: Bearer $token")
    echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'] if d.get('success') else 'ERROR')"
}

# 配置隧道 ingress 规则（hostname -> ssh://localhost:22）
# 需要 Token 权限: Tunnel:Edit
cf_set_ingress() {
    local token="$1"
    local account_id="$2"
    local tunnel_id="$3"
    local hostname="$4"
    curl -s -X PUT "$CF_API/accounts/$account_id/cfd_tunnel/$tunnel_id/configurations" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        --data "{\"config\":{\"ingress\":[{\"hostname\":\"$hostname\",\"service\":\"ssh://localhost:22\"},{\"service\":\"http_status:404\"}]}}"
}

# 创建 DNS CNAME 记录指向隧道
# 需要 Token 权限: DNS:Edit
cf_create_dns() {
    local token="$1"
    local zone_id="$2"
    local name="$3"
    local tunnel_id="$4"
    local resp=$(curl -s -X POST "$CF_API/zones/$zone_id/dns_records" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"$name\",\"content\":\"$tunnel_id.cfargotunnel.com\",\"ttl\":1,\"proxied\":true}")
    echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print('OK' if d.get('success') else 'ERROR:'+str(d.get('errors')))"
}

# 删除隧道
cf_delete_tunnel() {
    local token="$1"
    local account_id="$2"
    local tunnel_id="$3"
    curl -s -X DELETE "$CF_API/accounts/$account_id/cfd_tunnel/$tunnel_id?cascade=true" \
        -H "Authorization: Bearer $token" > /dev/null
}

# 通过域名查 zone_id
cf_get_zone_id() {
    local token="$1"
    local domain="$2"
    # 取主域名（最后两段）
    local root=$(echo "$domain" | rev | cut -d. -f1,2 | rev)
    local resp=$(curl -s "$CF_API/zones?name=$root" -H "Authorization: Bearer $token")
    echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'][0]['id'] if d.get('result') else 'ERROR')"
}

# 获取 account_id（取第一个）
cf_get_account_id() {
    local token="$1"
    local resp=$(curl -s "$CF_API/accounts" -H "Authorization: Bearer $token")
    echo "$resp" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result'][0]['id'] if d.get('result') else 'ERROR')"
}
