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

# 构建类型默认配置
BUILD_TYPE="Release"
BUILD_TYPE_LOWER="release"
BUILD_TYPE_SET="false"
PARSED_TARGET=""

# 默认构建类型配置
BUILD_TYPE="Release"
BUILD_TYPE_LOWER="release"
BUILD_TYPE_SET="false"
PARSED_TARGET=""

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

set_build_type_from_arg() {
    local value="$1"

    if [ -z "$value" ]; then
        log_error "Missing value for --build_type"
        exit 1
    fi

    local normalized
    normalized=$(echo "$value" | tr '[:upper:]' '[:lower:]')

    case "$normalized" in
        debug)
            if [ "$BUILD_TYPE_SET" = "true" ] && [ "$BUILD_TYPE_LOWER" != "debug" ]; then
                log_error "Conflicting build type arguments detected"
                exit 1
            fi
            BUILD_TYPE="Debug"
            BUILD_TYPE_LOWER="debug"
            BUILD_TYPE_SET="true"
            ;;
        release)
            if [ "$BUILD_TYPE_SET" = "true" ] && [ "$BUILD_TYPE_LOWER" != "release" ]; then
                log_error "Conflicting build type arguments detected"
                exit 1
            fi
            BUILD_TYPE="Release"
            BUILD_TYPE_LOWER="release"
            BUILD_TYPE_SET="true"
            ;;
        *)
            log_error "Invalid build type value: $value (expected Debug or Release)"
            exit 1
            ;;
    esac
}

set_build_type_from_arg() {
    local value="$1"

    if [ -z "$value" ]; then
        log_error "Missing value for --build_type"
        exit 1
    fi

    local normalized
    normalized=$(echo "$value" | tr '[:upper:]' '[:lower:]')

    case "$normalized" in
        debug)
            if [ "$BUILD_TYPE_SET" = "true" ] && [ "$BUILD_TYPE_LOWER" != "debug" ]; then
                log_error "Conflicting build type arguments detected"
                exit 1
            fi
            BUILD_TYPE="Debug"
            BUILD_TYPE_LOWER="debug"
            BUILD_TYPE_SET="true"
            ;;
        release)
            if [ "$BUILD_TYPE_SET" = "true" ] && [ "$BUILD_TYPE_LOWER" != "release" ]; then
                log_error "Conflicting build type arguments detected"
                exit 1
            fi
            BUILD_TYPE="Release"
            BUILD_TYPE_LOWER="release"
            BUILD_TYPE_SET="true"
            ;;
        *)
            log_error "Invalid build type value: $value (expected Debug or Release)"
            exit 1
            ;;
    esac
}

