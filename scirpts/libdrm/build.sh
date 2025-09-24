#!/bin/bash

# libdrm 构建脚本
# 支持多种交叉编译工具链编译libdrm库

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLCHAIN_DIR="${WORKSPACE_DIR}/toolchain"
SOURCES_DIR="${WORKSPACE_DIR}/sources"
OUTPUTS_DIR="${WORKSPACE_DIR}/outputs"
LIBDRM_OUTPUT_DIR="${OUTPUTS_DIR}/libdrm"

# libdrm 版本和源码目录
LIBDRM_VERSION="2.4.125"
LIBDRM_SOURCE_DIR="${SOURCES_DIR}/libdrm"
PROJECT_ROOT_DIR="${SCRIPT_DIR}"

# 限制默认编译目标
_DEFAULT_BUILD_TARGETS="glibc_arm64,glibc_arm,android_arm64_v8a,android_armeabi_v7a"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# 从工具链文件提取 CROSS_COMPILE 前缀
get_cross_compile_prefix() {
    local toolchain_file="$1"
    
    if [ ! -f "$toolchain_file" ]; then
        echo ""
        return 1
    fi
    
    # 从 CMake 工具链文件中提取 CROSS_COMPILE 前缀
    local cross_compile_line
    cross_compile_line=$(grep -E "set\s*\(\s*CROSS_COMPILE\s+" "$toolchain_file" | head -1)
    
    if [ -n "$cross_compile_line" ]; then
        # 使用 sed 提取前缀，去掉末尾的 '-'
        local prefix
        prefix=$(echo "$cross_compile_line" | sed -E 's/.*set\s*\(\s*CROSS_COMPILE\s+([a-zA-Z0-9-]+)-\s*\).*/\1/')
        
        if [ -n "$prefix" ] && [ "$prefix" != "$cross_compile_line" ]; then
            echo "${prefix}-"
        else
            echo ""
        fi
    else
        # 如果未找到，返回空字符串（使用系统默认工具）
        echo ""
    fi
}

# 检查交叉编译工具是否可用
check_cross_compile_tools() {
    local cross_prefix="$1"
    local target_name="$2"
    
    log_info "Checking cross-compile tools for $target_name (prefix: ${cross_prefix:-'system'})..."
    
    # 检查压缩相关工具
    local tools_status=""
    
    # strip 工具
    if [ -n "$cross_prefix" ]; then
        if command -v "${cross_prefix}strip" &> /dev/null; then
            tools_status="${tools_status}strip:${cross_prefix}strip "
        elif command -v "strip" &> /dev/null; then
            tools_status="${tools_status}strip:strip "
        fi
    else
        if command -v "strip" &> /dev/null; then
            tools_status="${tools_status}strip:strip "
        fi
    fi
    
    # objcopy 工具
    if [ -n "$cross_prefix" ]; then
        if command -v "${cross_prefix}objcopy" &> /dev/null; then
            tools_status="${tools_status}objcopy:${cross_prefix}objcopy "
        elif command -v "objcopy" &> /dev/null; then
            tools_status="${tools_status}objcopy:objcopy "
        fi
    else
        if command -v "objcopy" &> /dev/null; then
            tools_status="${tools_status}objcopy:objcopy "
        fi
    fi
    
    # UPX 和通用压缩工具
    if command -v "upx" &> /dev/null; then
        tools_status="${tools_status}upx:upx "
    fi
    if command -v "xz" &> /dev/null; then
        tools_status="${tools_status}xz:xz "
    fi
    if command -v "gzip" &> /dev/null; then
        tools_status="${tools_status}gzip:gzip "
    fi
    
    echo "$tools_status"
}

# 检查必要的工具
check_tools() {
    local tools=("meson" "ninja" "wget")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Missing required tool: $tool"
            exit 1
        fi
    done
}

# 应用 meson 时钟偏差补丁
apply_meson_clockskew_patch() {
    log_info "Applying meson clockskew patch..."
    
    local patch_script="${WORKSPACE_DIR}/patches/patch_meson_clockskew.py"
    
    if [ ! -f "$patch_script" ]; then
        log_warning "Meson clockskew patch script not found: $patch_script"
        log_warning "Compilation may fail due to clock skew issues"
        return 0
    fi
    
    # 运行补丁脚本
    if python3 "$patch_script"; then
        log_success "Meson clockskew patch applied successfully"
    else
        log_warning "Failed to apply meson clockskew patch"
        log_warning "Compilation may fail due to clock skew issues"
    fi
}

# 下载libdrm源码
download_libdrm() {
    log_info "Checking libdrm source..."
    
    # 创建sources目录
    mkdir -p "${SOURCES_DIR}"
    
    # 如果目录已存在且包含meson.build，跳过下载
    if [ -d "${LIBDRM_SOURCE_DIR}" ] && [ -f "${LIBDRM_SOURCE_DIR}/meson.build" ]; then
        log_success "libdrm source already exists, skipping download"
        return 0
    fi
    
    # 如果目录存在但不完整，先删除
    if [ -d "${LIBDRM_SOURCE_DIR}" ]; then
        log_warning "Removing incomplete libdrm directory"
        rm -rf "${LIBDRM_SOURCE_DIR}"
    fi
    
    # 下载源码包
    log_info "Downloading libdrm-${LIBDRM_VERSION}..."
    local archive_file="${SOURCES_DIR}/libdrm-${LIBDRM_VERSION}.tar.xz"
    
    wget -O "$archive_file" "https://dri.freedesktop.org/libdrm/libdrm-${LIBDRM_VERSION}.tar.xz"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to download libdrm"
        exit 1
    fi
    
    # 解压源码
    log_info "Extracting libdrm source..."
    cd "${SOURCES_DIR}"
    tar -xf "libdrm-${LIBDRM_VERSION}.tar.xz"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to extract libdrm"
        exit 1
    fi
    
    # 重命名目录
    mv "libdrm-${LIBDRM_VERSION}" "libdrm"
    
    # 清理下载的压缩包
    rm -f "$archive_file"
    
    if [ -f "${LIBDRM_SOURCE_DIR}/meson.build" ]; then
        log_success "libdrm source downloaded and extracted successfully"
    else
        log_error "libdrm source extraction appears to be incomplete"
        exit 1
    fi
}

