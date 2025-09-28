#!/bin/bash

# 交叉编译工具链一键安装脚本
# 适用于 Ubuntu 20.04 LTS
# 作者：自动生成
# 日期：$(date +%Y-%m-%d)

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为 Ubuntu 20.04
check_system() {
    log_info "检查系统版本..."
    
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法检测系统版本"
        exit 1
    fi
    
    source /etc/os-release
    
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "此脚本仅适用于 Ubuntu 系统，当前系统：$ID"
        exit 1
    fi
    
    log_success "系统检查通过：Ubuntu $VERSION_ID"
}

# 检查网络连接
check_network() {
    log_info "检查网络连接..."
    
    if ! ping -c 1 www.bing.com &> /dev/null; then
        log_error "无法连接到 Ubuntu 软件源，请检查网络连接"
        exit 1
    fi
    
    log_success "网络连接正常"
}

# 更新系统
update_system() {
    log_info "更新系统包列表..."
    
    apt update
    log_success "包列表更新完成"
    
    log_info "安装基础构建工具..."
    apt install -y build-essential cmake git wget curl
    log_success "基础构建工具安装完成"
}

# 安装 GNU 交叉编译工具链
install_gnu_toolchains() {
    log_info "开始安装 GNU 交叉编译工具链..."
    
    # ARM 32位
    log_info "安装 arm-linux-gnu-gcc..."
    apt install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf libc6-dev-armhf-cross
    
    # ARM 64位
    log_info "安装 aarch64-linux-gnu-gcc..."
    apt install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu libc6-dev-arm64-cross
    
    # RISC-V 64位
    log_info "安装 riscv64-linux-gnu-gcc..."
    apt install -y gcc-riscv64-linux-gnu g++-riscv64-linux-gnu libc6-dev-riscv64-cross
    
    log_success "GNU 交叉编译工具链安装完成"
}

# 验证 GNU 工具链安装
verify_gnu_toolchains() {
    log_info "验证 GNU 交叉编译工具链..."
    
    local tools=(
        "arm-linux-gnueabihf-gcc"
        "aarch64-linux-gnu-gcc"
        "riscv64-linux-gnu-gcc"
    )
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            local version=$($tool --version | head -n1)
            log_success "$tool: $version"
        else
            log_error "$tool 未找到"
            return 1
        fi
    done
}

# 安装 musl 交叉编译工具链
install_musl_toolchains() {
    log_info "开始安装 musl 交叉编译工具链..."
    
    # 创建工具链目录
    mkdir -p /opt/cross
    cd /tmp
    
    # 下载并安装 aarch64-linux-musl
    log_info "下载并安装 aarch64-linux-musl-gcc..."
    if [[ ! -f aarch64-linux-musl-cross.tgz ]]; then
        wget -O aarch64-linux-musl-cross.tgz "https://more.musl.cc/10/x86_64-linux-musl/aarch64-linux-musl-cross.tgz"
    fi
    tar -xzf aarch64-linux-musl-cross.tgz -C /opt/cross/
    
    # 下载并安装 arm-linux-musl
    log_info "下载并安装 arm-linux-musl-gcc..."
    if [[ ! -f arm-linux-musleabihf-cross.tgz ]]; then
        wget -O arm-linux-musleabihf-cross.tgz "https://more.musl.cc/10/x86_64-linux-musl/arm-linux-musleabihf-cross.tgz"
    fi
    tar -xzf arm-linux-musleabihf-cross.tgz -C /opt/cross/
    
    # 下载并安装 riscv64-linux-musl
    log_info "下载并安装 riscv64-linux-musl-gcc..."
    if [[ ! -f riscv64-linux-musl-cross.tgz ]]; then
        wget -O riscv64-linux-musl-cross.tgz "https://more.musl.cc/10/x86_64-linux-musl/riscv64-linux-musl-cross.tgz"
    fi
    tar -xzf riscv64-linux-musl-cross.tgz -C /opt/cross/
    
    log_success "musl 交叉编译工具链下载完成"
}

