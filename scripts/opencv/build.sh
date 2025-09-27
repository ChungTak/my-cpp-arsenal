#!/bin/bash

# OPENCV 构建脚本
# 支持多种交叉编译工具链编译 OPENCV 库

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLCHAIN_DIR="${WORKSPACE_DIR}/toolchain"
SOURCES_DIR="${WORKSPACE_DIR}/sources"
OUTPUTS_DIR="${WORKSPACE_DIR}/outputs"
OPENCV_OUTPUT_DIR="${OUTPUTS_DIR}/opencv"
OPENCV_SOURCE_DIR="${SOURCES_DIR}/opencv"
TEMP_DIR="${WORKSPACE_DIR}/.tmp/opencv"
OPENCV_VERSION="4.5.5"

# 默认构建类型配置
source "${SCRIPT_DIR}/../common.sh"

reset_build_type_state
VERSION_OVERRIDE=""
PARSED_TARGET=""

# 限制默认编译目标
_DEFAULT_BUILD_TARGETS="aarch64-linux-gnu,arm-linux-gnueabihf,aarch64-linux-android,arm-linux-android"

# 错误处理辅助
check_command_result() {
    local exit_code="$1"
    local message="$2"

    if [ "$exit_code" -ne 0 ]; then
        log_error "$message"
        exit "$exit_code"
    fi
}

# 克隆 opencv 源码
download_opencv() {
    log_info "Preparing opencv source..."

    if [ -d "$OPENCV_SOURCE_DIR" ] && [ -f "${OPENCV_SOURCE_DIR}/CMakeLists.txt" ]; then
        log_success "opencv source already present: $OPENCV_SOURCE_DIR"
    else
        mkdir -p "$TEMP_DIR"
        local archive_name="${OPENCV_VERSION}.tar.gz"
        local archive_path="${TEMP_DIR}/${archive_name}"
        local download_url="${OPENCV_DOWNLOAD_URL:-https://github.com/opencv/opencv/archive/refs/tags/${archive_name}}"

        ensure_tools_available wget tar

        if [ ! -f "$archive_path" ]; then
            log_info "Downloading ${download_url}"
            if ! wget -O "$archive_path" "$download_url"; then
                log_error "Failed to download opencv archive from $download_url"
                return 1
            fi
        fi

        rm -rf "$OPENCV_SOURCE_DIR"
        mkdir -p "$SOURCES_DIR"

        if ! tar -xf "$archive_path" -C "$SOURCES_DIR"; then
            log_error "Failed to extract $archive_path"
            return 1
        fi

        local extracted_dir="${SOURCES_DIR}/opencv-${OPENCV_VERSION}"
        if [ -d "$extracted_dir" ]; then
            mv "$extracted_dir" "$OPENCV_SOURCE_DIR"
        elif [ ! -d "$OPENCV_SOURCE_DIR" ]; then
            log_error "Extracted opencv directory not found"
            return 1
        fi

        log_success "opencv source prepared at $OPENCV_SOURCE_DIR"
    fi
    log_info "Using opencv version: $OPENCV_VERSION"
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
    prefix=$(grep -E "CROSS_COMPILE" "$toolchain_file" | head -n1 | sed -E 's/.*CROSS_COMPILE[[:space:]]+\"?([A-Za-z0-9_-]+)\-?\"?.*/\1/')

    if [ -z "$prefix" ]; then
        echo ""
        return 0
    fi

    normalize_cross_prefix "$prefix"
}

