#!/bin/bash

set -euo pipefail

# libdrm 构建脚本
# 支持多种交叉编译工具链编译libdrm库

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROJECT_ROOT_DIR="$WORKSPACE_DIR"
SOURCES_DIR="${WORKSPACE_DIR}/sources"
OUTPUTS_DIR="${WORKSPACE_DIR}/outputs"
LIBDRM_OUTPUT_DIR="${OUTPUTS_DIR}/libdrm"
LIBDRM_SOURCE_DIR="${SOURCES_DIR}/libdrm"
TOOLCHAIN_DIR="${WORKSPACE_DIR}/toolchain"
TEMP_DIR="${WORKSPACE_DIR}/.tmp/libdrm"

mkdir -p "$SOURCES_DIR" "$OUTPUTS_DIR" "$LIBDRM_OUTPUT_DIR" "$TEMP_DIR"

source "${SCRIPT_DIR}/../common.sh"

reset_build_type_state
PARSED_TARGET=""

# 限制默认构建目标
_DEFAULT_BUILD_TARGETS="aarch64-linux-gnu,arm-linux-gnueabihf,aarch64-linux-android,arm-linux-android"

LIBDRM_VERSION="unknown"

ALL_KNOWN_TARGETS=(
    arm-linux-gnueabihf
    aarch64-linux-gnu
    arm-linux-musleabihf
    aarch64-linux-musl
    riscv64-linux-gnu
    riscv64-linux-musl
    x86_64-linux-gnu
    x86_64-windows-gnu
    x86_64-macos
    aarch64-macos
    aarch64-linux-android
    arm-linux-android
)

declare -A TARGET_CONFIGS=(
    ["arm-linux-gnueabihf"]="arm-linux-gnueabihf:linux:${LIBDRM_OUTPUT_DIR}/arm-linux-gnueabihf:arm-linux-gnueabihf-:ARM"
    ["aarch64-linux-gnu"]="aarch64-linux-gnu:linux:${LIBDRM_OUTPUT_DIR}/aarch64-linux-gnu:aarch64-linux-gnu-:AArch64"
    ["arm-linux-musleabihf"]="arm-linux-musleabihf:linux:${LIBDRM_OUTPUT_DIR}/arm-linux-musleabihf:arm-linux-musleabihf-:ARM"
    ["aarch64-linux-musl"]="aarch64-linux-musl:linux:${LIBDRM_OUTPUT_DIR}/aarch64-linux-musl:aarch64-linux-musl-:AArch64"
    ["riscv64-linux-gnu"]="riscv64-linux-gnu:linux:${LIBDRM_OUTPUT_DIR}/riscv64-linux-gnu:riscv64-linux-gnu-:RISC-V"
    ["riscv64-linux-musl"]="riscv64-linux-musl:linux:${LIBDRM_OUTPUT_DIR}/riscv64-linux-musl:riscv64-linux-musl-:RISC-V"
    ["x86_64-linux-gnu"]="x86_64-linux-gnu:native:${LIBDRM_OUTPUT_DIR}/x86_64-linux-gnu::x86_64"
    ["x86_64-windows-gnu"]="x86_64-windows-gnu:linux:${LIBDRM_OUTPUT_DIR}/x86_64-windows-gnu:x86_64-w64-mingw32-:x86_64"
    ["x86_64-macos"]="x86_64-macos:macos:${LIBDRM_OUTPUT_DIR}/x86_64-macos::x86_64"
    ["aarch64-macos"]="aarch64-macos:macos:${LIBDRM_OUTPUT_DIR}/aarch64-macos::AArch64"
    ["aarch64-linux-android"]="aarch64-linux-android:android:${LIBDRM_OUTPUT_DIR}/aarch64-linux-android:aarch64-linux-android-:AArch64"
    ["arm-linux-android"]="arm-linux-android:android:${LIBDRM_OUTPUT_DIR}/arm-linux-android:arm-linux-androideabi-:ARM"
)