# 配置环境变量
setup_environment() {
    log_info "配置环境变量..."
    
    local bashrc_file="$HOME/.bashrc"
    local profile_file="/etc/profile.d/cross-toolchain.sh"
    
    # 创建全局环境配置文件
    tee "$profile_file" > /dev/null << 'EOF'
# 交叉编译工具链环境配置
export CROSS_TOOLCHAIN_ROOT="/opt/cross"

# musl 工具链路径
export PATH="/opt/cross/aarch64-linux-musl-cross/bin:$PATH"
export PATH="/opt/cross/arm-linux-musleabihf-cross/bin:$PATH"
export PATH="/opt/cross/riscv64-linux-musl-cross/bin:$PATH"

# 工具链别名（可选）
alias aarch64-musl-gcc='aarch64-linux-musl-gcc'
alias arm-musl-gcc='arm-linux-musleabihf-gcc'
alias riscv64-musl-gcc='riscv64-linux-musl-gcc'
EOF

    chmod +x "$profile_file"
    
    # 为当前用户添加到 .bashrc
    if ! grep -q "/opt/cross" "$bashrc_file" 2>/dev/null; then
        cat >> "$bashrc_file" << 'EOF'

# 交叉编译工具链路径
export PATH="/opt/cross/aarch64-linux-musl-cross/bin:$PATH"
export PATH="/opt/cross/arm-linux-musleabihf-cross/bin:$PATH"
export PATH="/opt/cross/riscv64-linux-musl-cross/bin:$PATH"
EOF
    fi
    
    # 应用环境变量
    source "$profile_file"
    
    log_success "环境变量配置完成"
}

# 验证 musl 工具链安装
verify_musl_toolchains() {
    log_info "验证 musl 交叉编译工具链..."
    
    # 临时添加路径到当前会话
    export PATH="/opt/cross/aarch64-linux-musl-cross/bin:$PATH"
    export PATH="/opt/cross/arm-linux-musleabihf-cross/bin:$PATH"
    export PATH="/opt/cross/riscv64-linux-musl-cross/bin:$PATH"
    
    local tools=(
        "aarch64-linux-musl-gcc"
        "arm-linux-musleabihf-gcc"
        "riscv64-linux-musl-gcc"
    )
    
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            local version=$($tool --version | head -n1)
            log_success "$tool: $version"
        else
            log_error "$tool 未找到，请检查安装"
            return 1
        fi
    done
}

# 创建测试程序
create_test_program() {
    log_info "创建测试程序..."
    
    local test_dir="/tmp/toolchain_test"
    mkdir -p "$test_dir"
    
    cat > "$test_dir/hello.c" << 'EOF'
#include <stdio.h>

int main() {
    printf("Hello, Cross Compilation World!\n");
    return 0;
}
EOF

    echo "$test_dir/hello.c"
}

# 测试所有工具链
test_toolchains() {
    log_info "测试所有交叉编译工具链..."
    
    local test_file=$(create_test_program)
    local test_dir=$(dirname "$test_file")
    
    # 临时添加路径
    export PATH="/opt/cross/aarch64-linux-musl-cross/bin:$PATH"
    export PATH="/opt/cross/arm-linux-musleabihf-cross/bin:$PATH"
    export PATH="/opt/cross/riscv64-linux-musl-cross/bin:$PATH"
    
    local compilers=(
        "arm-linux-gnueabihf-gcc"
        "aarch64-linux-gnu-gcc"
        "riscv64-linux-gnu-gcc"
        "aarch64-linux-musl-gcc"
        "arm-linux-musleabihf-gcc"
        "riscv64-linux-musl-gcc"
    )
    
    for compiler in "${compilers[@]}"; do
        if command -v "$compiler" &> /dev/null; then
            local output_file="$test_dir/hello_${compiler//[-\/]/_}"
            if "$compiler" -o "$output_file" "$test_file" 2>/dev/null; then
                log_success "$compiler 编译测试通过"
            else
                log_warning "$compiler 编译测试失败（可能缺少目标架构的库文件）"
            fi
        else
            log_error "$compiler 未找到"
        fi
    done
    
    # 清理测试文件
    rm -rf "$test_dir"
}

