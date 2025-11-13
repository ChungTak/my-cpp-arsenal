#!/bin/bash

# OpenSSL 构建脚本
# 支持多种交叉编译工具链编译 OpenSSL 库

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLCHAIN_DIR="${WORKSPACE_DIR}/toolchain"
SOURCES_DIR="${WORKSPACE_DIR}/sources"
OUTPUTS_DIR="${WORKSPACE_DIR}/outputs"
OPENSSL_OUTPUT_DIR="${OUTPUTS_DIR}/openssl"
OPENSSL_SOURCE_DIR="${SOURCES_DIR}/openssl"

# 默认构建类型配置
source "${SCRIPT_DIR}/../common.sh"

reset_build_type_state
PARSED_TARGET=""

# 限制默认编译目标
_DEFAULT_BUILD_TARGETS="aarch64-linux-gnu,arm-linux-gnueabihf,aarch64-linux-android,arm-linux-android,x86_64-linux-gnu"

# OpenSSL 版本号（默认3.5.4）
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.4}"
OPENSSL_DOWNLOAD_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"

# 错误处理辅助
check_command_result() {
    local exit_code="$1"
    local message="$2"

    if [ "$exit_code" -ne 0 ]; then
        log_error "$message"
        exit "$exit_code"
    fi
}

# 下载并解压 OpenSSL 源码
download_openssl() {
    log_info "Checking OpenSSL source..."

    mkdir -p "${SOURCES_DIR}"

    if [ -d "${OPENSSL_SOURCE_DIR}" ] && [ -f "${OPENSSL_SOURCE_DIR}/Configure" ]; then
        log_success "OpenSSL source already exists, skipping download"
        return 0
    fi

    if [ -d "${OPENSSL_SOURCE_DIR}" ]; then
        log_warning "Removing incomplete OpenSSL directory"
        rm -rf "${OPENSSL_SOURCE_DIR}"
    fi

    local temp_dir="${SOURCES_DIR}/temp_openssl"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    cd "$temp_dir"

    log_info "Downloading OpenSSL ${OPENSSL_VERSION}..."
    if wget -O "openssl-${OPENSSL_VERSION}.tar.gz" "$OPENSSL_DOWNLOAD_URL"; then
        log_success "OpenSSL downloaded successfully"
    else
        log_error "Failed to download OpenSSL from $OPENSSL_DOWNLOAD_URL"
        exit 1
    fi

    log_info "Extracting OpenSSL source..."
    if tar -xzf "openssl-${OPENSSL_VERSION}.tar.gz"; then
        log_success "OpenSSL extracted successfully"
        mv "openssl-${OPENSSL_VERSION}" "${OPENSSL_SOURCE_DIR}"
        cd "${WORKSPACE_DIR}"
        rm -rf "$temp_dir"
    else
        log_error "Failed to extract OpenSSL"
        exit 1
    fi
}

# 从工具链文件提取 CROSS_COMPILE 前缀
get_cross_compile_prefix() {
    local toolchain_file="$1"

    if [ -z "$toolchain_file" ] || [ "$toolchain_file" = "android" ]; then
        echo ""
        return 0
    fi

    if [ ! -f "$toolchain_file" ]; then
        echo ""
        return 0
    fi

    local prefix
    # 提取默认的 CROSS_COMPILE 值（不在 if 语句中的）
    prefix=$(grep -E "^[[:space:]]*set\([[:space:]]*CROSS_COMPILE[[:space:]]+" "$toolchain_file" | grep -v "if" | grep -v "ENV" | head -n1 | sed -E 's/.*CROSS_COMPILE[[:space:]]+([A-Za-z0-9_-]*).*/\1/')

    # 如果前缀为空字符串，表示原生编译
    if [ -z "$prefix" ]; then
        echo ""
        return 0
    fi

    normalize_cross_prefix "$prefix"
}