# 函数：根据目标架构获取系统信息
get_target_info() {
    local target="$1"
    
    case "$target" in
        x86_64-linux-gnu|x86_64-linux-android|x86_64-linux-harmonyos)
            echo "linux x86_64 x86_64 little"
            ;;
        aarch64-linux-gnu|aarch64-linux-android|aarch64-linux-harmonyos|aarch64-macos)
            echo "linux aarch64 aarch64 little"
            ;;
        arm-linux-gnueabihf|arm-linux-android|arm-linux-harmonyos)
            echo "linux arm arm little"
            ;;
        x86-linux-android)
            echo "linux x86 i386 little"
            ;;
        x86_64-windows-gnu)
            echo "windows x86_64 x86_64 little"
            ;;
        aarch64-windows-gnu)
            echo "windows aarch64 aarch64 little"
            ;;
        x86_64-macos)
            echo "darwin x86_64 x86_64 little"
            ;;
        riscv64-linux-gnu)
            echo "linux riscv64 riscv64 little"
            ;;
        loongarch64-linux-gnu)
            echo "linux loongarch64 loongarch64 little"
            ;;
        *)
            echo "linux unknown unknown little"
            ;;
    esac
}

# 创建动态交叉编译配置文件
create_cross_file() {
    local target_name="$1"
    local toolchain_file="$2"
    local is_android="$3"
    
    # 获取目标架构信息
    local target_arch=""
    case "$target_name" in
        "32bit"|"glibc_arm"|"musl_arm64")
            target_arch="arm-linux-gnueabihf"
            ;;
        "64bit"|"glibc_arm64"|"musl")
            target_arch="aarch64-linux-gnu"
            ;;
        "glibc_riscv64"|"musl_riscv64")
            target_arch="riscv64-linux-gnu"
            ;;
        "android_arm64_v8a")
            target_arch="aarch64-linux-android"
            ;;
        "android_armeabi_v7a")
            target_arch="arm-linux-android"
            ;;
        *)
            target_arch="unknown"
            ;;
    esac
    
    TARGET_INFO=($(get_target_info "$target_arch"))
    TARGET_SYSTEM="${TARGET_INFO[0]}"
    TARGET_CPU_FAMILY="${TARGET_INFO[1]}"
    TARGET_CPU="${TARGET_INFO[2]}"
    TARGET_ENDIAN="${TARGET_INFO[3]}"
    
    # 创建动态交叉编译配置文件
    CROSS_FILE="$PROJECT_ROOT_DIR/cross-build.txt"
    
    if [ "$is_android" = "true" ]; then
        # Android 交叉编译配置
        cat > "$CROSS_FILE" << EOF
[binaries]
c = '${TOOLCHAIN}/bin/${ANDROID_TARGET}${API_LEVEL}-clang'
cpp = '${TOOLCHAIN}/bin/${ANDROID_TARGET}${API_LEVEL}-clang++'
ar = '${TOOLCHAIN}/bin/llvm-ar'
strip = '${TOOLCHAIN}/bin/llvm-strip'
pkgconfig = 'pkg-config'

[host_machine]
system = '$TARGET_SYSTEM'
cpu_family = '$TARGET_CPU_FAMILY'
cpu = '$TARGET_CPU'
endian = '$TARGET_ENDIAN'

[built-in options]
c_std = 'c11'
default_library = 'both'
EOF
    else
        # 常规交叉编译配置
        local cross_prefix
        cross_prefix=$(get_cross_compile_prefix "$toolchain_file")
        
        cat > "$CROSS_FILE" << EOF
[binaries]
c = ['${cross_prefix}gcc']
cpp = ['${cross_prefix}g++']
ar = ['${cross_prefix}ar']
strip = ['${cross_prefix}strip']
pkg-config = 'pkg-config'

[host_machine]
system = '$TARGET_SYSTEM'
cpu_family = '$TARGET_CPU_FAMILY'
cpu = '$TARGET_CPU'
endian = '$TARGET_ENDIAN'

[built-in options]
c_std = 'c11'
default_library = 'both'
EOF
    fi
    
    log_info "Created cross-compilation file: $CROSS_FILE"
}

