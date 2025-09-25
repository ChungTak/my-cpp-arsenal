#!/bin/bash

# RK RGA 构建脚本 - 基于 Meson 构建系统
# 参考 libdrm 的 meson 构建方式，适配 rkrga 的构建需求

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SOURCES_DIR="${WORKSPACE_DIR}/sources"
OUTPUTS_DIR="${WORKSPACE_DIR}/outputs"
RKRGA_OUTPUT_DIR="${OUTPUTS_DIR}/rkrga"
LIBRGA_SOURCE_DIR="${SOURCES_DIR}/rkrga"

# 限制默认编译目标
_DEFAULT_BUILD_TARGETS="aarch64-linux-gnu,arm-linux-gnueabihf,aarch64-linux-android,arm-linux-android"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查工具
check_tools() {
    for tool in meson ninja git; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Missing required tool: $tool"
            exit 1
        fi
    done
}

# 克隆源码
clone_librga() {
    if [ -d "${LIBRGA_SOURCE_DIR}" ] && [ -f "${LIBRGA_SOURCE_DIR}/meson.build" ]; then
        log_success "librga source already exists"
        return 0
    fi
    
    mkdir -p "${SOURCES_DIR}"
    if [ -d "${LIBRGA_SOURCE_DIR}" ]; then
        rm -rf "${LIBRGA_SOURCE_DIR}"
    fi
    
    log_info "Cloning librga repository..."
    git clone -b jellyfin-rga --depth=1 https://github.com/nyanmisaka/rk-mirrors.git "${LIBRGA_SOURCE_DIR}"
    
    if [ $? -eq 0 ]; then
        log_success "librga cloned successfully"
    else
        log_error "Failed to clone librga"
        exit 1
    fi
}

# 获取目标配置
get_target_config() {
    local target="$1"
    case "$target" in
        "arm-linux-gnueabihf")
            echo "arm-linux-gnueabihf:${RKRGA_OUTPUT_DIR}/arm-linux-gnueabihf"
            ;;
        "aarch64-linux-gnu")
            echo "aarch64-linux-gnu:${RKRGA_OUTPUT_DIR}/aarch64-linux-gnu"
            ;;
        "arm-linux-musleabihf")
            echo "arm-linux-musleabihf:${RKRGA_OUTPUT_DIR}/arm-linux-musleabihf"
            ;;
        "aarch64-linux-musl")
            echo "aarch64-linux-musl:${RKRGA_OUTPUT_DIR}/aarch64-linux-musl"
            ;;
        "riscv64-linux-gnu")
            echo "riscv64-linux-gnu:${RKRGA_OUTPUT_DIR}/riscv64-linux-gnu"
            ;;
        "riscv64-linux-musl")
            echo "riscv64-linux-musl:${RKRGA_OUTPUT_DIR}/riscv64-linux-musl"
            ;;
        "aarch64-linux-android")
            echo "aarch64-linux-android:${RKRGA_OUTPUT_DIR}/aarch64-linux-android"
            ;;
        "arm-linux-android")
            echo "arm-linux-android:${RKRGA_OUTPUT_DIR}/arm-linux-android"
            ;;
        "x86_64-linux-gnu")
            echo "x86_64-linux-gnu:${RKRGA_OUTPUT_DIR}/x86_64-linux-gnu"
            ;;
        "x86_64-windows-gnu")
            echo "x86_64-windows-gnu:${RKRGA_OUTPUT_DIR}/x86_64-windows-gnu"
            ;;
        "x86_64-macos")
            echo "x86_64-macos:${RKRGA_OUTPUT_DIR}/x86_64-macos"
            ;;
        "aarch64-macos")
            echo "aarch64-macos:${RKRGA_OUTPUT_DIR}/aarch64-macos"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 设置 libdrm 依赖