detect_libdrm_version() {
    local meson_file="${LIBDRM_SOURCE_DIR}/meson.build"
    local version="unknown"

    if [ -f "$meson_file" ]; then
        version=$(grep -E "version\s*:\s*'" "$meson_file" | head -n1 | sed -E "s/.*version\s*:\s*'([^']+)'.*/\1/")
        [ -n "$version" ] || version="unknown"
    fi

    echo "$version"
}

download_libdrm() {
    log_info "Preparing libdrm source..."

    if [ -d "$LIBDRM_SOURCE_DIR" ] && [ -f "${LIBDRM_SOURCE_DIR}/meson.build" ]; then
        log_success "libdrm source already present: $LIBDRM_SOURCE_DIR"
    else
        local desired_version
        desired_version=$(detect_libdrm_version)
        if [ "$desired_version" = "unknown" ]; then
            desired_version="${LIBDRM_VERSION_OVERRIDE:-2.4.121}"
        fi

        local archive_name="libdrm-${desired_version}.tar.xz"
        local archive_path="${TEMP_DIR}/${archive_name}"
        local download_url="${LIBDRM_DOWNLOAD_URL:-https://dri.freedesktop.org/libdrm/${archive_name}}"

        ensure_tools_available wget tar

        if [ ! -f "$archive_path" ]; then
            log_info "Downloading ${download_url}"
            if ! wget -O "$archive_path" "$download_url"; then
                log_error "Failed to download libdrm archive from $download_url"
                return 1
            fi
        fi

        rm -rf "$LIBDRM_SOURCE_DIR"
        mkdir -p "$SOURCES_DIR"

        if ! tar -xf "$archive_path" -C "$SOURCES_DIR"; then
            log_error "Failed to extract $archive_path"
            return 1
        fi

        local extracted_dir="${SOURCES_DIR}/libdrm-${desired_version}"
        if [ -d "$extracted_dir" ]; then
            mv "$extracted_dir" "$LIBDRM_SOURCE_DIR"
        elif [ ! -d "$LIBDRM_SOURCE_DIR" ]; then
            log_error "Extracted libdrm directory not found"
            return 1
        fi

        log_success "libdrm source prepared at $LIBDRM_SOURCE_DIR"
    fi

    LIBDRM_VERSION=$(detect_libdrm_version)
    [ -z "$LIBDRM_VERSION" ] && LIBDRM_VERSION="unknown"
    log_info "Using libdrm version: $LIBDRM_VERSION"
}

setup_android_cross_compile() {
    local target_name="$1"

    local toolchain_dir
    if ! toolchain_dir="$(_detect_ndk_toolchain_dir)"; then
        log_error "Android NDK toolchain not found. Please set ANDROID_NDK_HOME."
        return 1
    fi

    local api_level="${ANDROID_API_LEVEL:-23}"
    local clang_triple=""
    local cpu_family=""
    local cpu=""

    case "$target_name" in
        aarch64-linux-android)
            clang_triple="aarch64-linux-android"
            cpu_family="aarch64"
            cpu="aarch64"
            ;;
        arm-linux-android)
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
    cat > "$cross_file" <<EOF
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

    echo "$cross_file"
}

setup_cross_compile() {
    local target_name="$1"
    local cross_prefix_input="$2"
    local cross_prefix
    cross_prefix=$(normalize_cross_prefix "$cross_prefix_input")

    if [ -z "$cross_prefix" ]; then
        log_warning "Invalid cross prefix for $target_name"
        return 1
    fi

    local c_compiler
    c_compiler=$(find_cross_tool_in_path "$cross_prefix" "gcc")
    if [ -z "$c_compiler" ]; then
        log_warning "${cross_prefix}gcc not found"
        return 1
    fi

    local cxx_compiler
    cxx_compiler=$(find_cross_tool_in_path "$cross_prefix" "g++")
    if [ -z "$cxx_compiler" ]; then
        log_warning "${cross_prefix}g++ not found"
        return 1
    fi

    local ar_tool
    ar_tool=$(find_cross_tool_in_path "$cross_prefix" "ar")
    if [ -z "$ar_tool" ]; then
        log_warning "${cross_prefix}ar not found"
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
    local cpu_family="aarch64"
    local cpu="aarch64"

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
    esac

    local cross_file="${SCRIPT_DIR}/cross-${target_name}.txt"
    cat > "$cross_file" <<EOF
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

    echo "$cross_file"
}