# 检查工具
check_tools() {
    local required_tools=("meson" "ninja" "git")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
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


# 目标配置映射
declare -A TARGET_CONFIGS=(
    ["arm-linux-gnueabihf"]="arm-linux-gnueabihf:${RKRGA_OUTPUT_DIR}/arm-linux-gnueabihf:${OUTPUTS_DIR}/libdrm/arm-linux-gnueabihf:arm-linux-gnueabihf:ARM"
    ["aarch64-linux-gnu"]="aarch64-linux-gnu:${RKRGA_OUTPUT_DIR}/aarch64-linux-gnu:${OUTPUTS_DIR}/libdrm/aarch64-linux-gnu:aarch64-linux-gnu:AArch64"
    ["arm-linux-musleabihf"]="arm-linux-musleabihf:${RKRGA_OUTPUT_DIR}/arm-linux-musleabihf:${OUTPUTS_DIR}/libdrm/arm-linux-musleabihf:arm-linux-musleabihf:ARM"
    ["aarch64-linux-musl"]="aarch64-linux-musl:${RKRGA_OUTPUT_DIR}/aarch64-linux-musl:${OUTPUTS_DIR}/libdrm/aarch64-linux-musl:aarch64-linux-musl:AArch64"
    ["riscv64-linux-gnu"]="riscv64-linux-gnu:${RKRGA_OUTPUT_DIR}/riscv64-linux-gnu:${OUTPUTS_DIR}/libdrm/riscv64-linux-gnu:riscv64-linux-gnu:RISC-V"
    ["riscv64-linux-musl"]="riscv64-linux-musl:${RKRGA_OUTPUT_DIR}/riscv64-linux-musl:${OUTPUTS_DIR}/libdrm/riscv64-linux-musl:riscv64-linux-musl:RISC-V"
    ["aarch64-linux-android"]="aarch64-linux-android:${RKRGA_OUTPUT_DIR}/aarch64-linux-android:${OUTPUTS_DIR}/libdrm/aarch64-linux-android:aarch64-linux-android:AArch64"
    ["arm-linux-android"]="arm-linux-android:${RKRGA_OUTPUT_DIR}/arm-linux-android:${OUTPUTS_DIR}/libdrm/arm-linux-android:arm-linux-android:ARM"
    ["x86_64-linux-gnu"]="x86_64-linux-gnu:${RKRGA_OUTPUT_DIR}/x86_64-linux-gnu:${OUTPUTS_DIR}/libdrm/x86_64-linux-gnu:x86_64-linux-gnu:x86_64"
    ["x86_64-windows-gnu"]="x86_64-windows-gnu:${RKRGA_OUTPUT_DIR}/x86_64-windows-gnu:${OUTPUTS_DIR}/libdrm/x86_64-windows-gnu:x86_64-windows-gnu:x86_64"
    ["x86_64-macos"]="x86_64-macos:${RKRGA_OUTPUT_DIR}/x86_64-macos:${OUTPUTS_DIR}/libdrm/x86_64-macos:x86_64-macos:x86_64"
    ["aarch64-macos"]="aarch64-macos:${RKRGA_OUTPUT_DIR}/aarch64-macos:${OUTPUTS_DIR}/libdrm/aarch64-macos:aarch64-macos:AArch64"
)

# 记录成功构建的输出目录
declare -a COMPLETED_OUTPUT_DIRS=()

# 获取目标配置
get_target_config() {
    local target="$1"
    echo "${TARGET_CONFIGS[$target]:-}"
}

get_output_dir_for_build_type() {
    local base_dir="$1"

    if [ "$BUILD_TYPE_LOWER" = "debug" ]; then
        echo "${base_dir}-debug"
    else
        echo "$base_dir"
    fi
}

# 检查并构建 libdrm 依赖
check_and_build_libdrm_dependency() {
    local target="$1"
    local config="${TARGET_CONFIGS[$target]:-}"
    
    if [ -z "$config" ]; then
        log_error "Invalid target: $target"
        return 1
    fi
    
    local cfg_target cfg_output_dir cfg_libdrm_dir cfg_cross_prefix cfg_expected_arch
    IFS=':' read -r cfg_target cfg_output_dir cfg_libdrm_dir cfg_cross_prefix cfg_expected_arch <<< "$config"
    local effective_libdrm_dir
    effective_libdrm_dir=$(get_output_dir_for_build_type "$cfg_libdrm_dir")
    
    # 检查 libdrm 依赖目录是否存在
    if [ -d "$effective_libdrm_dir" ]; then
        log_success "libdrm dependency already exists: $effective_libdrm_dir"
        return 0
    fi
    
    log_info "libdrm dependency not found: $effective_libdrm_dir"
    log_info "Building libdrm dependency for target: $cfg_target"
    
    # 检查 libdrm 构建脚本是否存在
    local libdrm_build_script="${WORKSPACE_DIR}/scripts/libdrm/build.sh"
    if [ ! -f "$libdrm_build_script" ]; then
        log_error "libdrm build script not found: $libdrm_build_script"
        return 1
    fi
    
    # 调用 libdrm 构建脚本，透传目标参数
    log_info "Executing: $libdrm_build_script --build_type $BUILD_TYPE $cfg_target"
    if ! "$libdrm_build_script" --build_type "$BUILD_TYPE" "$cfg_target"; then
        log_error "libdrm dependency build failed for target: $cfg_target"
        return 1
    fi
    
    # 验证构建结果
    if [ ! -d "$effective_libdrm_dir" ]; then
        log_error "libdrm dependency build completed but directory not found: $effective_libdrm_dir"
        return 1
    fi
    
    log_success "libdrm dependency built successfully: $effective_libdrm_dir"
    return 0
}

# 设置 libdrm 依赖
setup_libdrm_dependency() {
    local target="$1"
    
    # 先检查并构建依赖
    if ! check_and_build_libdrm_dependency "$target"; then
        return 1
    fi
    
    local config="${TARGET_CONFIGS[$target]:-}"
    local cfg_target cfg_output_dir cfg_libdrm_dir cfg_cross_prefix cfg_expected_arch
    IFS=':' read -r cfg_target cfg_output_dir cfg_libdrm_dir cfg_cross_prefix cfg_expected_arch <<< "$config"
    local effective_libdrm_dir
    effective_libdrm_dir=$(get_output_dir_for_build_type "$cfg_libdrm_dir")

    export PKG_CONFIG_PATH="${effective_libdrm_dir}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    export LD_LIBRARY_PATH="${effective_libdrm_dir}/lib:${LD_LIBRARY_PATH}"
    log_success "libdrm dependency setup completed"
}

# 构建单个目标
build_target() {
    local target_name="$1"
    
    log_info "Building target: $target_name"
    
    # 获取目标配置
    local config="${TARGET_CONFIGS[$target_name]:-}"
    if [ -z "$config" ]; then
        log_error "Invalid target configuration: $target_name"
        return 1
    fi
    
    local base_output_dir cross_prefix expected_arch
    IFS=':' read -r _ base_output_dir _ cross_prefix expected_arch <<< "$config"

    local output_dir
    output_dir=$(get_output_dir_for_build_type "$base_output_dir")

    log_info "Resolved output directory: $output_dir"

    if ! setup_libdrm_dependency "$target_name"; then
        return 1
    fi

    mkdir -p "$output_dir"
    local build_dir="${LIBRGA_SOURCE_DIR}/build_${target_name}"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"
    
    # Meson 配置选项
    local meson_options="--buildtype=${BUILD_TYPE_LOWER} --default-library=shared --libdir=lib"
    meson_options+=" -Dcpp_args=-fpermissive -Dlibdrm=true -Dlibrga_demo=false"
    
    # Android 特殊处理
    if [[ "$target_name" == *"-android" ]]; then
        if ! setup_android_cross_compile "$target_name"; then
            return 1
        fi
        meson_options+=" --cross-file=${SCRIPT_DIR}/android-cross.txt"
    elif [ -n "$cross_prefix" ]; then
        # 非Android目标：使用交叉编译
        if ! setup_cross_compile "$target_name" "$cross_prefix"; then
            log_warning "Cross compiler ${cross_prefix}gcc not found, using native build"
        else
            meson_options+=" --cross-file=${SCRIPT_DIR}/cross-${target_name}.txt"
        fi
    fi
    
    # 执行 Meson 构建
    log_info "Configuring with meson..."
    
    # 确保使用交叉编译文件
    if [[ "$target_name" == *"-android" ]]; then
        if [ -f "${SCRIPT_DIR}/android-cross.txt" ]; then
            meson_options="$meson_options --cross-file=${SCRIPT_DIR}/android-cross.txt"
            log_info "Using Android cross-file: ${SCRIPT_DIR}/android-cross.txt"
        fi
    elif [ -n "$cross_prefix" ] && [ -f "${SCRIPT_DIR}/cross-${target_name}.txt" ]; then
        meson_options="$meson_options --cross-file=${SCRIPT_DIR}/cross-${target_name}.txt"
        log_info "Using cross-file: ${SCRIPT_DIR}/cross-${target_name}.txt"
    else
        log_warning "Cross-file not found or not specified, using native build"
    fi
    
    meson setup "$build_dir" "$LIBRGA_SOURCE_DIR" --prefix "$output_dir" $meson_options
    
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
    
    # 获取交叉编译前缀并检测可用工具
    local cross_prefix
    cross_prefix=$(get_cross_compile_prefix "$target_name")
    local available_tools
    available_tools=$(check_cross_compile_tools "$cross_prefix")
    
    # 压缩库文件
    if [ "$BUILD_TYPE_LOWER" = "debug" ]; then
        log_info "Debug build type detected, skipping library compression"
    else
        compress_libraries "$output_dir" "$target_name" "$available_tools"
    fi
    
    # 验证构建架构
    validate_build_architecture "$output_dir" "$target_name"

    COMPLETED_OUTPUT_DIRS+=("$output_dir")

    return 0
}

# 设置 Android 交叉编译
setup_android_cross_compile() {
    local target_name="$1"
    
    local ndk_path="${ANDROID_NDK_HOME:-$HOME/sdk/android_ndk/android-ndk-r25c}"
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
        *)
            log_error "Unsupported Android target: $target_name"
            return 1
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
    
    return 0
}