# 获取meson编译选项
get_meson_options() {
    local target="$1"
    local enable_demos="$2"
    
    # Set test and demo options based on user preferences
    local test_options=""
    if [ "$enable_demos" = "true" ]; then
        test_options="-Dtests=true -Dinstall-test-programs=true"
    else
        test_options="-Dtests=false -Dinstall-test-programs=false"
    fi
    
    local meson_options=""
    
    case "$target" in
        x86_64-linux-*|x86-linux-*)
            # x86 Linux - enable all desktop GPU drivers
            meson_options=""
            meson_options+=" -Dintel=auto"
            meson_options+=" -Dradeon=auto"
            meson_options+=" -Damdgpu=auto"
            meson_options+=" -Dnouveau=auto"
            meson_options+=" -Dvmwgfx=auto"
            meson_options+=" -Domap=disabled"
            meson_options+=" -Dexynos=disabled"
            meson_options+=" -Dfreedreno=disabled"
            meson_options+=" -Dtegra=disabled"
            meson_options+=" -Dvc4=disabled"
            meson_options+=" -Detnaviv=disabled"
            meson_options+=" $test_options"
            meson_options+=" -Dman-pages=disabled"
            meson_options+=" -Dvalgrind=disabled"
            meson_options+=" -Dcairo-tests=disabled"
            meson_options+=" -Dudev=true"
            meson_options+=" -Dfreedreno-kgsl=false"
            ;;
        *android*|*harmonyos*)
            # Mobile/embedded platforms - focus on mobile GPU drivers
            meson_options=""
            meson_options+=" -Dintel=disabled"
            meson_options+=" -Dradeon=disabled"
            meson_options+=" -Damdgpu=disabled"
            meson_options+=" -Dnouveau=disabled"
            meson_options+=" -Dvmwgfx=disabled"
            meson_options+=" -Domap=auto"
            meson_options+=" -Dexynos=auto"
            meson_options+=" -Dfreedreno=auto"
            meson_options+=" -Dtegra=auto"
            meson_options+=" -Dvc4=auto"
            meson_options+=" -Detnaviv=auto"
            meson_options+=" $test_options"
            meson_options+=" -Dman-pages=disabled"
            meson_options+=" -Dvalgrind=disabled"
            meson_options+=" -Dcairo-tests=disabled"
            meson_options+=" -Dudev=false"
            meson_options+=" -Dfreedreno-kgsl=true"
            ;;
        aarch64-linux-gnu|arm-linux-gnueabihf|arm-linux-gnu)
            # ARM Linux - enable ARM SoC and PCIe GPU drivers
            meson_options=""
            meson_options+=" -Dintel=disabled"
            meson_options+=" -Dradeon=auto"
            meson_options+=" -Damdgpu=auto"
            meson_options+=" -Dnouveau=auto"
            meson_options+=" -Dvmwgfx=disabled"
            meson_options+=" -Domap=auto"
            meson_options+=" -Dexynos=auto"
            meson_options+=" -Dfreedreno=auto"
            meson_options+=" -Dtegra=auto"
            meson_options+=" -Dvc4=auto"
            meson_options+=" -Detnaviv=auto"
            meson_options+=" $test_options"
            meson_options+=" -Dman-pages=disabled"
            meson_options+=" -Dvalgrind=disabled"
            meson_options+=" -Dcairo-tests=disabled"
            meson_options+=" -Dudev=true"
            meson_options+=" -Dfreedreno-kgsl=false"
            ;;
        *loongarch64*|*riscv64*)
            # Alternative architectures - conservative GPU support
            meson_options=""
            meson_options+=" -Dintel=disabled"
            meson_options+=" -Dradeon=auto"
            meson_options+=" -Damdgpu=auto"
            meson_options+=" -Dnouveau=auto"
            meson_options+=" -Dvmwgfx=disabled"
            meson_options+=" -Domap=disabled"
            meson_options+=" -Dexynos=disabled"
            meson_options+=" -Dfreedreno=auto"
            meson_options+=" -Dtegra=auto"
            meson_options+=" -Dvc4=auto"
            meson_options+=" -Detnaviv=auto"
            meson_options+=" $test_options"
            meson_options+=" -Dman-pages=disabled"
            meson_options+=" -Dvalgrind=disabled"
            meson_options+=" -Dcairo-tests=disabled"
            meson_options+=" -Dudev=true"
            meson_options+=" -Dfreedreno-kgsl=false"
            ;;
        *windows*)
            # Windows - minimal support, no Linux-specific features
            meson_options=""
            meson_options+=" -Dintel=auto"
            meson_options+=" -Dradeon=auto"
            meson_options+=" -Damdgpu=auto"
            meson_options+=" -Dnouveau=auto"
            meson_options+=" -Dvmwgfx=auto"
            meson_options+=" -Domap=disabled"
            meson_options+=" -Dexynos=disabled"
            meson_options+=" -Dfreedreno=disabled"
            meson_options+=" -Dtegra=disabled"
            meson_options+=" -Dvc4=disabled"
            meson_options+=" -Detnaviv=disabled"
            meson_options+=" $test_options"
            meson_options+=" -Dman-pages=disabled"
            meson_options+=" -Dvalgrind=disabled"
            meson_options+=" -Dcairo-tests=disabled"
            meson_options+=" -Dudev=false"
            meson_options+=" -Dfreedreno-kgsl=false"
            ;;
        *macos*)
            # macOS - very minimal support, only basic functionality
            meson_options=""
            meson_options+=" -Dintel=disabled"
            meson_options+=" -Dradeon=disabled"
            meson_options+=" -Damdgpu=disabled"
            meson_options+=" -Dnouveau=disabled"
            meson_options+=" -Dvmwgfx=disabled"
            meson_options+=" -Domap=disabled"
            meson_options+=" -Dexynos=disabled"
            meson_options+=" -Dfreedreno=disabled"
            meson_options+=" -Dtegra=disabled"
            meson_options+=" -Dvc4=disabled"
            meson_options+=" -Detnaviv=disabled"
            meson_options+=" $test_options"
            meson_options+=" -Dman-pages=disabled"
            meson_options+=" -Dvalgrind=disabled"
            meson_options+=" -Dcairo-tests=disabled"
            meson_options+=" -Dudev=false"
            meson_options+=" -Dfreedreno-kgsl=false"
            ;;        
        *)
            # Default fallback - conservative settings
            meson_options=""
            meson_options+=" -Dintel=auto"
            meson_options+=" -Dradeon=auto"
            meson_options+=" -Damdgpu=auto"
            meson_options+=" -Dnouveau=auto"
            meson_options+=" -Dvmwgfx=auto"
            meson_options+=" -Domap=disabled"
            meson_options+=" -Dexynos=disabled"
            meson_options+=" -Dfreedreno=auto"
            meson_options+=" -Dtegra=auto"
            meson_options+=" -Dvc4=auto"
            meson_options+=" -Detnaviv=auto"
            meson_options+=" $test_options"
            meson_options+=" -Dman-pages=disabled"
            meson_options+=" -Dvalgrind=disabled"
            meson_options+=" -Dcairo-tests=disabled"
            meson_options+=" -Dudev=false"
            meson_options+=" -Dfreedreno-kgsl=false"
            ;;
    esac
    
    echo "$meson_options"
}