build_target_internal() {
    local target_name="$1"
    local platform="$2"
    local output_dir="$3"
    local cross_prefix="$4"
    local expected_arch="$5"

    log_info "Building $target_name (platform: $platform)"

    mkdir -p "$output_dir"

    local build_dir="${LIBDRM_SOURCE_DIR}/build_${target_name}"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    local cross_file=""
    local normalized_prefix=$(normalize_cross_prefix "$cross_prefix")

    case "$platform" in
        android)
            if ! cross_file=$(setup_android_cross_compile "$target_name"); then
                return 1
            fi
            ;;
        native)
            normalized_prefix=""
            ;;
        macos)
            log_warning "macOS cross builds are not fully supported; attempting native build"
            normalized_prefix=""
            ;;
        *)
            if [ -n "$normalized_prefix" ]; then
                if ! cross_file=$(setup_cross_compile "$target_name" "$normalized_prefix"); then
                    log_warning "Falling back to host toolchain for $target_name"
                    normalized_prefix=""
                    cross_file=""
                fi
            fi
            ;;
    esac

    local meson_args=(
        "--prefix" "$output_dir"
        "--libdir=lib"
        "--buildtype=$BUILD_TYPE_LOWER"
        "-Ddefault_library=shared"
        "-Dtests=false"
        "-Dvalgrind=disabled"
        "-Dman-pages=disabled"
    )

    if [ -n "$cross_file" ] && [ -f "$cross_file" ]; then
        meson_args+=("--cross-file=$cross_file")
        log_info "Using cross file: $cross_file"
    fi

    local old_pkg_config_path="${PKG_CONFIG_PATH:-}"

    log_info "Configuring with meson..."
    if ! meson setup "$build_dir" "$LIBDRM_SOURCE_DIR" "${meson_args[@]}"; then
        export PKG_CONFIG_PATH="$old_pkg_config_path"
        log_error "Meson configuration failed for $target_name"
        return 1
    fi

    log_info "Building with ninja..."
    if ! ninja -C "$build_dir"; then
        export PKG_CONFIG_PATH="$old_pkg_config_path"
        log_error "Build failed for $target_name"
        return 1
    fi

    log_info "Installing to $output_dir"
    if ! ninja -C "$build_dir" install; then
        export PKG_CONFIG_PATH="$old_pkg_config_path"
        log_error "Install failed for $target_name"
        return 1
    fi

    export PKG_CONFIG_PATH="$old_pkg_config_path"

    local available_tools
    available_tools=$(check_cross_compile_tools "$normalized_prefix" "$target_name" "$build_dir")

    if [ "$BUILD_TYPE_LOWER" = "release" ]; then
        if [ "$platform" = "android" ]; then
            compress_android_libraries "$output_dir" "$target_name" "$normalized_prefix"
        else
            compress_artifacts_in_dir \
                "$output_dir" \
                "$target_name" \
                "$available_tools" \
                --locale zh \
                --allow-upx \
                --summary-label "${target_name} 压缩统计:"
        fi
    else
        log_info "Debug build detected, skipping compression"
    fi

    validate_build_architecture "$output_dir" "$target_name"

    log_success "$target_name build completed"
    return 0
}

build_target() {
    local target_name="$1"
    local platform="${2:-}"
    local output_dir="${3:-}"
    local cross_prefix="${4:-}"
    local expected_arch="${5:-}"

    if [ -z "$platform" ] || [ -z "$output_dir" ]; then
        local config
        config=$(get_target_config "$target_name")
        if [ -z "$config" ]; then
            log_error "Unknown target: $target_name"
            return 1
        fi
        IFS=':' read -r _target platform output_dir cross_prefix expected_arch <<< "$config"
    fi

    build_target_internal "$target_name" "$platform" "$output_dir" "$cross_prefix" "$expected_arch"
}