# 设置交叉编译
setup_cross_compile() {
    local target_name="$1"
    local cross_prefix="$2"
    
    # 检查交叉编译工具是否可用
    if ! command -v "${cross_prefix}-gcc" &> /dev/null; then
        return 1
    fi
    
    log_info "Using cross compiler: ${cross_prefix}-gcc"
    
    # 创建交叉编译文件
    local cross_file="${SCRIPT_DIR}/cross-${target_name}.txt"
    cat > "$cross_file" << EOF
[binaries]
c = ['${cross_prefix}-gcc']
cpp = ['${cross_prefix}-g++']
ar = ['${cross_prefix}-ar']
strip = ['${cross_prefix}-strip']
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
    
    return 0
}



# 检查交叉编译工具
check_cross_compile_tools() {
    local cross_prefix="$1"
    local available_tools=""
    
    # 使用 stderr 输出调试信息，避免被命令替换捕获
    log_info "Checking available compression tools for cross-compilation..." >&2
    log_info "Cross prefix: '$cross_prefix'" >&2
    
    # 特殊处理 Android 目标
    if [[ "$cross_prefix" == *"android"* ]]; then
        log_info "Android target detected, using LLVM tools from Android NDK" >&2
        
        # 检查 Android NDK 中的 LLVM 工具
        local ndk_path="/home/kemove/sdk/android_ndk/android-ndk-r25c"
        local llvm_bin="$ndk_path/toolchains/llvm/prebuilt/linux-x86_64/bin"
        
        # 检查 llvm-strip
        if [ -f "$llvm_bin/llvm-strip" ]; then
            available_tools="${available_tools}strip:$llvm_bin/llvm-strip "
            log_info "✓ Found Android LLVM strip tool: $llvm_bin/llvm-strip" >&2
        elif command -v "llvm-strip" >/dev/null 2>&1; then
            available_tools="${available_tools}strip:llvm-strip "
            log_info "✓ Found system LLVM strip tool" >&2
        else
            log_warning "No LLVM strip tool available for Android target" >&2
        fi
        
        # 检查 llvm-objcopy
        if [ -f "$llvm_bin/llvm-objcopy" ]; then
            available_tools="${available_tools}objcopy:$llvm_bin/llvm-objcopy "
            log_info "✓ Found Android LLVM objcopy tool: $llvm_bin/llvm-objcopy" >&2
        elif command -v "llvm-objcopy" >/dev/null 2>&1; then
            available_tools="${available_tools}objcopy:llvm-objcopy "
            log_info "✓ Found system LLVM objcopy tool" >&2
        else
            log_warning "No LLVM objcopy tool available for Android target" >&2
        fi
    else
        
        # 检查交叉编译 strip 工具
        if command -v "${cross_prefix}-strip" >/dev/null 2>&1; then
            available_tools="${available_tools}strip:${cross_prefix}-strip "
            log_info "✓ Found cross strip tool: ${cross_prefix}-strip" >&2
        elif command -v "strip" >/dev/null 2>&1; then
            available_tools="${available_tools}strip:strip "
            log_info "✓ Found system strip tool" >&2
        else
            log_warning "No strip tool available for this target" >&2
        fi
        
        # 检查交叉编译 objcopy 工具
        if command -v "${cross_prefix}-objcopy" >/dev/null 2>&1; then
            available_tools="${available_tools}objcopy:${cross_prefix}-objcopy "
            log_info "✓ Found cross objcopy tool: ${cross_prefix}-objcopy" >&2
        elif command -v "objcopy" >/dev/null 2>&1; then
            available_tools="${available_tools}objcopy:objcopy "
            log_info "✓ Found system objcopy tool" >&2
        else
            log_warning "No objcopy tool available for this target" >&2
        fi
    fi
    
    # 检查 UPX 工具（仅适用于本机架构）
    if command -v "upx" >/dev/null 2>&1; then
        available_tools="${available_tools}upx:upx "
        log_info "✓ Found UPX compression tool" >&2
    else
        log_info "UPX not available for this target" >&2
    fi
    
    # 如果没有任何工具可用，记录警告
    if [ -z "$available_tools" ]; then
        log_warning "No compression tools available for target: $cross_prefix" >&2
    else
        log_info "Available tools: $available_tools" >&2
    fi
    
    # 只返回工具列表，不包含调试信息
    echo "$available_tools"
}