# Android编译函数
build_android_target() {
    local target_name="$1"
    local output_dir="$2"
    
    log_info "Building Android target: $target_name..."
    
    # 初始化Android环境
    init_android_env "$target_name"
    
    # 创建输出目录
    mkdir -p "$output_dir"
    
    # 创建构建目录
    local build_dir="${LIBDRM_SOURCE_DIR}/build_${target_name}"
    rm -rf "$build_dir"  # 清理旧的构建目录
    mkdir -p "$build_dir"
    
    # 创建交叉编译配置文件
    create_cross_file "$target_name" "" "true"
    
    # 应用 meson 时钟偏差补丁
    apply_meson_clockskew_patch
    
    # 获取meson编译选项
    local meson_options
    meson_options=$(get_meson_options "${ANDROID_TARGET}-android" false)
    
    # 配置Meson
    local MESON_CMD="meson setup $build_dir $LIBDRM_SOURCE_DIR -Dprefix=$output_dir -Dbuildtype=release -Dlibdir=lib"
    MESON_CMD="$MESON_CMD --cross-file=$CROSS_FILE"
    MESON_CMD="$MESON_CMD $meson_options"
    
    log_info "Meson command: $MESON_CMD"
    eval "$MESON_CMD"
    
    if [ $? -ne 0 ]; then
        log_error "Meson configuration failed for $target_name"
        return 1
    fi
    
    # 编译
    ninja -C "$build_dir"
    
    if [ $? -ne 0 ]; then
        log_error "Build failed for $target_name"
        return 1
    fi
    
    # 安装
    ninja -C "$build_dir" install
    
    if [ $? -ne 0 ]; then
        log_error "Install failed for $target_name"
        return 1
    fi
    
    log_success "$target_name build completed successfully"
    
    # Android版本的压缩处理
    compress_android_libraries "$output_dir" "$target_name"
    
    # 返回到工作目录
    cd "$WORKSPACE_DIR"
}

# 编译函数
build_target() {
    local target_name="$1"
    local toolchain_file="$2"
    local output_dir="$3"
    
    log_info "Building $target_name..."
    
    # 提取交叉编译前缀
    local cross_prefix
    cross_prefix=$(get_cross_compile_prefix "$toolchain_file")
    
    # 检查交叉编译工具
    local available_tools
    available_tools=$(check_cross_compile_tools "$cross_prefix" "$target_name")
    
    # 创建输出目录
    mkdir -p "$output_dir"
    
    # 创建构建目录
    local build_dir="${LIBDRM_SOURCE_DIR}/build_${target_name}"
    rm -rf "$build_dir"  # 清理旧的构建目录
    mkdir -p "$build_dir"
    
    # 创建交叉编译配置文件
    create_cross_file "$target_name" "$toolchain_file" "false"
    
    # 应用 meson 时钟偏差补丁
    apply_meson_clockskew_patch
    
    # 获取目标架构
    local target_arch=""
    case "$target_name" in
        "32bit"|"glibc_arm"|"musl_arm64")
            target_arch="arm-linux-gnueabihf"
            ;;
        "64bit"|"glibc_arm64"|"musl")
            target_arch="aarch64-linux-gnu"
            ;;
        "glibc_riscv64"|"musl_riscv64")
            target_arch="riscv64-linux-gnu"
            ;;
        *)
            target_arch="unknown"
            ;;
    esac
    
    # 获取meson编译选项
    local meson_options
    meson_options=$(get_meson_options "$target_arch" false)
    
    # 配置Meson
    local MESON_CMD="meson setup $build_dir $LIBDRM_SOURCE_DIR -Dprefix=$output_dir -Dbuildtype=release -Dlibdir=lib"
    if [ -n "$CROSS_FILE" ]; then
        MESON_CMD="$MESON_CMD --cross-file=$CROSS_FILE"
    fi
    # Always add meson options
    MESON_CMD="$MESON_CMD $meson_options"
    
    log_info "Meson command: $MESON_CMD"
    eval "$MESON_CMD"
    
    if [ $? -ne 0 ]; then
        log_error "Meson configuration failed for $target_name"
        return 1
    fi
    
    # 编译
    ninja -C "$build_dir"
    
    if [ $? -ne 0 ]; then
        log_error "Build failed for $target_name"
        return 1
    fi
    
    # 安装
    ninja -C "$build_dir" install
    
    if [ $? -ne 0 ]; then
        log_error "Install failed for $target_name"
        return 1
    fi
    
    log_success "$target_name build completed successfully"
    
    # 压缩库文件
    compress_libraries "$output_dir" "$target_name" "$available_tools"
    
    # 返回到工作目录
    cd "$WORKSPACE_DIR"
}

