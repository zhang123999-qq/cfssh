#!/bin/bash
# 用户管理：创建用户、设置密码
# 注意：密码永不落盘，只通过管道传递

# 创建随机用户
# 参数: $1=用户名 $2=密码
create_ssh_user() {
    local username="$1"
    local password="$2"

    # 创建用户（无密码过期，主组 users）
    if ! id "$username" &>/dev/null; then
        useradd -m -s /bin/bash "$username"
        log_info "用户 $username 已创建"
    else
        log_warn "用户 $username 已存在，跳过创建"
    fi

    # 设置密码（通过管道，不留在历史记录）
    echo "$username:$password" | chpasswd
    log_info "密码已设置"

    # 确保 SSH 允许密码登录（仅对此用户）
    # 在 sshd_config.d/ 加独立配置，不动主文件
    mkdir -p /etc/ssh/sshd_config.d
    cat > /etc/ssh/sshd_config.d/99-cf-tunnel.conf << EOF
# cf-ssh-tunnel 生成，请勿手动修改
Match User $username
    PasswordAuthentication yes
    PubkeyAuthentication no
EOF
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    log_info "sshd 配置已重载"
}

# 轮换密码
# 参数: $1=用户名 $2=新密码
rotate_password() {
    local username="$1"
    local new_password="$2"
    echo "$username:$new_password" | chpasswd
}

# 删除用户
delete_ssh_user() {
    local username="$1"
    userdel -r "$username" 2>/dev/null
    rm -f /etc/ssh/sshd_config.d/99-cf-tunnel.conf
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
}