setup_libdrm_dependency() {
    local target="$1"
    local libdrm_dir=""
    
    case "$target" in
        "arm-linux-gnueabihf")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/arm-linux-gnueabihf"
            ;;
        "aarch64-linux-gnu")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/aarch64-linux-gnu"
            ;;
        "arm-linux-musleabihf")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/arm-linux-musleabihf"
            ;;
        "aarch64-linux-musl")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/aarch64-linux-musl"
            ;;
        "riscv64-linux-gnu")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/riscv64-linux-gnu"
            ;;
        "riscv64-linux-musl")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/riscv64-linux-musl"
            ;;
        "aarch64-linux-android")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/aarch64-linux-android"
            ;;
        "arm-linux-android")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/arm-linux-android"
            ;;
        "x86_64-linux-gnu")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/x86_64-linux-gnu"
            ;;
        "x86_64-windows-gnu")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/x86_64-windows-gnu"
            ;;
        "x86_64-macos")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/x86_64-macos"
            ;;
        "aarch64-macos")
            libdrm_dir="${OUTPUTS_DIR}/libdrm/aarch64-macos"
            ;;
        *)
            libdrm_dir="${OUTPUTS_DIR}/libdrm"
            ;;
    esac
    
    if [ ! -d "$libdrm_dir" ]; then
        log_error "libdrm dependency not found: $libdrm_dir"
        return 1
    fi
    
    export PKG_CONFIG_PATH="${libdrm_dir}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="${libdrm_dir}/lib:${LD_LIBRARY_PATH}"
    log_success "libdrm dependency setup completed"
}

# 构建单个目标
build_target() {
    local target_name="$1"
    local output_dir="$2"
    
    log_info "Building target: $target_name"
    
    if ! setup_libdrm_dependency "$target_name"; then
        return 1
    fi
    
    mkdir -p "$output_dir"
    local build_dir="${LIBRGA_SOURCE_DIR}/build_${target_name}"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    
    # Meson 配置选项
    local meson_options="--buildtype=release --default-library=shared --libdir=lib"
    meson_options+=" -Dcpp_args=-fpermissive -Dlibdrm=true -Dlibrga_demo=false"
    
    # 获取目标架构
    local target_arch=""
    case "$target_name" in
        "arm-linux-gnueabihf")
            target_arch="arm-linux-gnueabihf"
            ;;
        "aarch64-linux-gnu")
            target_arch="aarch64-linux-gnu"
            ;;
        "arm-linux-musleabihf")
            target_arch="arm-linux-musleabihf"
            ;;
        "aarch64-linux-musl")
            target_arch="aarch64-linux-musl"
            ;;
        "riscv64-linux-gnu")
            target_arch="riscv64-linux-gnu"
            ;;
        "riscv64-linux-musl")
            target_arch="riscv64-linux-musl"
            ;;
        "aarch64-linux-android")
            target_arch="aarch64-linux-android"
            ;;
        "arm-linux-android")
            target_arch="arm-linux-android"
            ;;
        "x86_64-linux-gnu")
            target_arch="x86_64-linux-gnu"
            ;;
        "x86_64-windows-gnu")
            target_arch="x86_64-windows-gnu"
            ;;
        "x86_64-macos")
            target_arch="x86_64-macos"
            ;;
        "aarch64-macos")
            target_arch="aarch64-macos"
            ;;
        *)
            target_arch="unknown"
            ;;
    esac
    
    # Android 特殊处理
    if [[ "$target_name" == *"-android" ]]; then
        local ndk_path="${ANDROID_NDK_HOME:-$HOME/sdk/android_ndk/android-ndk-r21e}"
        if [ ! -d "$ndk_path" ]; then
            log_error "Android NDK not found: $ndk_path"
            return 1
        fi
        
        local api_level=23
        local android_target=""
        local android_abi=""
        
        case "$target_name" in
            "aarch64-linux-android")
                android_target="aarch64-linux-android"
                android_abi="arm64-v8a"
                ;;
            "arm-linux-android")
                android_target="armv7a-linux-androideabi"
                android_abi="armeabi-v7a"
                ;;
        esac
        
        # 创建 Android 交叉编译文件
        local cross_file="${SCRIPT_DIR}/android-cross.txt"
        cat > "$cross_file" << EOF