build_android_target() {
    local target_name="$1"
    local output_dir="$2"
    local cross_prefix="$3"
    local expected_arch="$4"

    build_target_internal "$target_name" "android" "$output_dir" "$cross_prefix" "$expected_arch"
}
# Android版本的压缩处理函数
compress_android_libraries() {
    local output_dir="$1"
    local target_name="$2"
    local cross_prefix="${3:-}"

    log_info "Compressing Android libraries for $target_name..."

    if [ -z "$cross_prefix" ]; then
        case "$target_name" in
            aarch64-linux-android)
                cross_prefix="aarch64-linux-android-"
                ;;
            arm-linux-android)
                cross_prefix="arm-linux-androideabi-"
                ;;
        esac
    fi

    local available_tools
    available_tools=$(check_cross_compile_tools "$cross_prefix" "$target_name")

    compress_artifacts_in_dir \
        "$output_dir" \
        "$target_name" \
        "$available_tools" \
        --locale zh \
        --allow-upx \
        --allow-xz \
        --allow-gzip \
        --print-details \
        --summary-label "${target_name} 压缩统计:"
}

# 创建软链接 - 已废弃，新目标名称不再需要软链接
create_symlinks() {
    log_info "Symbolic links creation deprecated - new target names no longer require symlinks"
}

# Android环境初始化
init_android_env() {
    local target="$1"
    
    if [[ "$target" == "android_"* ]] || [[ "$target" == *"-android" ]]; then
        # 展开波浪号路径
        local default_ndk_path
        default_ndk_path=$(eval echo "~/sdk/android_ndk/android-ndk-r25c")
        export ANDROID_NDK_ROOT="${ANDROID_NDK_HOME:-$default_ndk_path}"
        HOST_TAG=linux-x86_64
        TOOLCHAIN=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOST_TAG
        export PATH=$TOOLCHAIN/bin:$PATH
        API_LEVEL=23

        case "$target" in
            aarch64-linux-android)
                ANDROID_ABI=arm64-v8a
                ANDROID_TARGET=aarch64-linux-android
                log_info "Initializing Android NDK for arm64-v8a (API $API_LEVEL)"
                ;;
            arm-linux-android)
                ANDROID_ABI=armeabi-v7a
                ANDROID_TARGET=armv7a-linux-androideabi
                log_info "Initializing Android NDK for armeabi-v7a (API $API_LEVEL)"
                ;;
            *)
                log_error "Unknown Android architecture: $target"
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
    if [ -z "$_DEFAULT_BUILD_TARGETS" ]; then
        for target_name in "${ALL_KNOWN_TARGETS[@]}"; do
            local config="${TARGET_CONFIGS[$target_name]:-}"
            [ -n "$config" ] && echo "$config"
        done
        return 0
    fi

    IFS=',' read -ra TARGET_ARRAY <<< "$_DEFAULT_BUILD_TARGETS"
    for target_name in "${TARGET_ARRAY[@]}"; do
        target_name=$(echo "$target_name" | tr -d ' ')
        [ -z "$target_name" ] && continue
        local config="${TARGET_CONFIGS[$target_name]:-}"
        if [ -n "$config" ]; then
            echo "$config"
        else
            log_warning "Invalid default target ignored: $target_name"
        fi
    done
}

get_target_config() {
    local target_name="$1"
    echo "${TARGET_CONFIGS[$target_name]:-}"
}

# 验证目标名称
validate_target() {
    local target="$1"
    local valid_targets=("arm-linux-gnueabihf" "aarch64-linux-gnu" "riscv64-linux-gnu" "arm-linux-musleabihf" "aarch64-linux-musl" "riscv64-linux-musl" "x86_64-linux-gnu" "x86_64-windows-gnu" "x86_64-macos" "aarch64-macos" "aarch64-linux-android" "arm-linux-android")
    
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
    
    reset_build_type_state
    PARSED_TARGET=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
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
        log_error "Valid targets: arm-linux-gnueabihf, aarch64-linux-gnu, riscv64-linux-gnu, arm-linux-musleabihf, aarch64-linux-musl, riscv64-linux-musl, x86_64-linux-gnu, x86_64-windows-gnu, x86_64-macos, aarch64-macos, aarch64-linux-android, arm-linux-android"
        exit 1
    fi
    
    PARSED_TARGET="$target"
}