# 获取 OpenSSL 目标平台
get_openssl_target() {
    local target_name="$1"
    
    case "$target_name" in
        aarch64-linux-gnu)
            echo "linux-aarch64"
            ;;
        arm-linux-gnueabihf)
            echo "linux-armv4"
            ;;
        x86_64-linux-gnu)
            echo "linux-x86_64"
            ;;
        aarch64-linux-android)
            echo "android-arm64"
            ;;
        arm-linux-android)
            echo "android-arm"
            ;;
        *)
            log_error "Unsupported target: $target_name"
            exit 1
            ;;
    esac
}

# 通用构建函数
build_target_common() {
    local target_name="$1"
    local toolchain_file="$2"
    local output_dir="$3"
    local is_android="$4"

    log_info "构建目标: $target_name..."

    mkdir -p "$output_dir"

    local build_dir="${OPENSSL_SOURCE_DIR}/build_${target_name}"
    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    cd "${OPENSSL_SOURCE_DIR}"

    # 获取 OpenSSL 目标平台
    local openssl_target
    openssl_target=$(get_openssl_target "$target_name")

    # 设置环境变量
    if [ "$is_android" = "true" ]; then
        init_android_env "$target_name"
        export PATH="$TOOLCHAIN/bin:$PATH"
    elif [ -n "$toolchain_file" ] && [ -f "$toolchain_file" ]; then
        # 从工具链文件设置交叉编译环境
        local cross_prefix
        cross_prefix=$(get_cross_compile_prefix "$toolchain_file")
        if [ -n "$cross_prefix" ]; then
            export CROSS_COMPILE="$cross_prefix"
        fi
    fi

    # 清理之前的构建
    log_info "清理之前的构建..."
    make clean || true

    # 配置 OpenSSL
    log_info "配置 OpenSSL..."
    ./Configure \
        --prefix="$output_dir" \
        --openssldir="$output_dir/ssl" \
        --libdir=lib \
        no-shared \
        no-tests \
        "$openssl_target"
    
    check_command_result $? "OpenSSL configuration failed for $target_name"

    # 编译 OpenSSL
    log_info "编译 OpenSSL..."
    make -j"$(nproc)"
    check_command_result $? "OpenSSL build failed for $target_name"

    # 安装 OpenSSL
    log_info "安装 OpenSSL..."
    make install_sw
    check_command_result $? "OpenSSL install failed for $target_name"

    log_success "$target_name 构建完成"

    if [ "$BUILD_TYPE_LOWER" = "release" ]; then
        if [ "$is_android" = "true" ]; then
            compress_android_libraries "$output_dir" "$target_name" "$build_dir"
        else
            local cross_prefix
            cross_prefix=$(get_cross_compile_prefix "$toolchain_file")
            if [ -z "$cross_prefix" ] && [ -n "$CROSS_COMPILE" ]; then
                cross_prefix=$(normalize_cross_prefix "$CROSS_COMPILE")
            fi
            local available_tools
            available_tools=$(check_cross_compile_tools "$cross_prefix" "$target_name" "$build_dir" "$toolchain_file")
            compress_artifacts_in_dir \
                "$output_dir" \
                "$target_name" \
                "$available_tools" \
                --locale zh \
                --allow-upx \
                --summary-label "${target_name} 压缩统计:"
        fi
    else
        log_info "Debug 构建类型，跳过库压缩"
    fi

    cd "$WORKSPACE_DIR"
}

# Android编译函数
build_android_target() {
    local target_name="$1"
    local output_dir="$2"
    build_target_common "$target_name" "" "$output_dir" "true"
}

# Android环境初始化
init_android_env() {
    local target="$1"
    
    if [[ "$target" == "aarch64-linux-android" || "$target" == "arm-linux-android" ]]; then
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
                log_info "Initializing Android NDK for arm64-v8a (API $API_LEVEL)"
                ;;
            arm-linux-android)
                ANDROID_ABI=armeabi-v7a
                log_info "Initializing Android NDK for armeabi-v7a (API $API_LEVEL)"
                ;;
        esac
    else
        log_error "Unsupported Android target: $target"
        exit 1
    fi
}