# 通用构建函数
build_target_common() {
    local target_name="$1"
    local toolchain_file="$2"
    local output_dir="$3"
    local is_android="$4"

    log_info "构建目标: $target_name..."

    mkdir -p "$output_dir"

    local build_dir
    if [ "$is_android" = "true" ]; then
        build_dir="${OPENCV_SOURCE_DIR}/build/build_${target_name}"
    else
        build_dir="${OPENCV_SOURCE_DIR}/build_${target_name}"
    fi

    rm -rf "$build_dir"
    mkdir -p "$build_dir"

    cd "$build_dir"

    local cmake_args=()
    if [ "$is_android" = "true" ]; then
        init_android_env "$target_name"
        local android_toolchain="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake"
        if [ ! -f "$android_toolchain" ]; then
            log_error "Android NDK CMake toolchain not found: $android_toolchain"
            return 1
        fi

        cmake_args+=(
            -DCMAKE_TOOLCHAIN_FILE="$android_toolchain"
            -DANDROID_ABI="$ANDROID_ABI"
            -DANDROID_PLATFORM="android-$API_LEVEL"
        )
    else
        cmake_args+=(
            -DCMAKE_TOOLCHAIN_FILE="$toolchain_file"
        )
    fi

    cmake_args+=(
        "-DCMAKE_BUILD_TYPE=$BUILD_TYPE"
        "-DCMAKE_INSTALL_PREFIX=$output_dir"
    )
    # 读取 opencv4_cmake_options.txt 文件中的参数并追加到 CMAKE_CMD
    OPTIONS_FILE="$SCRIPT_DIR/opencv4_cmake_options.txt"
    if [ -f "$OPTIONS_FILE" ]; then
        log_info "读取 OpenCV 配置参数: $OPTIONS_FILE"    
        while IFS= read -r line; do
            # 跳过空行和注释行
            if [[ -n "$line" && ! "$line" =~ ^[[:space:]]*# ]]; then
                cmake_args+=($line)
            fi
        done < "$OPTIONS_FILE"
        log_success "已应用 OpenCV 配置参数"
    else
        log_warning "警告: 未找到配置文件 $OPTIONS_FILE，将使用默认配置"    
    fi    

    if [ "$is_android" = "true" ]; then
        cmake ../.. "${cmake_args[@]}"
    else
        cmake .. "${cmake_args[@]}"
    fi
    check_command_result $? "CMake configuration failed for $target_name"

    make -j"$(nproc)"
    check_command_result $? "Build failed for $target_name"

    make install
    check_command_result $? "Install failed for $target_name"

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
            echo "arm-linux-gnueabihf:${TOOLCHAIN_DIR}/arm-linux-gnueabihf.cmake:${OPENCV_OUTPUT_DIR}/arm-linux-gnueabihf"
            ;;
        "aarch64-linux-gnu")
            echo "aarch64-linux-gnu:${TOOLCHAIN_DIR}/aarch64-linux-gnu.cmake:${OPENCV_OUTPUT_DIR}/aarch64-linux-gnu"
            ;;
        "arm-linux-musleabihf")
            echo "arm-linux-musleabihf:${TOOLCHAIN_DIR}/arm-linux-musleabihf.cmake:${OPENCV_OUTPUT_DIR}/arm-linux-musleabihf"
            ;;
        "riscv64-linux-gnu")
            echo "riscv64-linux-gnu:${TOOLCHAIN_DIR}/riscv64-linux-gnu.cmake:${OPENCV_OUTPUT_DIR}/riscv64-linux-gnu"
            ;;
        "riscv64-linux-musl")
            echo "riscv64-linux-musl:${TOOLCHAIN_DIR}/riscv64-linux-musl.cmake:${OPENCV_OUTPUT_DIR}/riscv64-linux-musl"
            ;;
        "aarch64-linux-musl")
            echo "aarch64-linux-musl:${TOOLCHAIN_DIR}/aarch64-linux-musl.cmake:${OPENCV_OUTPUT_DIR}/aarch64-linux-musl"
            ;;
        "aarch64-linux-android")
            echo "aarch64-linux-android:android:${OPENCV_OUTPUT_DIR}/aarch64-linux-android"
            ;;
        "arm-linux-android")
            echo "arm-linux-android:android:${OPENCV_OUTPUT_DIR}/arm-linux-android"
            ;;
        "x86_64-linux-gnu")
            echo "x86_64-linux-gnu:${TOOLCHAIN_DIR}/x86_64-linux-gnu.cmake:${OPENCV_OUTPUT_DIR}/x86_64-linux-gnu"
            ;;
        "x86_64-windows-gnu")
            echo "x86_64-windows-gnu:${TOOLCHAIN_DIR}/x86_64-windows-gnu.cmake:${OPENCV_OUTPUT_DIR}/x86_64-windows-gnu"
            ;;
        "x86_64-macos")
            echo "x86_64-macos:${TOOLCHAIN_DIR}/x86_64-macos.cmake:${OPENCV_OUTPUT_DIR}/x86_64-macos"
            ;;
        "aarch64-macos")
            echo "aarch64-macos:${TOOLCHAIN_DIR}/aarch64-macos.cmake:${OPENCV_OUTPUT_DIR}/aarch64-macos"
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
        echo "arm-linux-gnueabihf:${TOOLCHAIN_DIR}/arm-linux-gnueabihf.cmake:${OPENCV_OUTPUT_DIR}/arm-linux-gnueabihf"
        echo "aarch64-linux-gnu:${TOOLCHAIN_DIR}/aarch64-linux-gnu.cmake:${OPENCV_OUTPUT_DIR}/aarch64-linux-gnu"
        echo "arm-linux-musleabihf:${TOOLCHAIN_DIR}/arm-linux-musleabihf.cmake:${OPENCV_OUTPUT_DIR}/arm-linux-musleabihf"
        echo "riscv64-linux-gnu:${TOOLCHAIN_DIR}/riscv64-linux-gnu.cmake:${OPENCV_OUTPUT_DIR}/riscv64-linux-gnu"
        echo "riscv64-linux-musl:${TOOLCHAIN_DIR}/riscv64-linux-musl.cmake:${OPENCV_OUTPUT_DIR}/riscv64-linux-musl"
        echo "aarch64-linux-musl:${TOOLCHAIN_DIR}/aarch64-linux-musl.cmake:${OPENCV_OUTPUT_DIR}/aarch64-linux-musl"
        echo "aarch64-linux-android:android:${OPENCV_OUTPUT_DIR}/aarch64-linux-android"
        echo "arm-linux-android:android:${OPENCV_OUTPUT_DIR}/arm-linux-android"
        echo "x86_64-linux-gnu:${TOOLCHAIN_DIR}/x86_64-linux-gnu.cmake:${OPENCV_OUTPUT_DIR}/x86_64-linux-gnu"
        echo "x86_64-windows-gnu:${TOOLCHAIN_DIR}/x86_64-windows-gnu.cmake:${OPENCV_OUTPUT_DIR}/x86_64-windows-gnu"
        echo "x86_64-macos:${TOOLCHAIN_DIR}/x86_64-macos.cmake:${OPENCV_OUTPUT_DIR}/x86_64-macos"
        echo "aarch64-macos:${TOOLCHAIN_DIR}/aarch64-macos.cmake:${OPENCV_OUTPUT_DIR}/aarch64-macos"
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
            --version)
                if [ -z "${2:-}" ]; then
                    log_error "--version requires a value"
                    exit 1
                fi
                VERSION_OVERRIDE="$2"
                shift 2
                continue
                ;;
            Debug|debug|Release|release)
                log_error "请使用 --build_type 参数设置构建类型"
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
        log_error "Valid targets: arm-linux-gnueabihf, aarch64-linux-gnu, arm-linux-musleabihf, riscv64-linux-gnu, riscv64-linux-musl, aarch64-linux-musl, aarch64-linux-android, arm-linux-android, x86_64-linux-gnu, x86_64-windows-gnu, x86_64-macos, aarch64-macos"
        exit 1
    fi

    PARSED_TARGET="$target"
}

