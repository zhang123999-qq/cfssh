# cfssh

通过 Cloudflare Tunnel（Argo）为内网/无公网 IP 的服务器提供 SSH 访问，一键安装。

## 解决什么问题

- 服务器在内网/NAT 后面，没有公网 IP，想从外面 SSH 进去
- 不想暴露真实 IP，不想开防火墙入站端口
- 想要随机用户名、随机密码、随机域名，用完即走

## 特点

- **内网穿透**：服务器只需能访问互联网，无需公网 IP、不开入站端口
- **全随机凭证**：用户名（`u`+8位）、密码（20位含符号）、域名前缀（10位数字）全部随机
- **密码不落盘**：密码只在控制台打印一次，服务器上不保存任何密码
- **24小时有效期**：密码 24 小时后自动失效，可换新密码或配置 SSH 密钥
- **3X-UI 式管理**：一条命令安装，`cfssh` 进管理面板
- **自动清理**：卸载时自动删除隧道、DNS 记录、系统用户

## 免费账号限制

Cloudflare 免费账号每个账户可创建 **1000 个隧道**，每个隧道最多 25 个副本，带宽不限量。也就是说一台机器装一个，一个免费 CF 账号最多管 1000 台机器，完全够用。

## 安装

```bash
# 交互模式（按提示输入）
bash <(curl -Ls https://raw.githubusercontent.com/zhang123999-qq/cfssh/main/install.sh)

# 非交互模式（用自己的 token，一条命令搞定）
bash <(curl -Ls https://raw.githubusercontent.com/zhang123999-qq/cfssh/main/install.sh) \
  --token "你的Cloudflare API Token" \
  --domain "yanhuang.cc.cd"
```

交互模式按提示输入：

1. **Cloudflare API Token**：在 [API Tokens](https://dash.cloudflare.com/profile/api-tokens) 创建 Custom Token，需要以下权限：

   | 类型 | 项目 | 权限 |
   |---|---|---|
   | Account | Cloudflare Tunnel | Edit |
   | Zone | Zone | Read |
   | Zone | DNS | Edit |

2. **域名**：已托管在该 Cloudflare 账号下的域名（如 `yanhuang.cc.cd`）

安装完成后终端打印（**只显示一次，请立即记录**）：

```
域名:     0811519409.yanhuang.cc.cd
用户名:   u7k2m9p4x
密码:     K9#mQ2$vL8@nP4!xR6&

连接命令:
ssh -o ProxyCommand="cloudflared access ssh --hostname 0811519409.yanhuang.cc.cd" u7k2m9p4x@0811519409.yanhuang.cc.cd
```

## 管理面板

```bash
cfssh
```

```
  cfssh 管理面板

  1. 查看连接信息
  2. 更换密码（重置24小时有效期）
  3. 添加 SSH 公钥
  4. 重启隧道
  5. 查看隧道状态
  6. 查看隧道日志
  0. 卸载
```

## 客户端连接

### 1. 安装 cloudflared

```bash
# Linux (amd64)
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

# Linux (arm64)
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 \
  -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

# macOS
brew install cloudflared

# Windows：从 https://github.com/cloudflare/cloudflared/releases 下载 exe

# Android (Termux)
pkg install cloudflared
```

### 2. 配置 SSH

编辑 `~/.ssh/config`，添加：

```
Host myserver
    HostName 0811519409.yanhuang.cc.cd
    User u7k2m9p4x
    ProxyCommand cloudflared access ssh --hostname %h
```

### 3. 连接

```bash
ssh myserver
# 输入安装时打印的密码
```

## 更换密码

```bash
cfssh
# 选 2，新密码直接打印到控制台，只显示一次，同时重置 24 小时有效期
```

## 添加 SSH 密钥（推荐）

```bash
cfssh
# 选 3，粘贴你的公钥（`~/.ssh/id_ed25519.pub` 的内容）
```

密钥登录不受 24 小时限制，密码过期后仍可用密钥登录。

## 卸载

```bash
# 方式一：管理面板
cfssh
# 选 0

# 方式二：直接运行
bash <(curl -Ls https://raw.githubusercontent.com/zhang123999-qq/cfssh/main/uninstall.sh)
```

卸载会删除：systemd 服务、管理命令、系统用户、Cloudflare 隧道、DNS 记录、配置文件。

## 工作原理

```
你的电脑                          Cloudflare                    内网服务器
   |                                  |                              |
   |  ssh via cloudflared             |                              |
   |--------------------------------->|                              |
   |                                  |  经已建立的隧道转发               |
   |                                  |----------------------------->|
   |                                  |                              |--> localhost:22
```

服务器上的 `cloudflared` 主动向 Cloudflare 发起**出站**连接（只需能上网），Cloudflare 收到你的 SSH 请求后经隧道转发回去。全程不暴露真实 IP，NAT/防火墙都能穿透。

## 安全说明

- 隧道 Token 以 600 权限保存在 systemd 服务文件，仅 root 可读
- 密码永不写入磁盘，只在控制台打印一次
- SSH 用户仅允许密码登录、禁止密钥登录（独立 Match 块，不影响其他用户）
- 建议配合 [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/) 添加身份验证层

## 常见问题

**Q: 支持哪些系统？**
A: 需 systemd 的 Linux（Ubuntu/Debian/CentOS 等），支持 amd64/arm64。

**Q: 密码忘了怎么办？**
A: 服务器上跑 `cfssh` → 选 2 换个新密码（同时重置 24 小时有效期）。

**Q: 密码 24 小时后失效了怎么办？**
A: 两种办法：① 服务器上 `cfssh` → 选 2 换新密码；② 提前用 `cfssh` → 选 3 添加 SSH 公钥，密钥登录不受时间限制。

**Q: 换了密码旧的还能用吗？**
A: 不能，`chpasswd` 直接覆盖，旧密码立即失效。

**Q: 能同时装多个吗？**
A: 一台机器只能装一个，重复安装会被拒绝。需要多个请先卸载。

**Q: 隧道掉了怎么办？**
A: systemd 会自动重启（`Restart=always`）。`cfssh` → 选 4/5 看状态和日志。

**Q: 非交互安装怎么做？**
A: `bash <(curl -Ls URL) --token "你的Token" --domain "你的域名"`，适合批量部署多台机器。

**Q: 免费账号能建多少个？**
A: 1000 个隧道/账号，每个隧道 25 副本，带宽不限。

## License

MIT