# 压缩库文件
compress_libraries() {
    local output_dir="$1"
    local target_name="$2"
    local available_tools="$3"
    
    log_info "Compressing libraries for $target_name..."
    
    # 解析可用工具
    local strip_cmd=""
    local objcopy_cmd=""
    local upx_cmd=""
    local xz_cmd=""
    local gzip_cmd=""
    
    if [ -n "$available_tools" ]; then
        # 从工具列表中提取各类工具
        strip_cmd=$(echo "$available_tools" | grep -o "strip:[^ ]*" | cut -d: -f2)
        objcopy_cmd=$(echo "$available_tools" | grep -o "objcopy:[^ ]*" | cut -d: -f2)
        upx_cmd=$(echo "$available_tools" | grep -o "upx:[^ ]*" | cut -d: -f2)
        xz_cmd=$(echo "$available_tools" | grep -o "xz:[^ ]*" | cut -d: -f2)
        gzip_cmd=$(echo "$available_tools" | grep -o "gzip:[^ ]*" | cut -d: -f2)
    fi
    
    # 显示可用的工具
    log_info "Available compression tools:"
    [ -n "$strip_cmd" ] && log_info "  Strip: $strip_cmd"
    [ -n "$objcopy_cmd" ] && log_info "  Objcopy: $objcopy_cmd"
    [ -n "$upx_cmd" ] && log_info "  UPX: $upx_cmd"
    [ -n "$xz_cmd" ] && log_info "  XZ: $xz_cmd"
    [ -n "$gzip_cmd" ] && log_info "  GZIP: $gzip_cmd"
    
    # 查找所有 .so 和 .a 文件
    local lib_files
    lib_files=$(find "$output_dir" -type f \( -name "*.so*" -o -name "*.a" \) 2>/dev/null || true)
    
    if [ -z "$lib_files" ]; then
        log_warning "No library files found to compress in $output_dir"
        return 0
    fi
    
    local compressed_count=0
    local total_original_size=0
    local total_compressed_size=0
    
    while IFS= read -r lib_file; do
        [ -z "$lib_file" ] && continue
        
        local original_size
        original_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "0")
        total_original_size=$((total_original_size + original_size))
        
        local final_size=$original_size
        local compression_method="none"
        local compression_applied=false
        
        log_info "  Processing: $(basename "$lib_file") (${original_size} bytes)"
        
        # 1. 首先尝试 strip 移除符号表（对所有库文件都有效）
        if [ -n "$strip_cmd" ]; then
            # 创建备份来测试 strip 效果
            local backup_file="${lib_file}.backup"
            cp "$lib_file" "$backup_file"
            
            log_info "    Using $strip_cmd to strip symbols..."
            
            # 使用不同的 strip 参数
            if [[ "$lib_file" == *.so* ]]; then
                # 对于共享库，保留动态符号
                "$strip_cmd" --strip-unneeded "$lib_file" 2>/dev/null || true
            else
                # 对于静态库，移除调试符号
                "$strip_cmd" --strip-debug "$lib_file" 2>/dev/null || true
            fi
            
            local stripped_size
            stripped_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "$original_size")
            
            if [ "$stripped_size" -lt "$original_size" ]; then
                final_size=$stripped_size
                compression_method="strip"
                compression_applied=true
                rm -f "$backup_file"
                local strip_reduction
                strip_reduction=$(( (original_size - stripped_size) * 100 / original_size ))
                log_success "      Stripped ${strip_reduction}% of symbols ($strip_cmd)"
            else
                # 如果 strip 没有效果，恢复原文件
                mv "$backup_file" "$lib_file"
                log_info "      Strip had no effect"
            fi
        else
            log_info "    Strip tool not available for this target"
        fi
        
        # 2. 对于动态库，尝试 UPX 压缩
        if [[ "$lib_file" == *.so* ]] && [ -n "$upx_cmd" ]; then
            local compressed_file="${lib_file}.upx"
            log_info "    Trying UPX compression with $upx_cmd..."
            
            # 尝试不同的 UPX 压缩级别
            if "$upx_cmd" --best --lzma -o "$compressed_file" "$lib_file" &>/dev/null; then
                local upx_size
                upx_size=$(stat -c%s "$compressed_file" 2>/dev/null || echo "$final_size")
                
                if [ "$upx_size" -lt "$final_size" ]; then
                    local upx_reduction
                    upx_reduction=$(( (final_size - upx_size) * 100 / final_size ))
                    mv "$compressed_file" "$lib_file"
                    final_size=$upx_size
                    compression_method="${compression_method}+upx"
                    compression_applied=true
                    log_success "      UPX: ${upx_reduction}% additional reduction"
                else
                    rm -f "$compressed_file"
                    log_info "      UPX compression not beneficial"
                fi
            else
                rm -f "$compressed_file"
                log_info "      UPX compression failed"
            fi
        elif [[ "$lib_file" == *.so* ]]; then
            log_info "    UPX not available for this target"
        fi
        
        # 3. 尝试使用 objcopy 进一步优化（如果可用）
        if [ -n "$objcopy_cmd" ] && [ "$compression_applied" = "true" ]; then
            log_info "    Optimizing with $objcopy_cmd..."
            if "$objcopy_cmd" --remove-section=.comment --remove-section=.note "$lib_file" 2>/dev/null; then
                local objcopy_size
                objcopy_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "$final_size")
                if [ "$objcopy_size" -lt "$final_size" ]; then
                    final_size=$objcopy_size
                    compression_method="${compression_method}+objcopy"
                    log_info "      objcopy optimization applied"
                fi
            fi
        fi
        
        total_compressed_size=$((total_compressed_size + final_size))
        
        if [ "$compression_applied" = "true" ]; then
            compressed_count=$((compressed_count + 1))
            local total_reduction
            total_reduction=$(( (original_size - final_size) * 100 / original_size ))
            log_success "    Final: $original_size → $final_size bytes (-${total_reduction}%, ${compression_method#none+})"
        else
            log_info "    No compression applied"
        fi
        
        echo ""
        
    done <<< "$lib_files"
    
    # 显示压缩统计
    if [ "$compressed_count" -gt 0 ]; then
        local total_reduction
        total_reduction=$(( (total_original_size - total_compressed_size) * 100 / total_original_size ))
        log_success "Compression summary for $target_name:"
        log_success "  Files processed: $(echo "$lib_files" | wc -l)"
        log_success "  Files optimized: $compressed_count"
        log_success "  Total size: $total_original_size → $total_compressed_size bytes (-${total_reduction}%)"
    else
        log_info "No significant compression achieved for $target_name (files may already be optimized)"
    fi
    
    # 显示每个文件的详细信息
    log_info "Final library file sizes:"
    while IFS= read -r lib_file; do
        [ -z "$lib_file" ] && continue
        local size
        size=$(stat -c%s "$lib_file" 2>/dev/null || echo "0")
        local size_kb
        size_kb=$((size / 1024))
        log_info "  $(basename "$lib_file"): ${size_kb} KB"
    done <<< "$lib_files"
}

