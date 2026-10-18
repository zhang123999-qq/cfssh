# cfssh

通过 Cloudflare Tunnel（Argo）为内网/无公网 IP 的服务器提供 SSH 访问，一键安装。

## 特点

- **内网穿透**：服务器无需公网 IP，只需能访问互联网
- **全随机凭证**：用户名、密码、域名前缀全部随机生成
- **密码不落盘**：密码只在控制台打印一次，服务器上不保存
- **3X-UI 式管理**：一条命令安装，`cfssh` 进管理面板

## 安装

```bash
bash <(curl -Ls https://raw.githubusercontent.com/zhang123999-qq/cfssh/main/install.sh)
```

按提示输入：
1. **Cloudflare API Token**：在 [API Tokens](https://dash.cloudflare.com/profile/api-tokens) 创建，需要权限：
   - `Account` → `Cloudflare Tunnel` → `Edit`
   - `Zone` → `Zone` → `Read`
   - `Zone` → `DNS` → `Edit`
2. **域名**：已托管在该 Cloudflare 账号下的域名（如 `yanhuang.cc.cd`）

安装完成后终端打印（**只显示一次，请立即记录**）：
```
域名:     0811519409.yanhuang.cc.cd
用户名:   u7k2m9p4x
密码:     K9#mQ2$vL8@nP4!xR6&
```

## 管理面板

```bash
cfssh
```

```
  cfssh 管理面板

  1. 查看连接信息
  2. 更换密码
  3. 重启隧道
  4. 查看隧道状态
  5. 查看隧道日志
  0. 卸载
```

## 客户端连接

1. 安装 `cloudflared`：
   ```bash
   # Linux
   curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
   chmod +x /usr/local/bin/cloudflared

   # macOS
   brew install cloudflared

   # Termux (Android)
   pkg install cloudflared
   ```

2. `~/.ssh/config` 添加：
   ```
   Host myserver
       HostName 0811519409.yanhuang.cc.cd
       User u7k2m9p4x
       ProxyCommand cloudflared access ssh --hostname %h
   ```

3. 连接：`ssh myserver`，输入安装时打印的密码

## 卸载

```bash
# 方式一：管理面板
cfssh
# 选 0

# 方式二：直接运行
bash <(curl -Ls https://raw.githubusercontent.com/zhang123999-qq/cfssh/main/uninstall.sh)
```

## 安全说明

- 隧道 Token 以 600 权限保存在 systemd 服务文件
- 密码永不写入磁盘
- 卸载后请手动删除 DNS 记录

## License

MIT