# 构建单个目标
build_single_target() {
    local target_to_build="$1"
    
    log_info "构建单个目标: $target_to_build"
    
    local target_config
    target_config=$(get_target_config "$target_to_build")
    
    if [ -z "$target_config" ]; then
        log_error "无效的目标: $target_to_build"
        exit 1
    fi
    
    IFS=':' read -r target_name toolchain_file output_dir <<< "$target_config"
    local effective_output_dir
    effective_output_dir=$(get_output_dir_for_build_type "$output_dir")
    log_info "输出目录: $effective_output_dir"
    
    # 检查是否为Android目标
    if [[ "$target_to_build" == "aarch64-linux-android" || "$target_to_build" == "arm-linux-android" ]]; then
        # Android目标使用专门的构建函数
        if build_android_target "$target_name" "$effective_output_dir"; then
            log_success "$target_to_build 构建完成"
        else
            log_error "$target_to_build 构建失败"
            exit 1
        fi
    else
        # 检查toolchain文件是否存在
        if [ ! -f "$toolchain_file" ]; then
            log_error "工具链文件不存在: $toolchain_file"
            log_error "请安装相应的交叉编译工具链"
            exit 1
        fi
        
        # 构建目标
        if build_target "$target_name" "$toolchain_file" "$effective_output_dir"; then
            log_success "$target_to_build 构建完成"
        else
            log_error "$target_to_build 构建失败"
            exit 1
        fi
    fi
}

# 构建多个目标
build_multiple_targets() {
    if [ -n "$_DEFAULT_BUILD_TARGETS" ]; then
        log_info "构建默认目标: $_DEFAULT_BUILD_TARGETS"
    else
        log_info "构建所有目标..."
    fi
    
    # 获取要构建的目标列表
    local targets_to_build
    targets_to_build=$(get_default_build_targets)
    
    if [ -z "$targets_to_build" ]; then
        log_error "没有有效的构建目标"
        exit 1
    fi
    
    # 构建所有指定的目标
    while IFS= read -r target_config; do
        [ -z "$target_config" ] && continue
        
        IFS=':' read -r target_name toolchain_file output_dir <<< "$target_config"
        local effective_output_dir
        effective_output_dir=$(get_output_dir_for_build_type "$output_dir")
        log_info "输出目录: $effective_output_dir"
        
        # 检查是否为Android目标
        if [[ "$target_name" == "aarch64-linux-android" || "$target_name" == "arm-linux-android" ]]; then
            # Android目标使用专门的构建函数
            if ! build_android_target "$target_name" "$effective_output_dir"; then
                log_warning "$target_name 构建失败，继续下一个目标"
                continue
            fi
        else
            # 检查toolchain文件是否存在
            if [ ! -f "$toolchain_file" ]; then
                log_warning "工具链文件不存在: $toolchain_file，跳过 $target_name"
                continue
            fi
            
            # 构建目标
            if ! build_target "$target_name" "$toolchain_file" "$effective_output_dir"; then
                log_warning "$target_name 构建失败，继续下一个目标"
                continue
            fi
        fi
    done <<< "$targets_to_build"
}

