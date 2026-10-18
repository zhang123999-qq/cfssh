#!/bin/bash
# 通用函数：随机生成、日志、系统检查

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# 生成随机用户名: u + 8位小写字母数字
gen_username() {
    echo "u$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)"
}

# 生成随机密码: 20位，含大小写+数字+符号
gen_password() {
    tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c 20
    echo
}

# 生成10位纯数字域名前缀
gen_subdomain() {
    tr -dc '0-9' < /dev/urandom | head -c 10
    echo
}

# 检查root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请用 root 运行此脚本"
        exit 1
    fi
}

# 检查系统架构
get_arch() {
    local arch=$(uname -m)
    case $arch in
        x86_64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) log_error "不支持的架构: $arch"; exit 1 ;;
    esac
}

# 检查OS
check_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    else
        log_error "无法识别操作系统"
        exit 1
    fi
}