# Android库文件压缩（使用通用压缩函数）
compress_android_libraries() {
    local output_dir="$1"
    local target_name="$2"
    local build_dir="$3"

    log_info "压缩 Android 库文件: $target_name..."

    local cross_prefix=""

    case "$target_name" in
        aarch64-linux-android)
            cross_prefix="aarch64-linux-android-"
            ;;
        arm-linux-android)
            cross_prefix="arm-linux-androideabi-"
            ;;
        *)
            log_warning "未知的 Android 目标: $target_name，跳过压缩"
            return 0
            ;;
    esac

    local available_tools
    available_tools=$(check_cross_compile_tools "$cross_prefix" "$target_name" "$build_dir" "")

    compress_artifacts_in_dir \
        "$output_dir" \
        "$target_name" \
        "$available_tools" \
        --locale zh \
        --allow-upx \
        --summary-label "${target_name} 压缩统计:"
}

# 编译函数
build_target() {
    local target_name="$1"
    local toolchain_file="$2"
    local output_dir="$3"
    build_target_common "$target_name" "$toolchain_file" "$output_dir" "false"
}

# 显示帮助信息
show_help() {
    cat << EOF
OpenSSL 构建脚本

用法: $0 [选项] [目标平台...]

选项:
    --build-type <type>     构建类型: Debug 或 Release (默认: Release)
    --all                   构建所有支持的目标平台
    --help                  显示此帮助信息

目标平台:
    aarch64-linux-gnu       ARM64 Linux GNU
    arm-linux-gnueabihf     ARM Linux GNU EABI HF
    x86_64-linux-gnu        x86_64 Linux GNU
    aarch64-linux-android   ARM64 Android
    arm-linux-android       ARM Android

环境变量:
    OPENSSL_VERSION         OpenSSL 版本号 (默认: 3.5.4)

示例:
    $0 --all                                    # 构建所有目标平台
    $0 --build-type Debug aarch64-linux-gnu    # 构建 ARM64 Linux Debug 版本
    $0 aarch64-linux-gnu x86_64-linux-gnu      # 构建指定目标平台

EOF
}

# 主函数
main() {
    local targets=()
    local build_all=false

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --build-type)
                set_build_type_from_arg "$2"
                shift 2
                ;;
            --all)
                build_all=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                targets+=("$1")
                shift
                ;;
        esac
    done

    # 如果没有指定目标，使用默认目标
    if [ ${#targets[@]} -eq 0 ] && [ "$build_all" = false ]; then
        log_info "未指定目标平台，使用默认目标: $_DEFAULT_BUILD_TARGETS"
        IFS=',' read -ra targets <<< "$_DEFAULT_BUILD_TARGETS"
    fi

    # 如果指定了 --all，使用所有支持的目标
    if [ "$build_all" = true ]; then
        IFS=',' read -ra targets <<< "$_DEFAULT_BUILD_TARGETS"
    fi

    # 确保必要的工具可用
    ensure_tools_available wget tar make gcc

    # 下载 OpenSSL 源码
    download_openssl

    # 构建所有指定的目标
    for target in "${targets[@]}"; do
        case "$target" in
            aarch64-linux-gnu|arm-linux-gnueabihf|x86_64-linux-gnu)
                local toolchain_file="${TOOLCHAIN_DIR}/${target}.cmake"
                if [ ! -f "$toolchain_file" ]; then
                    log_error "工具链文件不存在: $toolchain_file"
                    exit 1
                fi
                local output_dir
                output_dir=$(get_output_dir_for_build_type "${OPENSSL_OUTPUT_DIR}/${target}")
                build_target "$target" "$toolchain_file" "$output_dir"
                ;;
            aarch64-linux-android|arm-linux-android)
                local output_dir
                output_dir=$(get_output_dir_for_build_type "${OPENSSL_OUTPUT_DIR}/${target}")
                build_android_target "$target" "$output_dir"
                ;;
            *)
                log_error "不支持的目标平台: $target"
                exit 1
                ;;
        esac
    done

    log_success "所有目标构建完成！"
}

# 脚本入口
main "$@"