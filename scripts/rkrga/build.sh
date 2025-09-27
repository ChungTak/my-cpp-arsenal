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

source "${SCRIPT_DIR}/../common.sh"

reset_build_type_state
PARSED_TARGET=""

# 限制默认编译目标
_DEFAULT_BUILD_TARGETS="aarch64-linux-gnu,arm-linux-gnueabihf,aarch64-linux-android,arm-linux-android"

# 命令执行结果检查
check_command_result() {
    local exit_code="$1"
    local message="$2"

    if [ "$exit_code" -ne 0 ]; then
        log_error "$message"
        exit "$exit_code"
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

# 克隆/更新 librga 源码
clone_librga() {
    log_info "Checking librga repository..."

    mkdir -p "${SOURCES_DIR}"

    if [ -d "${LIBRGA_SOURCE_DIR}" ] && [ -f "${LIBRGA_SOURCE_DIR}/meson.build" ]; then
        log_success "librga source already exists, skipping clone"
        return 0
    fi

    if [ -d "${LIBRGA_SOURCE_DIR}" ]; then
        log_warning "Removing incomplete librga directory"
        rm -rf "${LIBRGA_SOURCE_DIR}"
    fi

    local repo_url="https://github.com/rockchip-linux/rga.git"
    log_info "Cloning librga repository from ${repo_url}..."

    if git clone --depth=1 "$repo_url" "${LIBRGA_SOURCE_DIR}"; then
        log_success "librga repository cloned successfully"
    else
        log_error "Failed to clone librga repository"
        exit 1
    fi
}

# 获取目标配置
get_target_config() {
    local target="$1"
    echo "${TARGET_CONFIGS[$target]:-}"
}

# 检查并构建 libdrm 依赖，返回依赖目录
check_and_build_libdrm_dependency() {
    local target="$1"
    local config
    config=$(get_target_config "$target")

    if [ -z "$config" ]; then
        log_error "Invalid target: $target"
        return 1
    fi

    local _cfg_target _cfg_output_dir cfg_libdrm_dir _cfg_cross_prefix _cfg_expected_arch
    IFS=':' read -r _cfg_target _cfg_output_dir cfg_libdrm_dir _cfg_cross_prefix _cfg_expected_arch <<< "$config"

    local resolved_libdrm_dir
    resolved_libdrm_dir=$(get_output_dir_for_build_type "$cfg_libdrm_dir")

    if [ -z "$resolved_libdrm_dir" ]; then
        log_error "无法解析 libdrm 输出目录"
        return 1
    fi

    if [ ! -d "$resolved_libdrm_dir" ]; then
        log_warning "libdrm 依赖缺失: $resolved_libdrm_dir，尝试自动构建"
        if ! "${SCRIPT_DIR}/../libdrm/build.sh" --build_type "$BUILD_TYPE" "$target"; then
            log_error "自动构建 libdrm 失败，请先构建 libdrm"
            return 1
        fi
    fi

    local pkgconfig_dir="${resolved_libdrm_dir}/lib/pkgconfig"
    if [ ! -f "${pkgconfig_dir}/libdrm.pc" ]; then
        log_warning "缺少 libdrm.pc (期待位置: ${pkgconfig_dir}/libdrm.pc)，尝试重新构建 libdrm"
        if ! "${SCRIPT_DIR}/../libdrm/build.sh" --build_type "$BUILD_TYPE" "$target"; then
            log_error "自动构建 libdrm 失败，请先构建 libdrm"
            return 1
        fi
    fi

    if [ ! -f "${pkgconfig_dir}/libdrm.pc" ]; then
        log_error "缺少 libdrm.pc (期待位置: ${pkgconfig_dir}/libdrm.pc)"
        return 1
    fi

    printf '%s\n' "$resolved_libdrm_dir"
    return 0
}

# 设置 Android 交叉编译
setup_android_cross_compile() {
    local target_name="$1"
    local toolchain_dir
    if ! toolchain_dir="$(_detect_ndk_toolchain_dir)"; then
        log_error "未找到可用的 Android NDK 工具链，请设置 ANDROID_NDK_HOME"
        return 1
    fi

    local api_level=${ANDROID_API_LEVEL:-23}
    local clang_triple=""
    local cpu_family=""
    local cpu=""

    case "$target_name" in
        "aarch64-linux-android")
            clang_triple="aarch64-linux-android"
            cpu_family="aarch64"
            cpu="aarch64"
            ;;
        "arm-linux-android")
            clang_triple="armv7a-linux-androideabi"
            cpu_family="arm"
            cpu="armv7"
            ;;
        *)
            log_error "Unsupported Android target: $target_name"
            return 1
            ;;
    esac

    local cross_file="${SCRIPT_DIR}/android-${target_name}.txt"
    cat > "$cross_file" << EOF