# 创建软链接
create_symlinks() {
    local target_built="$1"
    
    log_info "Creating symbolic links..."
    
    cd "$LIBDRM_OUTPUT_DIR"
    
    # 根据构建的目标创建对应的软链接
    case "$target_built" in
        "32bit"|"glibc_arm")
            if [ -d "32bit" ]; then
                ln -sf 32bit glibc_arm
            fi
            ;;
        "64bit"|"glibc_arm64")
            if [ -d "64bit" ]; then
                ln -sf 64bit glibc_arm64
            fi
            ;;
        "musl"|"musl_arm")
            if [ -d "musl" ]; then
                ln -sf musl musl_arm
            fi
            ;;
        "all")
            # 为所有存在的目录创建软链接
            [ -d "32bit" ] && ln -sf 32bit glibc_arm
            [ -d "64bit" ] && ln -sf 64bit glibc_arm64
            [ -d "musl" ] && ln -sf musl musl_arm
            ;;
    esac
    
    log_success "Symbolic links created"
}

# Android环境初始化
init_android_env() {
    local target="$1"
    
    if [[ "$target" == "android_"* ]]; then
        # 展开波浪号路径
        local default_ndk_path
        default_ndk_path=$(eval echo "~/sdk/android_ndk/android-ndk-r21e")
        export ANDROID_NDK_ROOT="${ANDROID_NDK_HOME:-$default_ndk_path}"
        HOST_TAG=linux-x86_64
        TOOLCHAIN=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG
        export PATH=$TOOLCHAIN/bin:$PATH
        API_LEVEL=23

        case "$target" in
            android_arm64_v8a)
                ANDROID_ABI=arm64-v8a
                ANDROID_TARGET=aarch64-linux-android
                log_info "Initializing Android NDK for arm64-v8a (API $API_LEVEL)"
                ;;
            android_armeabi_v7a)
                ANDROID_ABI=armeabi-v7a
                ANDROID_TARGET=armv7a-linux-androideabi
                log_info "Initializing Android NDK for armeabi-v7a (API $API_LEVEL)"
                ;;
            *)
                log_error "未知的 Android 架构: $target"
                exit 1
                ;;
        esac
        
        # 检查Android NDK是否存在
        if [ ! -d "$ANDROID_NDK_ROOT" ]; then
            log_error "Android NDK not found at: $ANDROID_NDK_ROOT"
            log_error "Please install Android NDK or set ANDROID_NDK_HOME environment variable"
            exit 1
        fi
        
        if [ ! -d "$TOOLCHAIN" ]; then
            log_error "Android NDK toolchain not found at: $TOOLCHAIN"
            exit 1
        fi
        
        log_success "Android NDK environment initialized"
        log_info "NDK Root: $ANDROID_NDK_ROOT"
        log_info "Toolchain: $TOOLCHAIN"
        log_info "ABI: $ANDROID_ABI"
        log_info "API Level: $API_LEVEL"
    fi
}

# 获取默认编译目标列表
get_default_build_targets() {
    # 如果私有变量不存在或为空，返回所有目标的配置
    if [ -z "$_DEFAULT_BUILD_TARGETS" ]; then
        # 所有目标的配置
        echo "32bit:${TOOLCHAIN_DIR}/arm-linux-gnueabihf.cmake:${LIBDRM_OUTPUT_DIR}/32bit"
        echo "64bit:${TOOLCHAIN_DIR}/aarch64-linux-gnu.cmake:${LIBDRM_OUTPUT_DIR}/64bit"
        echo "glibc_riscv64:${TOOLCHAIN_DIR}/riscv64-unknown-linux-gnu.cmake:${LIBDRM_OUTPUT_DIR}/glibc_riscv64"
        echo "musl:${TOOLCHAIN_DIR}/aarch64-none-linux-musl.cmake:${LIBDRM_OUTPUT_DIR}/musl"
        echo "musl_arm64:${TOOLCHAIN_DIR}/arm-none-linux-musleabihf.cmake:${LIBDRM_OUTPUT_DIR}/musl_arm64"
        echo "musl_riscv64:${TOOLCHAIN_DIR}/riscv64-unknown-linux-musl.cmake:${LIBDRM_OUTPUT_DIR}/musl_riscv64"
        echo "android_arm64_v8a:android:${LIBDRM_OUTPUT_DIR}/android_arm64_v8a"
        echo "android_armeabi_v7a:android:${LIBDRM_OUTPUT_DIR}/android_armeabi_v7a"
        return 0
    fi
    
    # 解析限制的默认目标列表
    IFS=',' read -ra TARGET_ARRAY <<< "$_DEFAULT_BUILD_TARGETS"
    for target_name in "${TARGET_ARRAY[@]}"; do
        # 去除空格
        target_name=$(echo "$target_name" | tr -d ' ')
        if [ -n "$target_name" ]; then
            local target_config
            target_config=$(get_target_config "$target_name")
            if [ -n "$target_config" ]; then
                echo "$target_config"
            else
                log_warning "Invalid default target ignored: $target_name"
            fi
        fi
    done
}