[binaries]
c = '${ndk_path}/toolchains/llvm/prebuilt/linux-x86_64/bin/${android_target}${api_level}-clang'
cpp = '${ndk_path}/toolchains/llvm/prebuilt/linux-x86_64/bin/${android_target}${api_level}-clang++'
ar = '${ndk_path}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-ar'
strip = '${ndk_path}/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip'
pkgconfig = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_std = 'c11'
cpp_std = 'c++11'
default_library = 'shared'
EOF
        
        meson_options+=" --cross-file=$cross_file"
    else
        # 非Android目标：使用交叉编译
        local cross_prefix=""
        case "$target_name" in
            "arm-linux-gnueabihf")
                cross_prefix="arm-linux-gnueabihf-"
                ;;
            "aarch64-linux-gnu")
                cross_prefix="aarch64-linux-gnu-"
                ;;
            "riscv64-linux-gnu")
                cross_prefix="riscv64-linux-gnu-"
                ;;
            "riscv64-linux-musl")
                cross_prefix="riscv64-linux-musl-"
                ;;
            "arm-linux-musleabihf")
                cross_prefix="arm-linux-musleabihf-"
                ;;
            "aarch64-linux-musl")
                cross_prefix="aarch64-linux-musl-"
                ;;
            "x86_64-linux-gnu")
                cross_prefix="x86_64-linux-gnu-"
                ;;
            "x86_64-windows-gnu")
                cross_prefix="x86_64-w64-mingw32-"
                ;;
            "x86_64-macos")
                cross_prefix="x86_64-apple-darwin-"
                ;;
            "aarch64-macos")
                cross_prefix="aarch64-apple-darwin-"
                ;;
        esac
        
        if [ -n "$cross_prefix" ]; then
            # 检查交叉编译工具是否可用
            if command -v "${cross_prefix}gcc" &> /dev/null; then
                log_info "Using cross compiler: ${cross_prefix}gcc"
                
                # 创建交叉编译文件
                local cross_file="${SCRIPT_DIR}/cross-${target_name}.txt"
                cat > "$cross_file" << EOF
[binaries]
c = ['${cross_prefix}gcc']
cpp = ['${cross_prefix}g++']
ar = ['${cross_prefix}ar']
strip = ['${cross_prefix}strip']
pkg-config = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_std = 'c11'
cpp_std = 'c++11'
default_library = 'shared'

[properties]
needs_exe_wrapper = true
EOF
                
                meson_options+=" --cross-file=$cross_file"
            else
                log_warning "Cross compiler ${cross_prefix}gcc not found, using native build"
            fi
        fi
    fi
    
    # 执行 Meson 构建
    log_info "Configuring with meson..."
    meson setup "$build_dir" "$LIBRGA_SOURCE_DIR" -Dprefix="$output_dir" $meson_options
    
    if [ $? -ne 0 ]; then
        log_error "Meson configuration failed"
        return 1
    fi
    
    log_info "Building with ninja..."
    ninja -C "$build_dir"
    
    if [ $? -ne 0 ]; then
        log_error "Build failed"
        return 1
    fi
    
    log_info "Installing..."
    ninja -C "$build_dir" install
    
    if [ $? -ne 0 ]; then
        log_error "Install failed"
        return 1
    fi
    
    log_success "$target_name build completed"
    
    # 压缩库文件
    compress_libraries "$output_dir" "$target_name"
    
    # 验证构建架构
    validate_build_architecture "$output_dir" "$target_name"
    
    return 0
}