# 主函数
main() {
    local target_to_build="${1:-$PARSED_TARGET}"
    
    # 设置版本号
    OPENCV_VERSION="${VERSION_OVERRIDE:-4.5.5}"
    
    log_info "开始 OPENCV 构建过程..."
    log_info "当前构建类型: $BUILD_TYPE"
    
    # 检查工具
    ensure_tools_available git cmake make
    
    # 克隆源码
    download_opencv
    
    # 创建输出目录
    mkdir -p "$OPENCV_OUTPUT_DIR"
    
    if [ -n "$target_to_build" ]; then
        build_single_target "$target_to_build"
    else
        build_multiple_targets
    fi
    
    log_success "构建过程完成!"
    log_info "输出目录: $OPENCV_OUTPUT_DIR"
    
    # 生成version.ini文件
    create_version_file

    # 显示目录结构
    log_info "目录结构:"
    tree "$OPENCV_OUTPUT_DIR" 2>/dev/null || ls -la "$OPENCV_OUTPUT_DIR"
}


# 创建版本信息文件
create_version_file() {
    log_info "Creating version.ini file..."
    
    local version_file="${OPENCV_OUTPUT_DIR}/version.ini"
    local version_to_write="${OPENCV_VERSION:-unknown}"

    # 写入版本信息到version.ini
    cat > "$version_file" << EOF
[version]
version=$version_to_write
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Version file created successfully: $version_file"
        log_info "libdrm version: $OPENCV_VERSION"
    else
        log_error "Failed to create version file: $version_file"
        return 1
    fi
}


# 清理函数
cleanup() {
    log_info "Cleaning up..."
    
    # 清理构建目录
    if [ -d "${OPENCV_SOURCE_DIR}" ]; then
        find "${OPENCV_SOURCE_DIR}" -name "build_*" -type d -exec rm -rf {} + 2>/dev/null || true
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
    if [ -d "${OPENCV_OUTPUT_DIR}" ]; then
        log_info "Removing output directory: ${OPENCV_OUTPUT_DIR}"
        rm -rf "${OPENCV_OUTPUT_DIR}"
    fi
    
    log_success "Clean completed"
}

# 帮助信息
show_help() {
        local script_name
        script_name="$(basename "$0")"

        cat <<EOF
OPENCV Build Script

Usage: ./${script_name} [OPTIONS] [TARGET]

TARGET (optional):
    arm-linux-gnueabihf    Build ARM 32-bit glibc version
    aarch64-linux-gnu      Build ARM 64-bit glibc version
    riscv64-linux-gnu      Build RISC-V 64-bit glibc version
    arm-linux-musleabihf   Build ARM 32-bit musl version
    aarch64-linux-musl     Build ARM 64-bit musl version
    riscv64-linux-musl     Build RISC-V 64-bit musl version
    aarch64-linux-android  Build Android ARM 64-bit version
    arm-linux-android      Build Android ARM 32-bit version
    x86_64-linux-gnu       Build x86_64 Linux version
    x86_64-windows-gnu     Build x86_64 Windows version
    x86_64-macos           Build x86_64 macOS version
    aarch64-macos          Build ARM 64-bit macOS version

Options:
    -h, --help                        Show this help message
    -c, --clean                       Clean build directories only
    --clean-all                       Clean all (sources and outputs)
    --build_type {Debug|Release}      Specify CMake build type (default: Release)
    --version VERSION                 Specify OpenCV version (default: 4.5.5)

Environment Variables:
    TOOLCHAIN_ROOT_DIR    Path to cross-compilation toolchain (optional)
    ANDROID_NDK_HOME      Path to Android NDK (default: ~/sdk/android_ndk/android-ndk-r25c)

Examples:
    ./${script_name}                                # Build default targets
    ./${script_name} aarch64-linux-gnu              # Build ARM 64-bit glibc version
    ./${script_name} arm-linux-musleabihf           # Build ARM 32-bit musl version
    ./${script_name} aarch64-linux-android          # Build Android ARM 64-bit version
    ./${script_name} --clean                        # Clean build directories
    ./${script_name} --clean-all                    # Clean everything
    ./${script_name} --build_type Debug aarch64-linux-gnu  # Debug build for ARM64
    ./${script_name} --version 4.8.0 aarch64-linux-gnu  # Build specific version
EOF
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