# 获取交叉编译前缀
get_cross_compile_prefix() {
    local target_name="$1"
    local config="${TARGET_CONFIGS[$target_name]:-}"
    
    if [ -z "$config" ]; then
        echo ""
        return 0
    fi
    
    local cfg_target cfg_output_dir cfg_libdrm_dir cfg_cross_prefix cfg_expected_arch
    IFS=':' read -r cfg_target cfg_output_dir cfg_libdrm_dir cfg_cross_prefix cfg_expected_arch <<< "$config"
    echo "$cfg_cross_prefix"
}

# 压缩库文件
compress_libraries() {
    local output_dir="$1"
    local target_name="$2"
    local available_tools="$3"
    
    log_info "Compressing libraries for $target_name..."
    
    # 获取交叉编译前缀
    local cross_prefix
    cross_prefix=$(get_cross_compile_prefix "$target_name")
    
    # 如果没有传入 available_tools，则检测工具
    if [ -z "$available_tools" ]; then
        available_tools=$(check_cross_compile_tools "$cross_prefix")
    fi
    
    local lib_files
    lib_files=$(find "$output_dir" -type f \( -name "*.so*" -o -name "*.a" \) 2>/dev/null || true)
    
    if [ -z "$lib_files" ]; then
        log_warning "No library files found to compress"
        return 0
    fi
    
    local compressed_count=0
    local total_original_size=0
    local total_compressed_size=0
    
    # 解析可用工具
    local strip_tool=""
    local objcopy_tool=""
    local upx_tool=""
    
    # 使用空格分隔解析工具
    IFS=' ' read -ra tools <<< "$available_tools"
    for tool_info in "${tools[@]}"; do
        if [[ "$tool_info" == strip:* ]]; then
            strip_tool="${tool_info#strip:}"
        elif [[ "$tool_info" == objcopy:* ]]; then
            objcopy_tool="${tool_info#objcopy:}"
        elif [[ "$tool_info" == upx:* ]]; then
            upx_tool="${tool_info#upx:}"
        fi
    done
    
    log_info "Available compression tools:"
    [ -n "$strip_tool" ] && log_info "  Strip: $strip_tool"
    [ -n "$objcopy_tool" ] && log_info "  Objcopy: $objcopy_tool"
    [ -n "$upx_tool" ] && log_info "  UPX: $upx_tool"
    
    while IFS= read -r lib_file; do
        [ -z "$lib_file" ] && continue
        
        local original_size
        original_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "0")
        total_original_size=$((total_original_size + original_size))
        
        local final_size=$original_size
        local compression_applied=false
        
        # 使用 strip 工具优化
        if [ -n "$strip_tool" ]; then
            local backup_file="${lib_file}.backup"
            cp "$lib_file" "$backup_file"
            
            if [[ "$lib_file" == *.so* ]]; then
                "$strip_tool" --strip-unneeded "$lib_file" 2>/dev/null || true
            else
                "$strip_tool" --strip-debug "$lib_file" 2>/dev/null || true
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
    else
        log_info "No significant compression achieved for $target_name (files may already be optimized)"
    fi
}