# 压缩库文件
compress_libraries() {
    local output_dir="$1"
    local target_name="$2"
    
    log_info "Compressing libraries for $target_name..."
    
    local lib_files
    lib_files=$(find "$output_dir" -type f \( -name "*.so*" -o -name "*.a" \) 2>/dev/null || true)
    
    if [ -z "$lib_files" ]; then
        log_warning "No library files found to compress"
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
        
        # 使用 strip 工具优化
        if command -v "strip" &> /dev/null; then
            local backup_file="${lib_file}.backup"
            cp "$lib_file" "$backup_file"
            
            if [[ "$lib_file" == *.so* ]]; then
                strip --strip-unneeded "$lib_file" 2>/dev/null || true
            else
                strip --strip-debug "$lib_file" 2>/dev/null || true
            fi
            
            local stripped_size
            stripped_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "$original_size")
            
            if [ "$stripped_size" -lt "$original_size" ]; then
                final_size=$stripped_size
                compression_applied=true
                rm -f "$backup_file"
            else
                mv "$backup_file" "$lib_file"
            fi
        fi
        
        # 使用 UPX 压缩（仅对共享库）
        if [[ "$lib_file" == *.so* ]] && command -v "upx" &> /dev/null; then
            local compressed_file="${lib_file}.upx"
            
            if upx --best --lzma -o "$compressed_file" "$lib_file" &>/dev/null; then
                local upx_size
                upx_size=$(stat -c%s "$compressed_file" 2>/dev/null || echo "$final_size")
                
                if [ "$upx_size" -lt "$final_size" ]; then
                    mv "$compressed_file" "$lib_file"
                    final_size=$upx_size
                    compression_applied=true
                else
                    rm -f "$compressed_file"
                fi
            else
                rm -f "$compressed_file"
            fi
        fi
        
        total_compressed_size=$((total_compressed_size + final_size))
        
        if [ "$compression_applied" = "true" ]; then
            compressed_count=$((compressed_count + 1))
        fi
        
    done <<< "$lib_files"
    
    if [ "$compressed_count" -gt 0 ]; then
        local total_reduction=0
        if [ "$total_original_size" -gt 0 ]; then
            total_reduction=$(( (total_original_size - total_compressed_size) * 100 / total_original_size ))
        fi
        log_success "Compression summary:"
        log_success "  Files processed: $(echo "$lib_files" | wc -l)"
        log_success "  Files optimized: $compressed_count"
        log_success "  Total size: $total_original_size → $total_compressed_size bytes (-${total_reduction}%)"
    fi
}

# 验证构建架构
validate_build_architecture() {
    local output_dir="$1"
    local target_name="$2"
    
    log_info "Validating build architecture for $target_name..."
    
    local expected_arch=""
    case "$target_name" in
        "arm-linux-gnueabihf"|"arm-linux-musleabihf"|"arm-linux-android")
            expected_arch="ARM"
            ;;
        "aarch64-linux-gnu"|"aarch64-linux-musl"|"aarch64-linux-android"|"aarch64-macos")
            expected_arch="AArch64"
            ;;
        "riscv64-linux-gnu"|"riscv64-linux-musl")
            expected_arch="RISC-V"
            ;;
        "x86_64-linux-gnu"|"x86_64-windows-gnu"|"x86_64-macos")
            expected_arch="x86_64"
            ;;
        *)
            expected_arch="Unknown"
            ;;
    esac
    
    local lib_files
    lib_files=$(find "$output_dir" -type f \( -name "*.so*" -o -name "*.a" \) 2>/dev/null || true)
    
    if [ -z "$lib_files" ]; then
        log_warning "No library files found for validation"
        return 0
    fi
    
    local validation_passed=true
    
    while IFS= read -r lib_file; do
        [ -z "$lib_file" ] && continue
        
        local file_info
        file_info=$(file "$lib_file" 2>/dev/null || echo "Unknown file type")
        
        case "$expected_arch" in
            "ARM")
                if echo "$file_info" | grep -q -E "(x86-64|x86_64)"; then
                    log_warning "Architecture mismatch: Expected ARM, but got x86-64"
                    validation_passed=false
                elif echo "$file_info" | grep -q -E "(ARM|32-bit|arm)"; then
                    log_success "✓ Architecture matches expected ARM"
                else
                    log_info "Architecture detection inconclusive for ARM"
                fi
                ;;
            "AArch64")
                if echo "$file_info" | grep -q -E "(x86-64|x86_64)"; then
                    log_warning "Architecture mismatch: Expected AArch64, but got x86-64"
                    validation_passed=false
                elif echo "$file_info" | grep -q -E "(AArch64|aarch64|64-bit|ARM64)"; then
                    log_success "✓ Architecture matches expected AArch64"
                else
                    log_info "Architecture detection inconclusive for AArch64"
                fi
                ;;
            *)
                log_info "Architecture validation skipped for unknown target"
                ;;
        esac
        
    done <<< "$lib_files"
    
    if [ "$validation_passed" = "true" ]; then
        log_success "Architecture validation passed for $target_name ($expected_arch)"
        return 0
    else
        log_error "Architecture validation failed for $target_name"
        return 1
    fi
}

