# cf-ssh-tunnel

通过 Cloudflare Tunnel（Argo）为内网/无公网 IP 的服务器提供 SSH 访问，一键安装。

## 特点

- **内网穿透**：服务器无需公网 IP，只需能访问互联网
- **全随机凭证**：用户名、密码、域名前缀全部随机生成
- **密码每日轮换**：每 24 小时自动更换密码，邮件通知
- **密码不落盘**：密码只在安装时打印一次，服务器上不保存
- **一键安装/卸载**

## 快速开始

### 服务端（一键安装）

```bash
curl -sSL https://raw.githubusercontent.com/zhang123999-qq/cf-ssh-tunnel/main/install.sh | sudo bash -s -- \
  --cf-token "你的Cloudflare API Token" \
  --domain "example.com" \
  --notify-email "you@example.com"
```

需要准备：
1. **Cloudflare API Token**：在 [API Tokens](https://dash.cloudflare.com/profile/api-tokens) 创建，需要权限：
   - `Tunnel:Edit`
   - `DNS:Edit`
2. **域名**：已托管在 Cloudflare 的域名
3. **邮箱**：接收每日新密码

安装完成后，终端会打印（**只显示一次**）：
```
域名:     0811519409.example.com
用户名:   u7k2m9p4x
密码:     K9#mQ2$vL8@nP4!xR6&
```

### 客户端连接

1. 安装 `cloudflared`：
   ```bash
   # Ubuntu/Debian
   curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
   chmod +x /usr/local/bin/cloudflared
   
   # macOS
   brew install cloudflared
   
   # Termux (Android)
   pkg install cloudflared
   ```

2. 配置 SSH（`~/.ssh/config`）：
   ```
   Host myserver
       HostName 0811519409.example.com
       User u7k2m9p4x
       ProxyCommand cloudflared access ssh --hostname %h
   ```

3. 连接：
   ```bash
   ssh myserver
   # 输入邮件里的当天密码
   ```

## 密码轮换

- 每天 00:00（服务器时间）自动更换密码
- 新密码发送到安装时指定的邮箱
- 旧密码立即失效

## 卸载

```bash
curl -sSL https://raw.githubusercontent.com/zhang123999-qq/cf-ssh-tunnel/main/uninstall.sh | sudo bash -s -- \
  --cf-token "你的Cloudflare API Token"
```

## 安全说明

- 隧道 Token 以 600 权限保存在 systemd 服务文件中
- 密码永不写入磁盘
- 建议配合 Cloudflare Access 使用，添加身份验证层
- 定期检查 Cloudflare 后台的隧道状态

## License

MIT