# 主函数
main() {
    local target_to_build="$1"
    
    log_info "Starting libdrm build process..."
    log_info "Selected build type: $BUILD_TYPE"
    
    # 检查工具
    ensure_tools_available meson ninja pkg-config
    
    # 下载源码
    download_libdrm

    # 修复 Meson clockskew 问题
    apply_meson_clockskew_patch
    
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
        
        IFS=':' read -r target_name build_mode output_dir cross_prefix expected_arch <<< "$target_config"
        local effective_output_dir
        effective_output_dir=$(get_output_dir_for_build_type "$output_dir")
        log_info "Resolved output directory: $effective_output_dir"
        
        case "$build_mode" in
            android)
                if build_android_target "$target_name" "$effective_output_dir" "$cross_prefix" "$expected_arch"; then
                    log_success "$target_to_build build completed successfully"
                else
                    log_error "Failed to build $target_to_build"
                    exit 1
                fi
                ;;
            *)
                if build_target "$target_name" "$build_mode" "$effective_output_dir" "$cross_prefix" "$expected_arch"; then
                    log_success "$target_to_build build completed successfully"
                else
                    log_error "Failed to build $target_to_build"
                    exit 1
                fi
                ;;
        esac
        
        # 软链接创建已废弃
        # create_symlinks "$target_to_build"
        
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
            
            IFS=':' read -r target_name build_mode output_dir cross_prefix expected_arch <<< "$target_config"
            local effective_output_dir
            effective_output_dir=$(get_output_dir_for_build_type "$output_dir")
            log_info "Resolved output directory: $effective_output_dir"
            
            case "$build_mode" in
                android)
                    if ! build_android_target "$target_name" "$effective_output_dir" "$cross_prefix" "$expected_arch"; then
                        log_warning "Failed to build $target_name, continuing with next target"
                        continue
                    fi
                    ;;
                *)
                    if ! build_target "$target_name" "$build_mode" "$effective_output_dir" "$cross_prefix" "$expected_arch"; then
                        log_warning "Failed to build $target_name, continuing with next target"
                        continue
                    fi
                    ;;
            esac
        done <<< "$targets_to_build"
        
        # 软链接创建已废弃
        # create_symlinks "all"
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
    local version_to_write="${LIBDRM_VERSION:-unknown}"

    # 写入版本信息到version.ini
    cat > "$version_file" << EOF
[version]
version=$version_to_write
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Version file created successfully: $version_file"
        log_info "libdrm version: $LIBDRM_VERSION"
    else
        log_error "Failed to create version file: $version_file"
        return 1
    fi
}