# 验证构建架构
validate_build_architecture() {
    local output_dir="$1"
    local target_name="$2"
    
    log_info "Validating build architecture for $target_name..."
    
    # 获取目标配置中的预期架构
    local config="${TARGET_CONFIGS[$target_name]:-}"
    if [ -z "$config" ]; then
        log_warning "Unknown target for validation: $target_name"
        return 0
    fi
    
    IFS=':' read -r target_name output_dir libdrm_dir cross_prefix expected_arch <<< "$config"
    
    local lib_files
    lib_files=$(find "$output_dir" -type f \( -name "*.so*" -o -name "*.a" \) 2>/dev/null || true)
    
    if [ -z "$lib_files" ]; then
        log_warning "No library files found for validation"
        return 0
    fi
    
    local validation_passed=true
    local arch_patterns=()
    
    # 设置架构匹配模式
    case "$expected_arch" in
        "ARM")
            arch_patterns=("ARM" "32-bit" "arm")
            ;;
        "AArch64")
            arch_patterns=("AArch64" "aarch64" "64-bit" "ARM64")
            ;;
        "RISC-V")
            arch_patterns=("RISC-V" "riscv64")
            ;;
        "x86_64")
            arch_patterns=("x86-64" "x86_64" "64-bit")
            ;;
        *)
            log_info "Architecture validation skipped for unknown target: $expected_arch"
            return 0
            ;;
    esac
    
    while IFS= read -r lib_file; do
        [ -z "$lib_file" ] && continue
        
        local file_info
        file_info=$(file "$lib_file" 2>/dev/null || echo "Unknown file type")
        
        # 检查是否包含错误的架构
        if echo "$file_info" | grep -q -E "(x86-64|x86_64)"; then
            if [ "$expected_arch" != "x86_64" ]; then
                log_warning "Architecture mismatch: Expected $expected_arch, but got x86-64"
                validation_passed=false
                continue
            fi
        fi
        
        # 检查是否匹配预期架构
        local pattern_matched=false
        for pattern in "${arch_patterns[@]}"; do
            if echo "$file_info" | grep -q -E "$pattern"; then
                pattern_matched=true
                break
            fi
        done
        
        if [ "$pattern_matched" = "true" ]; then
            log_success "✓ Architecture matches expected $expected_arch"
        else
            log_warning "Architecture detection inconclusive for $expected_arch"
        fi
        
    done <<< "$lib_files"
    
    if [ "$validation_passed" = "true" ]; then
        log_success "Architecture validation passed for $target_name ($expected_arch)"
        return 0
    else
        log_error "Architecture validation failed for $target_name"
        return 1
    fi
}