# 获取目标配置
get_target_config() {
    local target_name="$1"
    
    # 定义目标映射 - 处理别名
    case "$target_name" in
        "glibc_arm")
            echo "32bit:${TOOLCHAIN_DIR}/arm-linux-gnueabihf.cmake:${LIBDRM_OUTPUT_DIR}/32bit"
            ;;
        "glibc_arm64")
            echo "64bit:${TOOLCHAIN_DIR}/aarch64-linux-gnu.cmake:${LIBDRM_OUTPUT_DIR}/64bit"
            ;;
        "musl_arm")
            echo "musl:${TOOLCHAIN_DIR}/aarch64-none-linux-musl.cmake:${LIBDRM_OUTPUT_DIR}/musl"
            ;;
        "32bit")
            echo "32bit:${TOOLCHAIN_DIR}/arm-linux-gnueabihf.cmake:${LIBDRM_OUTPUT_DIR}/32bit"
            ;;
        "64bit")
            echo "64bit:${TOOLCHAIN_DIR}/aarch64-linux-gnu.cmake:${LIBDRM_OUTPUT_DIR}/64bit"
            ;;
        "glibc_riscv64")
            echo "glibc_riscv64:${TOOLCHAIN_DIR}/riscv64-unknown-linux-gnu.cmake:${LIBDRM_OUTPUT_DIR}/glibc_riscv64"
            ;;
        "musl")
            echo "musl:${TOOLCHAIN_DIR}/aarch64-none-linux-musl.cmake:${LIBDRM_OUTPUT_DIR}/musl"
            ;;
        "musl_arm64")
            echo "musl_arm64:${TOOLCHAIN_DIR}/arm-none-linux-musleabihf.cmake:${LIBDRM_OUTPUT_DIR}/musl_arm64"
            ;;
        "musl_riscv64")
            echo "musl_riscv64:${TOOLCHAIN_DIR}/riscv64-unknown-linux-musl.cmake:${LIBDRM_OUTPUT_DIR}/musl_riscv64"
            ;;
        "android_arm64_v8a")
            echo "android_arm64_v8a:android:${LIBDRM_OUTPUT_DIR}/android_arm64_v8a"
            ;;
        "android_armeabi_v7a")
            echo "android_armeabi_v7a:android:${LIBDRM_OUTPUT_DIR}/android_armeabi_v7a"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 验证目标名称
validate_target() {
    local target="$1"
    local valid_targets=("32bit" "64bit" "glibc_riscv64" "musl" "musl_arm64" "musl_riscv64" "glibc_arm" "glibc_arm64" "musl_arm" "android_arm64_v8a" "android_armeabi_v7a")
    
    for valid in "${valid_targets[@]}"; do
        if [ "$target" = "$valid" ]; then
            return 0
        fi
    done
    return 1
}

# 参数解析
parse_arguments() {
    local target=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [ -z "$target" ]; then
                    target="$1"
                else
                    log_error "Multiple targets specified. Only one target is allowed."
                    show_help
                    exit 1
                fi
                ;;
        esac
        shift
    done
    
    # 验证目标名称（如果提供了）
    if [ -n "$target" ] && ! validate_target "$target"; then
        log_error "Invalid target: $target"
        log_error "Valid targets: 32bit, 64bit, glibc_riscv64, musl, musl_arm64, musl_riscv64, glibc_arm, glibc_arm64, musl_arm, android_arm64_v8a, android_armeabi_v7a"
        exit 1
    fi
    
    echo "$target"
}

# 主函数
main() {
    local target_to_build="$1"
    
    log_info "Starting libdrm build process..."
    
    # 检查工具
    check_tools
    
    # 下载源码
    download_libdrm
    
    # 创建输出目录
    mkdir -p "$LIBDRM_OUTPUT_DIR"
    
    if [ -n "$target_to_build" ]; then
        # 单个目标构建
        log_info "Building single target: $target_to_build"
        
        local target_config
        target_config=$(get_target_config "$target_to_build")
        
        if [ -z "$target_config" ]; then
            log_error "Invalid target: $target_to_build"
            exit 1
        fi
        
        IFS=':' read -r target_name toolchain_file output_dir <<< "$target_config"
        
        # 检查是否为Android目标
        if [[ "$target_to_build" == "android_"* ]]; then
            # Android目标使用专门的构建函数
            if build_android_target "$target_name" "$output_dir"; then
                log_success "$target_to_build build completed successfully"
            else
                log_error "Failed to build $target_to_build"
                exit 1
            fi
        else
            # 检查toolchain文件是否存在
            if [ ! -f "$toolchain_file" ]; then
                log_error "Toolchain file not found: $toolchain_file"
                log_error "Please install the corresponding cross-compilation toolchain"
                exit 1
            fi
            
            # 构建目标
            if build_target "$target_name" "$toolchain_file" "$output_dir"; then
                log_success "$target_to_build build completed successfully"
            else
                log_error "Failed to build $target_to_build"
                exit 1
            fi
        fi
        
        # 创建对应的软链接
        create_symlinks "$target_to_build"
        
    else
        # 构建所有目标（或默认限制的目标）
        if [ -n "$_DEFAULT_BUILD_TARGETS" ]; then
            log_info "Building default targets: $_DEFAULT_BUILD_TARGETS"
        else
            log_info "Building all targets..."
        fi
        
        # 获取要构建的目标列表
        local targets_to_build
        targets_to_build=$(get_default_build_targets)
        
        if [ -z "$targets_to_build" ]; then
            log_error "No valid targets to build"
            exit 1
        fi
        
        # 构建所有指定的目标
        while IFS= read -r target_config; do
            [ -z "$target_config" ] && continue
            
            IFS=':' read -r target_name toolchain_file output_dir <<< "$target_config"
            
            # 检查是否为Android目标
            if [[ "$target_name" == "android_"* ]]; then
                # Android目标使用专门的构建函数
                if ! build_android_target "$target_name" "$output_dir"; then
                    log_warning "Failed to build $target_name, continuing with next target"
                    continue
                fi
            else
                # 检查toolchain文件是否存在
                if [ ! -f "$toolchain_file" ]; then
                    log_warning "Toolchain file not found: $toolchain_file, skipping $target_name"
                    continue
                fi
                
                # 构建目标
                if ! build_target "$target_name" "$toolchain_file" "$output_dir"; then
                    log_warning "Failed to build $target_name, continuing with next target"
                    continue
                fi
            fi
        done <<< "$targets_to_build"
        
        # 创建所有软链接
        create_symlinks "all"
    fi
    
    log_success "Build process completed!"
    log_info "Output directory: $LIBDRM_OUTPUT_DIR"
    
    # 显示压缩统计
    show_compression_summary
    
    # 生成version.ini文件
    create_version_file
    
    # 显示目录结构
    log_info "Directory structure:"
    tree "$LIBDRM_OUTPUT_DIR" 2>/dev/null || ls -la "$LIBDRM_OUTPUT_DIR"
}