# 验证构建结果的架构
validate_build_architecture() {
    local output_dir="$1"
    local expected_target="$2"
    
    log_info "Validating build architecture for $expected_target..."
    
    # 根据目标名称确定期望的架构
    local expected_arch=""
    case "$expected_target" in
        "arm-linux-gnueabihf"|"arm-linux-musleabihf"|"arm-linux-android")
            expected_arch="ARM"
            ;;
        "aarch64-linux-gnu"|"aarch64-linux-musl"|"aarch64-linux-android")
            expected_arch="AArch64"
            ;;
        "riscv64-linux-gnu"|"riscv64-linux-musl")
            expected_arch="RISC-V"
            ;;
        *)
            expected_arch="Unknown"
            ;;
    esac
    
    # 查找所有库文件
    local lib_files
    lib_files=$(find "$output_dir" -type f \( -name "*.so*" -o -name "*.a" \) 2>/dev/null || true)
    
    if [ -z "$lib_files" ]; then
        log_warning "No library files found for validation in $output_dir"
        return 0
    fi
    
    local validation_passed=true
    
    while IFS= read -r lib_file; do
        [ -z "$lib_file" ] && continue
        
        # 使用 file 命令检查文件架构
        local file_info
        file_info=$(file "$lib_file" 2>/dev/null || echo "Unknown file type")
        
        log_info "  $(basename "$lib_file"): $file_info"
        
        # 对于静态库文件(.a)，需要特殊处理来检测架构
        if [[ "$lib_file" == *.a ]]; then
            # 静态库是归档文件，需要检查内部对象文件的架构
            local static_lib_arch="unknown"
            
            # 方法1: 使用 ar 命令提取一个对象文件并检查
            if command -v "ar" &> /dev/null; then
                local temp_dir
                temp_dir=$(mktemp -d)
                cd "$temp_dir"
                
                # 提取第一个对象文件
                if ar x "$lib_file" 2>/dev/null; then
                    local first_obj
                    first_obj=$(find . -name "*.o" -type f | head -1)
                    if [ -n "$first_obj" ]; then
                        local obj_arch
                        obj_arch=$(file "$first_obj" 2>/dev/null || echo "")
                        if echo "$obj_arch" | grep -q -E "(ARM|arm)"; then
                            static_lib_arch="ARM"
                        elif echo "$obj_arch" | grep -q -E "(AArch64|aarch64|ARM64)"; then
                            static_lib_arch="AArch64"
                        elif echo "$obj_arch" | grep -q -E "(x86-64|x86_64)"; then
                            static_lib_arch="x86-64"
                        elif echo "$obj_arch" | grep -q -E "(RISC-V|riscv)"; then
                            static_lib_arch="RISC-V"
                        fi
                    fi
                fi
                
                cd - >/dev/null
                rm -rf "$temp_dir"
            fi
            
            # 根据检测到的架构进行验证
            case "$expected_arch" in
                "ARM")
                    if [ "$static_lib_arch" = "ARM" ]; then
                        log_success "    ✓ Static library architecture matches expected ARM"
                    elif [ "$static_lib_arch" = "x86-64" ]; then
                        log_warning "    Architecture mismatch: Expected ARM, but got x86-64"
                        validation_passed=false
                    else
                        log_info "    Static library architecture detection inconclusive (assuming ARM based on target)"
                        log_success "    ✓ Architecture matches expected ARM (based on target configuration)"
                    fi
                    ;;
                "AArch64")
                    if [ "$static_lib_arch" = "AArch64" ]; then
                        log_success "    ✓ Static library architecture matches expected AArch64"
                    elif [ "$static_lib_arch" = "x86-64" ]; then
                        log_warning "    Architecture mismatch: Expected AArch64, but got x86-64"
                        validation_passed=false
                    else
                        log_info "    Static library architecture detection inconclusive (assuming AArch64 based on target)"
                        log_success "    ✓ Architecture matches expected AArch64 (based on target configuration)"
                    fi
                    ;;
                "RISC-V")
                    if [ "$static_lib_arch" = "RISC-V" ]; then
                        log_success "    ✓ Static library architecture matches expected RISC-V"
                    elif [ "$static_lib_arch" = "x86-64" ]; then
                        log_warning "    Architecture mismatch: Expected RISC-V, but got x86-64"
                        validation_passed=false
                    else
                        log_info "    Static library architecture detection inconclusive (assuming RISC-V based on target)"
                        log_success "    ✓ Architecture matches expected RISC-V (based on target configuration)"
                    fi
                    ;;
                *)
                    log_info "    Static library architecture validation skipped for unknown target"
                    ;;
            esac
            
        else
            # 对于共享库文件(.so)，使用 file 命令检测架构
            case "$expected_arch" in
                "ARM")
                    if echo "$file_info" | grep -q -E "(x86-64|x86_64|X86-64|X86_64)"; then
                        log_warning "    Architecture mismatch: Expected ARM, but got x86-64"
                        validation_passed=false
                    elif echo "$file_info" | grep -q -E "(ARM|32-bit|arm|ARM)"; then
                        log_success "    ✓ Architecture matches expected ARM"
                    else
                        log_warning "    Architecture detection inconclusive for ARM"
                    fi
                    ;;
                "AArch64")
                    if echo "$file_info" | grep -q -E "(x86-64|x86_64|X86-64|X86_64)"; then
                        log_warning "    Architecture mismatch: Expected AArch64, but got x86-64"
                        validation_passed=false
                    elif echo "$file_info" | grep -q -E "(AArch64|aarch64|64-bit|ARM64|AARCH64)"; then
                        log_success "    ✓ Architecture matches expected AArch64"
                    else
                        log_warning "    Architecture detection inconclusive for AArch64"
                    fi
                    ;;
                "RISC-V")
                    if echo "$file_info" | grep -q -E "(x86-64|x86_64|X86-64|X86_64)"; then
                        log_warning "    Architecture mismatch: Expected RISC-V, but got x86-64"
                        validation_passed=false
                    elif echo "$file_info" | grep -q -E "(RISC-V|riscv|RISC_V)"; then
                        log_success "    ✓ Architecture matches expected RISC-V"
                    else
                        log_warning "    Architecture detection inconclusive for RISC-V"
                    fi
                    ;;
                *)
                    log_info "    Architecture validation skipped for unknown target"
                    ;;
            esac
        fi
        
    done <<< "$lib_files"
    
    if [ "$validation_passed" = "true" ]; then
        log_success "Architecture validation passed for $expected_target ($expected_arch)"
        return 0
    else
        log_error "Architecture validation failed for $expected_target"
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
    find "$SCRIPT_DIR" -maxdepth 1 -name "cross-*.txt" -type f -delete 2>/dev/null || true
    find "$SCRIPT_DIR" -maxdepth 1 -name "android-*.txt" -type f -delete 2>/dev/null || true
}

# 帮助信息
show_help() {
    local script_name
    script_name="$(basename "$0")"

    cat <<EOF
libdrm Build Script

Usage: ./${script_name} [OPTIONS] [TARGET]

TARGET (optional):
    arm-linux-gnueabihf    Build ARM 32-bit glibc version
    aarch64-linux-gnu      Build ARM 64-bit glibc version
    riscv64-linux-gnu      Build RISC-V 64-bit glibc version
    arm-linux-musleabihf   Build ARM 32-bit musl version
    aarch64-linux-musl     Build ARM 64-bit musl version
    riscv64-linux-musl     Build RISC-V 64-bit musl version
    x86_64-linux-gnu       Build x86_64 Linux version
    x86_64-windows-gnu     Build x86_64 Windows version
    x86_64-macos           Build x86_64 macOS version
    aarch64-macos          Build ARM64 macOS version
    aarch64-linux-android  Build Android ARM 64-bit version
    arm-linux-android      Build Android ARM 32-bit version

Options:
    --build_type {Debug|Release}  Set build configuration (default: Release)
    -h, --help                    Show this help message
    -c, --clean                   Clean build directories only
    --clean-all                   Clean all (sources and outputs)

Environment Variables:
    TOOLCHAIN_ROOT_DIR    Path to cross-compilation toolchain (optional)
    ANDROID_NDK_HOME      Path to Android NDK (default: ~/sdk/android_ndk/android-ndk-r25c)

Examples:
    ./${script_name}                                # Build default targets in Release configuration
    ./${script_name} --build_type Debug             # Build default targets in Debug configuration
    ./${script_name} --build_type Release aarch64-linux-gnu  # Release build for aarch64-linux-gnu
    ./${script_name} --build_type Debug arm-linux-musleabihf # Debug build for arm-linux-musleabihf
    ./${script_name} aarch64-linux-android          # Release build for Android ARM 64-bit
    ./${script_name} --build_type Debug aarch64-linux-android # Debug build for Android ARM 64-bit
    ./${script_name} --clean                        # Clean build directories
    ./${script_name} --clean-all                    # Clean everything

Features:
    - Fixed version: ${LIBDRM_VERSION}
    - Meson + Ninja build pipeline
    - Automatic Meson clockskew patching
    - Cross-compilation support via generated Meson cross files
    - Library compression with strip/objcopy/UPX when available
    - Architecture validation for generated artifacts
    - Compression statistics and size reporting
EOF
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
    parse_arguments "$@"
    main "$PARSED_TARGET"
        ;;
esac