[binaries]
c = '${toolchain_dir}/bin/${clang_triple}${api_level}-clang'
cpp = '${toolchain_dir}/bin/${clang_triple}${api_level}-clang++'
ar = '${toolchain_dir}/bin/llvm-ar'
strip = '${toolchain_dir}/bin/llvm-strip'
objcopy = '${toolchain_dir}/bin/llvm-objcopy'
pkg-config = 'pkg-config'

[host_machine]
system = 'android'
cpu_family = '${cpu_family}'
cpu = '${cpu}'
endian = 'little'

[built-in options]
c_std = 'c11'
cpp_std = 'c++11'
default_library = 'shared'

[properties]
needs_exe_wrapper = true
EOF

    printf '%s\n' "$cross_file"
    return 0
}

# 设置交叉编译
setup_cross_compile() {
    local target_name="$1"
    local cross_prefix_input="$2"
    local cross_prefix
    cross_prefix=$(normalize_cross_prefix "$cross_prefix_input")

    if [ -z "$cross_prefix" ]; then
        log_warning "未提供有效的交叉编译前缀"
        return 1
    fi

    local c_compiler
    c_compiler=$(find_cross_tool_in_path "$cross_prefix" "gcc")
    if [ -z "$c_compiler" ]; then
        log_warning "未找到 ${cross_prefix}gcc"
        return 1
    fi

    local cxx_compiler
    cxx_compiler=$(find_cross_tool_in_path "$cross_prefix" "g++")
    if [ -z "$cxx_compiler" ]; then
        log_warning "未找到 ${cross_prefix}g++"
        return 1
    fi

    local ar_tool
    ar_tool=$(find_cross_tool_in_path "$cross_prefix" "ar")
    if [ -z "$ar_tool" ]; then
        log_warning "未找到 ${cross_prefix}ar"
        return 1
    fi

    local strip_tool
    strip_tool=$(find_cross_tool_in_path "$cross_prefix" "strip")
    if [ -z "$strip_tool" ]; then
        strip_tool=$(command -v strip 2>/dev/null || true)
    fi
    [ -z "$strip_tool" ] && strip_tool="strip"

    local objcopy_tool
    objcopy_tool=$(find_cross_tool_in_path "$cross_prefix" "objcopy")
    if [ -z "$objcopy_tool" ]; then
        objcopy_tool=$(command -v objcopy 2>/dev/null || true)
    fi
    [ -z "$objcopy_tool" ] && objcopy_tool="objcopy"

    local system="linux"
    local cpu_family=""
    local cpu=""

    case "$target_name" in
        arm-linux-gnueabihf|arm-linux-musleabihf)
            cpu_family="arm"
            cpu="armv7"
            ;;
        aarch64-linux-gnu|aarch64-linux-musl)
            cpu_family="aarch64"
            cpu="aarch64"
            ;;
        riscv64-linux-gnu|riscv64-linux-musl)
            cpu_family="riscv64"
            cpu="riscv64"
            ;;
        x86_64-linux-gnu)
            cpu_family="x86_64"
            cpu="x86_64"
            ;;
        x86_64-windows-gnu)
            system="windows"
            cpu_family="x86_64"
            cpu="x86_64"
            ;;
        x86_64-macos)
            system="darwin"
            cpu_family="x86_64"
            cpu="x86_64"
            ;;
        aarch64-macos)
            system="darwin"
            cpu_family="aarch64"
            cpu="aarch64"
            ;;
        *)
            cpu_family="aarch64"
            cpu="aarch64"
            ;;
    esac

    local cross_file="${SCRIPT_DIR}/cross-${target_name}.txt"
    cat > "$cross_file" << EOF
[binaries]
c = '${c_compiler}'
cpp = '${cxx_compiler}'
ar = '${ar_tool}'
strip = '${strip_tool}'
objcopy = '${objcopy_tool}'
pkg-config = 'pkg-config'

[host_machine]
system = '${system}'
cpu_family = '${cpu_family}'
cpu = '${cpu}'
endian = 'little'

[built-in options]
c_std = 'c11'
cpp_std = 'c++11'
default_library = 'shared'

[properties]
needs_exe_wrapper = true
EOF

    printf '%s\n' "$cross_file"
    return 0
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