# 显示安装总结
show_summary() {
    echo
    echo "=============================================="
    echo "          交叉编译工具链安装完成"
    echo "=============================================="
    echo
    echo "已安装的工具链："
    echo "  GNU glibc 工具链："
    echo "    - arm-linux-gnueabihf-gcc"
    echo "    - aarch64-linux-gnu-gcc"
    echo "    - riscv64-linux-gnu-gcc"
    echo
    echo "  musl 工具链："
    echo "    - aarch64-linux-musl-gcc"
    echo "    - arm-linux-musleabihf-gcc"
    echo "    - riscv64-linux-musl-gcc"
    echo
    echo "使用方法："
    echo "  1. 重新加载环境变量："
    echo "     source ~/.bashrc"
    echo "     # 或者"
    echo "     source /etc/profile.d/cross-toolchain.sh"
    echo
    echo "  2. 编译示例："
    echo "     arm-linux-gnueabihf-gcc -o hello hello.c"
    echo "     aarch64-linux-gnu-gcc -o hello hello.c"
    echo "     aarch64-linux-musl-gcc -o hello hello.c"
    echo
    echo "  3. 查看工具链版本："
    echo "     aarch64-linux-gnu-gcc --version"
    echo
    echo "相关文档："
    echo "  - README_TOOLCHAIN.md (详细安装文档)"
    echo "  - toolchain/*.cmake (CMake 工具链文件)"
    echo
    echo "=============================================="
}

# 显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help     显示此帮助信息"
    echo "  --skip-test    跳过编译测试步骤"
    echo "  --gnu-only     仅安装 GNU 工具链"
    echo "  --musl-only    仅安装 musl 工具链"
    echo
    echo "支持的交叉编译工具链:"
    echo "  GNU glibc 工具链:"
    echo "    - arm-linux-gnueabihf-gcc"
    echo "    - aarch64-linux-gnu-gcc"
    echo "    - riscv64-linux-gnu-gcc"
    echo
    echo "  musl 工具链:"
    echo "    - aarch64-linux-musl-gcc"
    echo "    - arm-linux-musleabihf-gcc"
    echo "    - riscv64-linux-musl-gcc"
    echo
    echo "示例:"
    echo "  $0                    # 安装所有工具链"
    echo "  $0 --gnu-only        # 仅安装 GNU 工具链"
    echo "  $0 --skip-test       # 安装但跳过测试"
}

# 主函数
main() {
    local skip_test=false
    local gnu_only=false
    local musl_only=false
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --skip-test)
                skip_test=true
                shift
                ;;
            --gnu-only)
                gnu_only=true
                shift
                ;;
            --musl-only)
                musl_only=true
                shift
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    echo "=============================================="
    echo "    Ubuntu 20.04 交叉编译工具链一键安装脚本"
    echo "=============================================="
    echo
    
    # 检查是否以 root 身份运行
    if [[ $EUID -eq 0 ]]; then
        log_error "请不要以 root 身份运行此脚本"
        exit 1
    fi
    
    # 检查 权限
    if ! -n true 2>/dev/null; then
        log_info "此脚本需要 权限，请输入密码"
        true || {
            log_error "需要 权限才能继续"
            exit 1
        }
    fi
    
    # 执行安装步骤
    check_system
    # check_network
    update_system
    
    # 根据参数决定安装哪些工具链
    if [[ "$musl_only" != "true" ]]; then
        install_gnu_toolchains
        verify_gnu_toolchains || {
            log_error "GNU 工具链验证失败"
            exit 1
        }
    fi
    
    if [[ "$gnu_only" != "true" ]]; then
        install_musl_toolchains
        setup_environment
        verify_musl_toolchains || {
            log_warning "musl 工具链验证失败，但安装可能已完成"
        }
    fi
    
    # 测试工具链（如果没有跳过）
    if [[ "$skip_test" != "true" ]]; then
        test_toolchains
    fi
    
    show_summary
    
    log_success "所有工具链安装完成！"
    log_info "请运行 'source ~/.bashrc' 或重新打开终端以应用环境变量"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi