#!/bin/bash

# RK MPP 构建脚本
# 支持多种交叉编译工具链编译 Rockchip Media Process Platform (MPP) 库

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLCHAIN_DIR="${WORKSPACE_DIR}/toolchain"
SOURCES_DIR="${WORKSPACE_DIR}/sources"
OUTPUTS_DIR="${WORKSPACE_DIR}/outputs"
RKMPP_OUTPUT_DIR="${OUTPUTS_DIR}/rkmpp"

# mpp 源码目录
MPP_SOURCE_DIR="${SOURCES_DIR}/rkmpp"

# 限制默认编译目标
_DEFAULT_BUILD_TARGETS="aarch64-linux-gnu,arm-linux-gnueabihf,aarch64-linux-android,arm-linux-android"

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
    local tools=("git" "cmake" "make")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Missing required tool: $tool"
            exit 1
        fi
    done
}

# 克隆 mpp 源码
clone_mpp() {
    log_info "Checking mpp repository..."
    
    # 创建sources目录
    mkdir -p "${SOURCES_DIR}"
    
    # 如果目录已存在且包含CMakeLists.txt，跳过克隆
    if [ -d "${MPP_SOURCE_DIR}" ] && [ -f "${MPP_SOURCE_DIR}/CMakeLists.txt" ]; then
        log_success "mpp source already exists, skipping clone"
        return 0
    fi
    
    # 如果目录存在但不完整，先删除
    if [ -d "${MPP_SOURCE_DIR}" ]; then
        log_warning "Removing incomplete mpp directory"
        rm -rf "${MPP_SOURCE_DIR}"
    fi
    
    # 克隆最新代码
    log_info "Cloning mpp repository..."
    git clone --depth=1 https://github.com/rockchip-linux/mpp "${MPP_SOURCE_DIR}"
    
    if [ $? -eq 0 ]; then
        log_success "mpp cloned successfully"
    else
        log_error "Failed to clone mpp"
        exit 1
    fi
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
    local build_dir="${MPP_SOURCE_DIR}/build/build_${target_name}"
    rm -rf "$build_dir"  # 清理旧的构建目录
    mkdir -p "$build_dir"
    
    # 进入构建目录
    cd "$build_dir"
    
    # 检查Android toolchain文件是否存在
    local android_toolchain="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake"
    if [ ! -f "$android_toolchain" ]; then
        log_error "Android NDK CMake toolchain not found: $android_toolchain"
        return 1
    fi
    
    log_info "Using Android NDK CMake toolchain: $android_toolchain"
    
    # 配置CMake - 使用Android NDK的CMake工具链
    cmake ../.. \
          -DCMAKE_TOOLCHAIN_FILE="$android_toolchain" \
          -DANDROID_ABI="$ANDROID_ABI" \
          -DANDROID_PLATFORM="android-$API_LEVEL" \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX="$output_dir" \
          -DBUILD_SHARED_LIBS=ON \
          -DBUILD_TEST=OFF
    
    if [ $? -ne 0 ]; then
        log_error "CMake configuration failed for $target_name"
        return 1
    fi
    
    # 编译
    make -j$(nproc)
    
    if [ $? -ne 0 ]; then
        log_error "Build failed for $target_name"
        return 1
    fi
    
    # 安装
    make install
    
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

# Android库文件压缩
compress_android_libraries() {
    local output_dir="$1"
    local target_name="$2"
    
    log_info "Compressing Android libraries for $target_name..."
    
    # Android下可用的工具（主要是strip）
    local strip_cmd=""
    local available_tools=""
    
    # 检查Android NDK中的strip工具
    case "$ANDROID_ABI" in
        "arm64-v8a")
            strip_cmd="$TOOLCHAIN/bin/aarch64-linux-android-strip"
            ;;
        "armeabi-v7a")
            strip_cmd="$TOOLCHAIN/bin/arm-linux-androideabi-strip"
            ;;
    esac
    
    if [ -n "$strip_cmd" ] && command -v "$strip_cmd" &> /dev/null; then
        available_tools="strip:$strip_cmd "
        log_info "Available Android tools: $available_tools"
    else
        log_warning "Android strip tool not found, skipping compression"
    fi
    
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
        local compression_applied=false
        
        log_info "  Processing: $(basename "$lib_file") (${original_size} bytes)"
        
        # 使用Android NDK的strip工具
        if [ -n "$strip_cmd" ]; then
            local backup_file="${lib_file}.backup"
            cp "$lib_file" "$backup_file"
            
            log_info "    Using Android strip tool..."
            
            if [[ "$lib_file" == *.so* ]]; then
                "$strip_cmd" --strip-unneeded "$lib_file" 2>/dev/null || true
            else
                "$strip_cmd" --strip-debug "$lib_file" 2>/dev/null || true
            fi
            
            local stripped_size
            stripped_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "$original_size")
            
            if [ "$stripped_size" -lt "$original_size" ]; then
                final_size=$stripped_size
                compression_applied=true
                rm -f "$backup_file"
                local strip_reduction
                strip_reduction=$(( (original_size - stripped_size) * 100 / original_size ))
                log_success "      Stripped ${strip_reduction}% of symbols"
            else
                mv "$backup_file" "$lib_file"
                log_info "      Strip had no effect"
            fi
        fi
        
        total_compressed_size=$((total_compressed_size + final_size))
        
        if [ "$compression_applied" = "true" ]; then
            compressed_count=$((compressed_count + 1))
            local total_reduction
            total_reduction=$(( (original_size - final_size) * 100 / original_size ))
            log_success "    Final: $original_size → $final_size bytes (-${total_reduction}%)"
        else
            log_info "    No compression applied"
        fi
        
    done <<< "$lib_files"
    
    # 显示压缩统计
    if [ "$compressed_count" -gt 0 ]; then
        local total_reduction
        total_reduction=$(( (total_original_size - total_compressed_size) * 100 / total_original_size ))
        log_success "Android compression summary for $target_name:"
        log_success "  Files processed: $(echo "$lib_files" | wc -l)"
        log_success "  Files optimized: $compressed_count"
        log_success "  Total size: $total_original_size → $total_compressed_size bytes (-${total_reduction}%)"
    else
        log_info "No significant compression achieved for $target_name"
    fi
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
    local build_dir="${MPP_SOURCE_DIR}/build_${target_name}"
    mkdir -p "$build_dir"
    
    # 进入构建目录
    cd "$build_dir"
    
    # 配置CMake
    cmake -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
          -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_INSTALL_PREFIX="$output_dir" \
          -DBUILD_SHARED_LIBS=ON \
          -DBUILD_TEST=OFF \
          ..
    
    if [ $? -ne 0 ]; then
        log_error "CMake configuration failed for $target_name"
        return 1
    fi
    
    # 编译
    make -j$(nproc)
    
    if [ $? -ne 0 ]; then
        log_error "Build failed for $target_name"
        return 1
    fi
    
    # 安装
    make install
    
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
    
    if [ -n "$available_tools" ]; then
        # 从工具列表中提取各类工具
        strip_cmd=$(echo "$available_tools" | grep -o "strip:[^ ]*" | cut -d: -f2)
        objcopy_cmd=$(echo "$available_tools" | grep -o "objcopy:[^ ]*" | cut -d: -f2)
        upx_cmd=$(echo "$available_tools" | grep -o "upx:[^ ]*" | cut -d: -f2)
    fi
    
    # 显示可用的工具
    log_info "Available compression tools:"
    [ -n "$strip_cmd" ] && log_info "  Strip: $strip_cmd"
    [ -n "$objcopy_cmd" ] && log_info "  Objcopy: $objcopy_cmd"
    [ -n "$upx_cmd" ] && log_info "  UPX: $upx_cmd"
    
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
        
        # 1. 首先尝试 strip 移除符号表
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
        
        # 2. 尝试使用 objcopy 进一步优化（如果可用）
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
}

# Android环境初始化
init_android_env() {
    local target="$1"
    
    if [[ "$target" == "aarch64-linux-android" || "$target" == "arm-linux-android" ]]; then
        # 展开波浪号路径
        local default_ndk_path
        default_ndk_path=$(eval echo "~/sdk/android_ndk/android-ndk-r21e")
        export ANDROID_NDK_ROOT="${ANDROID_NDK_HOME:-$default_ndk_path}"
        HOST_TAG=linux-x86_64
        TOOLCHAIN=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG
        export PATH=$TOOLCHAIN/bin:$PATH
        API_LEVEL=23

        case "$target" in
            aarch64-linux-android)
                ANDROID_ABI=arm64-v8a
                log_info "Initializing Android NDK for arm64-v8a (API $API_LEVEL)"
                ;;
            arm-linux-android)
                ANDROID_ABI=armeabi-v7a
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

# 获取目标配置
get_target_config() {
    local target_name="$1"
    
    # 定义目标映射
    case "$target_name" in
        "arm-linux-gnueabihf")
            echo "arm-linux-gnueabihf:${TOOLCHAIN_DIR}/arm-linux-gnueabihf.cmake:${RKMPP_OUTPUT_DIR}/arm-linux-gnueabihf"
            ;;
        "aarch64-linux-gnu")
            echo "aarch64-linux-gnu:${TOOLCHAIN_DIR}/aarch64-linux-gnu.cmake:${RKMPP_OUTPUT_DIR}/aarch64-linux-gnu"
            ;;
        "arm-linux-musleabihf")
            echo "arm-linux-musleabihf:${TOOLCHAIN_DIR}/arm-none-linux-musleabihf.cmake:${RKMPP_OUTPUT_DIR}/arm-linux-musleabihf"
            ;;
        "riscv64-linux-gnu")
            echo "riscv64-linux-gnu:${TOOLCHAIN_DIR}/riscv64-linux-gnu.cmake:${RKMPP_OUTPUT_DIR}/riscv64-linux-gnu"
            ;;
        "riscv64-linux-musl")
            echo "riscv64-linux-musl:${TOOLCHAIN_DIR}/riscv64-linux-musl.cmake:${RKMPP_OUTPUT_DIR}/riscv64-linux-musl"
            ;;
        "aarch64-linux-musl")
            echo "aarch64-linux-musl:${TOOLCHAIN_DIR}/aarch64-linux-musl.cmake:${RKMPP_OUTPUT_DIR}/aarch64-linux-musl"
            ;;
        "aarch64-linux-android")
            echo "aarch64-linux-android:android:${RKMPP_OUTPUT_DIR}/aarch64-linux-android"
            ;;
        "arm-linux-android")
            echo "arm-linux-android:android:${RKMPP_OUTPUT_DIR}/arm-linux-android"
            ;;
        "x86_64-linux-gnu")
            echo "x86_64-linux-gnu:${TOOLCHAIN_DIR}/x86_64-linux-gnu.cmake:${RKMPP_OUTPUT_DIR}/x86_64-linux-gnu"
            ;;
        "x86_64-windows-gnu")
            echo "x86_64-windows-gnu:${TOOLCHAIN_DIR}/x86_64-windows-gnu.cmake:${RKMPP_OUTPUT_DIR}/x86_64-windows-gnu"
            ;;
        "x86_64-macos")
            echo "x86_64-macos:${TOOLCHAIN_DIR}/x86_64-macos.cmake:${RKMPP_OUTPUT_DIR}/x86_64-macos"
            ;;
        "aarch64-macos")
            echo "aarch64-macos:${TOOLCHAIN_DIR}/aarch64-macos.cmake:${RKMPP_OUTPUT_DIR}/aarch64-macos"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 获取默认编译目标列表
get_default_build_targets() {
    # 如果私有变量不存在或为空，返回所有目标的配置
    if [ -z "$_DEFAULT_BUILD_TARGETS" ]; then
        # 所有目标的配置
        echo "arm-linux-gnueabihf:${TOOLCHAIN_DIR}/arm-linux-gnueabihf.cmake:${RKMPP_OUTPUT_DIR}/arm-linux-gnueabihf"
        echo "aarch64-linux-gnu:${TOOLCHAIN_DIR}/aarch64-linux-gnu.cmake:${RKMPP_OUTPUT_DIR}/aarch64-linux-gnu"
        echo "arm-linux-musleabihf:${TOOLCHAIN_DIR}/arm-none-linux-musleabihf.cmake:${RKMPP_OUTPUT_DIR}/arm-linux-musleabihf"
        echo "riscv64-linux-gnu:${TOOLCHAIN_DIR}/riscv64-linux-gnu.cmake:${RKMPP_OUTPUT_DIR}/riscv64-linux-gnu"
        echo "riscv64-linux-musl:${TOOLCHAIN_DIR}/riscv64-linux-musl.cmake:${RKMPP_OUTPUT_DIR}/riscv64-linux-musl"
        echo "aarch64-linux-musl:${TOOLCHAIN_DIR}/aarch64-linux-musl.cmake:${RKMPP_OUTPUT_DIR}/aarch64-linux-musl"
        echo "aarch64-linux-android:android:${RKMPP_OUTPUT_DIR}/aarch64-linux-android"
        echo "arm-linux-android:android:${RKMPP_OUTPUT_DIR}/arm-linux-android"
        echo "x86_64-linux-gnu:${TOOLCHAIN_DIR}/x86_64-linux-gnu.cmake:${RKMPP_OUTPUT_DIR}/x86_64-linux-gnu"
        echo "x86_64-windows-gnu:${TOOLCHAIN_DIR}/x86_64-windows-gnu.cmake:${RKMPP_OUTPUT_DIR}/x86_64-windows-gnu"
        echo "x86_64-macos:${TOOLCHAIN_DIR}/x86_64-macos.cmake:${RKMPP_OUTPUT_DIR}/x86_64-macos"
        echo "aarch64-macos:${TOOLCHAIN_DIR}/aarch64-macos.cmake:${RKMPP_OUTPUT_DIR}/aarch64-macos"
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

# 验证目标名称
validate_target() {
    local target="$1"
    local valid_targets=("arm-linux-gnueabihf" "aarch64-linux-gnu" "arm-linux-musleabihf" "riscv64-linux-gnu" "riscv64-linux-musl" "aarch64-linux-musl" "aarch64-linux-android" "arm-linux-android" "x86_64-linux-gnu" "x86_64-windows-gnu" "x86_64-macos" "aarch64-macos")
    
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
        log_error "Valid targets: arm-linux-gnueabihf, aarch64-linux-gnu, arm-linux-musleabihf, riscv64-linux-gnu, riscv64-linux-musl, aarch64-linux-musl, aarch64-linux-android, arm-linux-android, x86_64-linux-gnu, x86_64-windows-gnu, x86_64-macos, aarch64-macos"
        exit 1
    fi
    
    echo "$target"
}

# 主函数
main() {
    local target_to_build="$1"
    
    log_info "Starting RK MPP build process..."
    
    # 检查工具
    check_tools
    
    # 克隆源码
    clone_mpp
    
    # 创建输出目录
    mkdir -p "$RKMPP_OUTPUT_DIR"
    
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
        if [[ "$target_to_build" == "aarch64-linux-android" || "$target_to_build" == "arm-linux-android" ]]; then
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
            if [[ "$target_name" == "aarch64-linux-android" || "$target_name" == "arm-linux-android" ]]; then
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
    fi
    
    log_success "Build process completed!"
    log_info "Output directory: $RKMPP_OUTPUT_DIR"
    
    # 生成version.ini文件
    create_version_file

    # 显示目录结构
    log_info "Directory structure:"
    tree "$RKMPP_OUTPUT_DIR" 2>/dev/null || ls -la "$RKMPP_OUTPUT_DIR"
}


# 创建版本信息文件
create_version_file() {
    log_info "Creating version.ini file..."
    
    local version_file="${RKMPP_OUTPUT_DIR}/version.ini"
    local changelog_file="${MPP_SOURCE_DIR}/CHANGELOG.md"
    
    # 检查CHANGELOG.md是否存在
    if [ ! -f "$changelog_file" ]; then
        log_warning "CHANGELOG.md not found: $changelog_file"
        echo "version=unknown" > "$version_file"
        log_warning "Created version.ini with unknown version"
        return 0
    fi
    
    # 提取最新版本号（格式：## 1.10.4 （2025-04-03））
    local latest_version
    latest_version=$(grep -E "^## [0-9]+\.[0-9]+\.[0-9]+" "$changelog_file" | head -1 | sed -E 's/^## ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
    
    if [ -z "$latest_version" ]; then
        log_warning "Could not extract version from CHANGELOG.md"
        echo "version=unknown" > "$version_file"
        log_warning "Created version.ini with unknown version"
        return 0
    fi
    
    # 写入版本信息到version.ini
    cat > "$version_file" << EOF
[version]
version=$latest_version
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Version file created successfully: $version_file"
        log_info "Latest version: $latest_version"
    else
        log_error "Failed to create version file: $version_file"
        return 1
    fi
}


# 清理函数
cleanup() {
    log_info "Cleaning up..."
    
    # 清理构建目录
    if [ -d "${MPP_SOURCE_DIR}" ]; then
        find "${MPP_SOURCE_DIR}" -name "build_*" -type d -exec rm -rf {} + 2>/dev/null || true
    fi
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
    if [ -d "${RKMPP_OUTPUT_DIR}" ]; then
        log_info "Removing output directory: ${RKMPP_OUTPUT_DIR}"
        rm -rf "${RKMPP_OUTPUT_DIR}"
    fi
    
    log_success "Clean completed"
}

# 帮助信息
show_help() {
    echo "RK MPP Build Script"
    echo ""
    echo "Usage: $0 [OPTIONS] [TARGET]"
    echo ""
    echo "TARGET (optional):"
    echo "  arm-linux-gnueabihf    Build ARM 32-bit glibc version"
    echo "  aarch64-linux-gnu      Build ARM 64-bit glibc version"
    echo "  riscv64-linux-gnu      Build RISC-V 64-bit glibc version"
    echo "  arm-linux-musleabihf   Build ARM 32-bit musl version"
    echo "  aarch64-linux-musl     Build ARM 64-bit musl version"
    echo "  riscv64-linux-musl     Build RISC-V 64-bit musl version"
    echo "  aarch64-linux-android  Build Android ARM 64-bit version"
    echo "  arm-linux-android      Build Android ARM 32-bit version"
    echo "  x86_64-linux-gnu       Build x86_64 Linux version"
    echo "  x86_64-windows-gnu     Build x86_64 Windows version"
    echo "  x86_64-macos           Build x86_64 macOS version"
    echo "  aarch64-macos          Build ARM 64-bit macOS version"
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
    echo "  $0                    # Build default targets (aarch64-linux-gnu, arm-linux-gnueabihf, aarch64-linux-android, arm-linux-android)"
    echo "  $0 aarch64-linux-gnu  # Build only ARM 64-bit glibc version"
    echo "  $0 arm-linux-musleabihf # Build only ARM 32-bit musl version"
    echo "  $0 aarch64-linux-android # Build Android ARM 64-bit version"
    echo "  $0 arm-linux-android   # Build Android ARM 32-bit version"
    echo "  $0 x86_64-linux-gnu   # Build x86_64 Linux version"
    echo "  $0 --clean           # Clean build directories"
    echo "  $0 --clean-all       # Clean everything"
    echo ""
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