# 构建单个目标
build_single_target() {
    local target="$1"
    local target_config
    target_config=$(get_target_config "$target")
    
    if [ -z "$target_config" ]; then
        log_error "Invalid target: $target"
        return 1
    fi
    
    local cfg_target cfg_output_dir
    IFS=':' read -r cfg_target cfg_output_dir <<< "$target_config"
    if build_target "$cfg_target"; then
        log_success "$target build completed"
        return 0
    else
        log_error "$target build failed"
        return 1
    fi
}

# 构建多个目标
build_multiple_targets() {
    local targets=("$@")
    local success_count=0
    local failure_count=0
    
    for target in "${targets[@]}"; do
        if build_single_target "$target"; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
    done
    
    log_info "Build summary: $success_count successful, $failure_count failed"
    
    if [ $failure_count -gt 0 ]; then
        log_warning "Some builds failed, but continuing..."
    fi
    
    return $((failure_count > 0 ? 1 : 0))
}

parse_arguments() {
    local target=""

    BUILD_TYPE="Release"
    BUILD_TYPE_LOWER="release"
    BUILD_TYPE_SET="false"
    PARSED_TARGET=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            --build_type)
                if [ -z "${2:-}" ]; then
                    log_error "--build_type requires a value (Debug or Release)"
                    exit 1
                fi
                set_build_type_from_arg "$2"
                shift 2
                continue
                ;;
            --build_type=*)
                set_build_type_from_arg "${1#*=}"
                shift
                continue
                ;;
            Debug|debug|Release|release)
                log_error "Build type must be specified using --build_type"
                exit 1
                ;;
            -* )
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

    PARSED_TARGET="$target"
}