# 构建指定目标
build_target() {
    local target_name="$1"

    local config
    config=$(get_target_config "$target_name")
    if [ -z "$config" ]; then
        log_error "Invalid target: $target_name"
        return 1
    fi

    local cfg_target cfg_output_dir cfg_libdrm_dir cfg_cross_prefix cfg_expected_arch
    IFS=':' read -r cfg_target cfg_output_dir cfg_libdrm_dir cfg_cross_prefix cfg_expected_arch <<< "$config"

    local output_dir
    output_dir=$(get_output_dir_for_build_type "$cfg_output_dir")
    if [ -z "$output_dir" ]; then
        log_error "无法解析输出目录"
        return 1
    fi
    mkdir -p "$output_dir"

    local libdrm_dir
    if ! libdrm_dir=$(check_and_build_libdrm_dependency "$target_name"); then
        return 1
    fi

    local libdrm_pkg_dir="${libdrm_dir}/lib/pkgconfig"

    local build_dir="${LIBRGA_SOURCE_DIR}/build_${target_name}"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    local cross_file=""
    local cross_prefix_normalized=""

    if [[ "$target_name" == *"-android" ]]; then
        if ! cross_file=$(setup_android_cross_compile "$target_name"); then
            return 1
        fi
        cross_prefix_normalized=$(normalize_cross_prefix "$cfg_cross_prefix")
    elif [ -n "$cfg_cross_prefix" ]; then
        if cross_file=$(setup_cross_compile "$target_name" "$cfg_cross_prefix"); then
            cross_prefix_normalized=$(normalize_cross_prefix "$cfg_cross_prefix")
        else
            log_warning "未找到 ${cfg_cross_prefix} 交叉编译工具，使用本机工具链"
            cross_file=""
            cross_prefix_normalized=""
        fi
    fi

    local meson_args=(
        "--prefix" "$output_dir"
        "--buildtype=$BUILD_TYPE_LOWER"
        "--default-library=shared"
        "--libdir=lib"
        "-Dcpp_args=-fpermissive"
        "-Dlibdrm=true"
        "-Dlibrga_demo=false"
    )

    if [ -n "$cross_file" ] && [ -f "$cross_file" ]; then
        meson_args+=("--cross-file=$cross_file")
        log_info "使用 cross file: $cross_file"
    fi

    local old_pkg_config_path="${PKG_CONFIG_PATH:-}"
    export PKG_CONFIG_PATH="${libdrm_pkg_dir}${old_pkg_config_path:+:$old_pkg_config_path}"

    log_info "Meson 配置中..."
    if ! meson setup "$build_dir" "$LIBRGA_SOURCE_DIR" "${meson_args[@]}"; then
        export PKG_CONFIG_PATH="$old_pkg_config_path"
        log_error "Meson 配置失败"
        return 1
    fi

    log_info "使用 ninja 构建..."
    if ! ninja -C "$build_dir"; then
        export PKG_CONFIG_PATH="$old_pkg_config_path"
        log_error "构建失败"
        return 1
    fi

    log_info "安装到 $output_dir ..."
    if ! ninja -C "$build_dir" install; then
        export PKG_CONFIG_PATH="$old_pkg_config_path"
        log_error "安装失败"
        return 1
    fi

    export PKG_CONFIG_PATH="$old_pkg_config_path"

    log_success "$target_name build completed"

    local available_tools=""
    available_tools=$(check_cross_compile_tools "$cross_prefix_normalized" "$target_name" "$build_dir")

    if [ "$BUILD_TYPE_LOWER" = "release" ]; then
        compress_artifacts_in_dir \
            "$output_dir" \
            "$target_name" \
            "$available_tools" \
            --locale zh \
            --allow-upx \
            --summary-label "${target_name} 压缩统计:"
    else
        log_info "Debug 构建类型，跳过库压缩"
    fi

    validate_build_architecture "$output_dir" "$target_name"

    COMPLETED_OUTPUT_DIRS+=("$output_dir")
    return 0
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
    
    reset_build_type_state
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
    
    ensure_tools_available git meson ninja pkg-config
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
        local script_name
        script_name="$(basename "$0")"

        cat <<EOF
RK RGA Build Script (Meson)

Usage: ./${script_name} [OPTIONS] [TARGET]

Options:
    --build_type {Debug|Release}  Set build type (default: Release)
    -h, --help                    Show this help message

TARGET (optional):
    aarch64-linux-gnu      Build ARM 64-bit glibc version
    arm-linux-gnueabihf    Build ARM 32-bit glibc version
    aarch64-linux-musl     Build ARM 64-bit musl version
    arm-linux-musleabihf   Build ARM 32-bit musl version
    riscv64-linux-gnu      Build RISC-V 64-bit glibc version
    riscv64-linux-musl     Build RISC-V 64-bit musl version
    aarch64-linux-android  Build Android ARM 64-bit version
    arm-linux-android      Build Android ARM 32-bit version
    x86_64-linux-gnu       Build x86_64 Linux version
    x86_64-windows-gnu     Build x86_64 Windows version
    x86_64-macos           Build x86_64 macOS version
    aarch64-macos          Build ARM 64-bit macOS version

Examples:
    ./${script_name}                                # Build default targets (${_DEFAULT_BUILD_TARGETS})
    ./${script_name} aarch64-linux-gnu              # Build ARM 64-bit GNU libc version
    ./${script_name} --build_type Debug aarch64-linux-gnu  # Debug build with -debug suffix
    ./${script_name} aarch64-linux-android          # Build Android ARM 64-bit version
    ./${script_name} --clean                        # Clean build artifacts

Environment Variables:
    ANDROID_NDK_HOME      Path to Android NDK (default: ~/sdk/android_ndk/android-ndk-r25c)
EOF
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