# 主函数
main() {
    local target="${1:-}"
    
    check_tools
    clone_librga
    mkdir -p "$RKRGA_OUTPUT_DIR"
    
    if [ -n "$target" ]; then
        # 构建单个目标
        local target_config
        target_config=$(get_target_config "$target")
        if [ -z "$target_config" ]; then
            log_error "Invalid target: $target"
            show_help
            exit 1
        fi
        
        IFS=':' read -r target_name output_dir <<< "$target_config"
        if build_target "$target_name" "$output_dir"; then
            log_success "Build completed successfully"
        else
            log_error "Build failed"
            exit 1
        fi
    else
        # 构建默认目标
        # 将_DEFAULT_BUILD_TARGETS字符串转换为数组
        IFS=',' read -r -a default_targets <<< "$_DEFAULT_BUILD_TARGETS"
        for target in "${default_targets[@]}"; do
            local target_config
            target_config=$(get_target_config "$target")
            if [ -n "$target_config" ]; then
                IFS=':' read -r target_name output_dir <<< "$target_config"
                if build_target "$target_name" "$output_dir"; then
                    log_success "$target build completed"
                else
                    log_warning "$target build failed, continuing..."
                fi
            fi
        done
        log_success "All builds completed"
    fi
    
    # 生成version.ini文件
    create_version_file

    # 显示结果
    log_info "Output directory: $RKRGA_OUTPUT_DIR"
    if command -v tree &> /dev/null; then
        tree "$RKRGA_OUTPUT_DIR"
    else
        ls -la "$RKRGA_OUTPUT_DIR"
    fi
}

# 帮助信息
show_help() {
    echo "RK RGA Build Script (Meson)"
    echo ""
    echo "Usage: $0 [TARGET]"
    echo ""
    echo "TARGET (optional):"
    echo "  aarch64-linux-gnu      Build ARM 64-bit glibc version"
    echo "  arm-linux-gnueabihf    Build ARM 32-bit glibc version"
    echo "  aarch64-linux-musl     Build ARM 64-bit musl version"
    echo "  arm-linux-musleabihf   Build ARM 32-bit musl version"
    echo "  riscv64-linux-gnu      Build RISC-V 64-bit glibc version"
    echo "  riscv64-linux-musl     Build RISC-V 64-bit musl version"
    echo "  aarch64-linux-android  Build Android ARM 64-bit version"
    echo "  arm-linux-android      Build Android ARM 32-bit version"
    echo "  x86_64-linux-gnu       Build x86 64-bit Linux version"
    echo "  x86_64-windows-gnu     Build x86 64-bit Windows version"
    echo "  x86_64-macos           Build x86 64-bit macOS version"
    echo "  aarch64-macos          Build ARM 64-bit macOS version"
    echo ""
    echo "Examples:"
    echo "  $0                    # Build default targets ($_DEFAULT_BUILD_TARGETS)"
    echo "  $0 aarch64-linux-gnu  # Build only ARM 64-bit GNU libc version"
    echo "  $0 aarch64-linux-android  # Build Android ARM 64-bit version"
    echo "  $0 arm-linux-musleabihf  # Build ARM 32-bit musl version"
    echo "  $0 aarch64-linux-musl    # Build ARM 64-bit musl version"
    echo "  $0 x86_64-linux-gnu      # Build x86 64-bit Linux version"
    echo "  $0 --clean            # Clean all build artifacts"
    echo ""
    echo "Environment Variables:"
    echo "  ANDROID_NDK_HOME      Path to Android NDK (default: ~/sdk/android_ndk/android-ndk-r21e)"
    echo ""
}

# 创建版本信息文件
create_version_file() {
    log_info "Creating version.ini file..."
    
    local version_file="${RKRGA_OUTPUT_DIR}/version.ini"
    local changelog_file="${LIBRGA_SOURCE_DIR}/CHANGELOG.md"
    
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
    if [ -d "${LIBRGA_SOURCE_DIR}" ]; then
        find "${LIBRGA_SOURCE_DIR}" -name "build_*" -type d -exec rm -rf {} + 2>/dev/null || true
    fi
    # 清理临时交叉编译文件
    find "${SCRIPT_DIR}" -name "*.txt" -type f -delete 2>/dev/null || true
    find "${SCRIPT_DIR}" -name "cross-*.txt" -type f -delete 2>/dev/null || true
    find "${SCRIPT_DIR}" -name "android-cross.txt" -type f -delete 2>/dev/null || true
}

trap cleanup EXIT

# 执行主函数
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$1"
        ;;
esac