# 主函数
main() {
    local target="${1:-}"
    
    check_tools
    clone_librga
    mkdir -p "$RKRGA_OUTPUT_DIR"
    apply_meson_clockskew_patch    

    log_info "当前构建类型: $BUILD_TYPE"

    if [ -n "$target" ]; then
        # 构建单个目标
        if build_single_target "$target"; then
            log_success "Build completed successfully"
        else
            log_error "Build failed"
            exit 1
        fi
    else
        # 构建默认目标
        IFS=',' read -r -a default_targets <<< "$_DEFAULT_BUILD_TARGETS"
        build_multiple_targets "${default_targets[@]}"
    fi
    
    # 生成version.ini文件
    create_version_file

    # 显示结果
    if [ ${#COMPLETED_OUTPUT_DIRS[@]} -gt 0 ]; then
        log_info "Artifacts installed to:"
        for dir in "${COMPLETED_OUTPUT_DIRS[@]}"; do
            log_info "  - $dir"
            if command -v tree &> /dev/null; then
                tree "$dir"
            else
                ls -la "$dir"
            fi
        done
    else
        log_info "Output directory root: $RKRGA_OUTPUT_DIR"
        if command -v tree &> /dev/null; then
            tree "$RKRGA_OUTPUT_DIR"
        else
            ls -la "$RKRGA_OUTPUT_DIR"
        fi
    fi
}

# 帮助信息
show_help() {
    echo "RK RGA Build Script (Meson)"
    echo ""
    echo "Usage: $0 [OPTIONS] [TARGET]"
    echo ""
    echo "Options:"
    printf "  %-25s %s\n" "--build_type {Debug,Release}" "Set build type (default: Release)"
    printf "  %-25s %s\n" "-h, --help" "Show this help message"
    echo ""
    echo "TARGET (optional):"
    
    # 使用目标配置映射生成帮助信息
    local target_descriptions=(
        "aarch64-linux-gnu:Build ARM 64-bit glibc version"
        "arm-linux-gnueabihf:Build ARM 32-bit glibc version"
        "aarch64-linux-musl:Build ARM 64-bit musl version"
        "arm-linux-musleabihf:Build ARM 32-bit musl version"
        "riscv64-linux-gnu:Build RISC-V 64-bit glibc version"
        "riscv64-linux-musl:Build RISC-V 64-bit musl version"
        "aarch64-linux-android:Build Android ARM 64-bit version"
        "arm-linux-android:Build Android ARM 32-bit version"
        "x86_64-linux-gnu:Build x86 64-bit Linux version"
        "x86_64-windows-gnu:Build x86 64-bit Windows version"
        "x86_64-macos:Build x86 64-bit macOS version"
        "aarch64-macos:Build ARM 64-bit macOS version"
    )
    
    for desc in "${target_descriptions[@]}"; do
        IFS=':' read -r target description <<< "$desc"
        printf "  %-25s %s\n" "$target" "$description"
    done
    
    echo ""
    echo "Examples:"
    echo "  $0                                # Build default targets ($_DEFAULT_BUILD_TARGETS)"
    echo "  $0 aarch64-linux-gnu              # Build only ARM 64-bit GNU libc version"
    echo "  $0 --build_type Debug aarch64-linux-gnu  # Debug build with -debug suffix"
    echo "  $0 aarch64-linux-android          # Build Android ARM 64-bit version"
    echo "  $0 arm-linux-musleabihf           # Build ARM 32-bit musl version"
    echo "  $0 aarch64-linux-musl             # Build ARM 64-bit musl version"
    echo "  $0 x86_64-linux-gnu               # Build x86 64-bit Linux version"
    echo "  $0 --clean                        # Clean all build artifacts"
    echo ""
    echo "Environment Variables:"
    echo "  ANDROID_NDK_HOME      Path to Android NDK (default: ~/sdk/android_ndk/android-ndk-r25c)"
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

parse_arguments "$@"
main "$PARSED_TARGET"