# 创建版本信息文件
create_version_file() {
    log_info "Creating version.ini file..."
    
    local version_file="${LIBDRM_OUTPUT_DIR}/version.ini"
    
    # 写入版本信息到version.ini
    cat > "$version_file" << EOF
[version]
version=$LIBDRM_VERSION
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Version file created successfully: $version_file"
        log_info "libdrm version: $LIBDRM_VERSION"
    else
        log_error "Failed to create version file: $version_file"
        return 1
    fi
}

# 显示压缩统计汇总
show_compression_summary() {
    log_info "Checking final library sizes..."
    
    # 查找所有库文件并显示大小
    local all_libs
    all_libs=$(find "$LIBDRM_OUTPUT_DIR" -type f \( -name "*.so*" -o -name "*.a" -o -name "*.gz" \) 2>/dev/null || true)
    
    if [ -n "$all_libs" ]; then
        log_info "Final library files:"
        while IFS= read -r lib_file; do
            [ -z "$lib_file" ] && continue
            local size
            size=$(stat -c%s "$lib_file" 2>/dev/null || echo "0")
            local size_mb
            if command -v "bc" &> /dev/null; then
                size_mb=$(echo "scale=2; $size / 1024 / 1024" | bc 2>/dev/null || echo "0.00")
            else
                size_mb=$(( size / 1024 / 1024 ))
            fi
            log_info "  $(basename "$lib_file"): ${size} bytes (${size_mb} MB)"
        done <<< "$all_libs"
    fi
}

# 清理函数
cleanup() {
    log_info "Cleaning up..."
    
    # 清理构庺目录
    if [ -d "${LIBDRM_SOURCE_DIR}" ]; then
        find "${LIBDRM_SOURCE_DIR}" -name "build_*" -type d -exec rm -rf {} + 2>/dev/null || true
    fi
    
    # 清理交叉编译配置文件
    [ -f "$PROJECT_ROOT_DIR/cross-build.txt" ] && rm -f "$PROJECT_ROOT_DIR/cross-build.txt"
}

# 帮助信息
show_help() {
    echo "libdrm Build Script"
    echo ""
    echo "Usage: $0 [OPTIONS] [TARGET]"
    echo ""
    echo "TARGET (optional):"
    echo "  32bit           Build ARM 32-bit glibc version"
    echo "  64bit           Build ARM 64-bit glibc version"
    echo "  glibc_riscv64   Build RISC-V 64-bit glibc version"
    echo "  musl            Build ARM 64-bit musl version"
    echo "  musl_arm64      Build ARM 32-bit musl version"
    echo "  musl_riscv64    Build RISC-V 64-bit musl version"
    echo "  glibc_arm       Alias for 32bit"
    echo "  glibc_arm64     Alias for 64bit"
    echo "  musl_arm        Alias for musl"
    echo "  android_arm64_v8a     Build Android ARM 64-bit version"
    echo "  android_armeabi_v7a   Build Android ARM 32-bit version"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -c, --clean    Clean build directories only"
    echo "  --clean-all    Clean all (sources and outputs)"
    echo ""
    echo "Environment Variables:"
    echo "  TOOLCHAIN_ROOT_DIR    Path to cross-compilation toolchain (optional)"
    echo "  ANDROID_NDK_HOME      Path to Android NDK (default: ~/sdk/android_ndk/android-ndk-r21e)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Build default targets (glibc_arm64, glibc_arm, android_arm64_v8a, android_armeabi_v7a)"
    echo "  $0 glibc_arm64        # Build only ARM 64-bit glibc version"
    echo "  $0 64bit              # Same as above"
    echo "  $0 musl               # Build only ARM 64-bit musl version"
    echo "  $0 android_arm64_v8a  # Build Android ARM 64-bit version"
    echo "  $0 android_armeabi_v7a # Build Android ARM 32-bit version"
    echo "  $0 --clean           # Clean build directories"
    echo "  $0 --clean-all       # Clean everything"
    echo ""
    echo "Features:"
    echo "  - Fixed version: $LIBDRM_VERSION"
    echo "  - Uses meson build system"
    echo "  - Cross-compilation support via cross-build.txt"
    echo "  - Automatic meson clockskew patch to avoid time synchronization issues"
    echo "  - Automatic library compression using available tools"
    echo "  - UPX compression for .so files (if available)"
    echo "  - Symbol stripping for size reduction"
    echo "  - Compression statistics and size reporting"
    echo ""
}

# 清理所有
clean_all() {
    log_info "Cleaning all..."
    
    # 清理源码目录
    if [ -d "${SOURCES_DIR}" ]; then
        log_info "Removing sources directory: ${SOURCES_DIR}"
        rm -rf "${SOURCES_DIR}"
    fi
    
    # 清理输出目录
    if [ -d "${LIBDRM_OUTPUT_DIR}" ]; then
        log_info "Removing output directory: ${LIBDRM_OUTPUT_DIR}"
        rm -rf "${LIBDRM_OUTPUT_DIR}"
    fi
    
    # 清理交叉编译配置文件
    [ -f "$PROJECT_ROOT_DIR/cross-build.txt" ] && rm -f "$PROJECT_ROOT_DIR/cross-build.txt"
    
    log_success "Clean completed"
}

# 信号处理
trap cleanup EXIT

# 主执行逻辑
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -c|--clean)
        cleanup
        exit 0
        ;;
    --clean-all)
        clean_all
        exit 0
        ;;
    *)
        # 解析参数并执行主函数
        TARGET_TO_BUILD=$(parse_arguments "$@")
        main "$TARGET_TO_BUILD"
        ;;
esac