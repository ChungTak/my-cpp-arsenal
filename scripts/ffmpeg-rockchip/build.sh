#!/bin/bash

# FFmpeg Rockchip 构建脚本
# 支持多种交叉编译工具链编译 FFmpeg Rockchip 版本

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLCHAIN_DIR="${WORKSPACE_DIR}/toolchain"
SOURCES_DIR="${WORKSPACE_DIR}/sources"
OUTPUTS_DIR="${WORKSPACE_DIR}/outputs"
FFMPEG_OUTPUT_DIR="${OUTPUTS_DIR}/ffmpeg-rockchip"

# ffmpeg-rockchip 源码目录
FFMPEG_SOURCE_DIR="${SOURCES_DIR}/ffmpeg-rockchip"

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

# 检查必要的工具
check_tools() {
    local tools=("git" "make")
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Missing required tool: $tool"
            exit 1
        fi
    done
}

# 克隆 ffmpeg-rockchip 源码
clone_ffmpeg() {
    log_info "Checking ffmpeg-rockchip repository..."
    
    # 创建sources目录
    mkdir -p "${SOURCES_DIR}"
    
    # 如果目录已存在且包含configure脚本，跳过克隆
    if [ -d "${FFMPEG_SOURCE_DIR}" ] && [ -f "${FFMPEG_SOURCE_DIR}/configure" ]; then
        log_success "ffmpeg-rockchip source already exists, skipping clone"
        return 0
    fi
    
    # 如果目录存在但不完整，先删除
    if [ -d "${FFMPEG_SOURCE_DIR}" ]; then
        log_warning "Removing incomplete ffmpeg-rockchip directory"
        rm -rf "${FFMPEG_SOURCE_DIR}"
    fi
    
    # 克隆最新代码
    log_info "Cloning ffmpeg-rockchip repository..."
    git clone --depth=1 https://github.com/nyanmisaka/ffmpeg-rockchip.git "${FFMPEG_SOURCE_DIR}"
    
    if [ $? -eq 0 ]; then
        log_success "ffmpeg-rockchip cloned successfully"
    else
        log_error "Failed to clone ffmpeg-rockchip"
        exit 1
    fi
}

# 获取目标配置
get_target_config() {
    local target="$1"
    case "$target" in
        "arm-linux-gnueabihf")
            echo "arm-linux-gnueabihf:${FFMPEG_OUTPUT_DIR}/arm-linux-gnueabihf"
            ;;
        "aarch64-linux-gnu")
            echo "aarch64-linux-gnu:${FFMPEG_OUTPUT_DIR}/aarch64-linux-gnu"
            ;;
        "arm-linux-musleabihf")
            echo "arm-linux-musleabihf:${FFMPEG_OUTPUT_DIR}/arm-linux-musleabihf"
            ;;
        "aarch64-linux-musl")
            echo "aarch64-linux-musl:${FFMPEG_OUTPUT_DIR}/aarch64-linux-musl"
            ;;
        "riscv64-linux-gnu")
            echo "riscv64-linux-gnu:${FFMPEG_OUTPUT_DIR}/riscv64-linux-gnu"
            ;;
        "riscv64-linux-musl")
            echo "riscv64-linux-musl:${FFMPEG_OUTPUT_DIR}/riscv64-linux-musl"
            ;;
        "aarch64-linux-android")
            echo "aarch64-linux-android:${FFMPEG_OUTPUT_DIR}/aarch64-linux-android"
            ;;
        "arm-linux-android")
            echo "arm-linux-android:${FFMPEG_OUTPUT_DIR}/arm-linux-android"
            ;;
        "x86_64-linux-gnu")
            echo "x86_64-linux-gnu:${FFMPEG_OUTPUT_DIR}/x86_64-linux-gnu"
            ;;
        "x86_64-windows-gnu")
            echo "x86_64-windows-gnu:${FFMPEG_OUTPUT_DIR}/x86_64-windows-gnu"
            ;;
        "x86_64-macos")
            echo "x86_64-macos:${FFMPEG_OUTPUT_DIR}/x86_64-macos"
            ;;
        "aarch64-macos")
            echo "aarch64-macos:${FFMPEG_OUTPUT_DIR}/aarch64-macos"
            ;;
        *)
            echo ""
            ;;
    esac
}

# 设置依赖环境变量
setup_dependency_env() {
    local target="$1"
    local rkmpp_dir=""
    local rkrga_dir=""
    local libdrm_dir=""
    
    case "$target" in
        "arm-linux-gnueabihf")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/arm-linux-gnueabihf"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/arm-linux-gnueabihf"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/arm-linux-gnueabihf"
            ;;
        "aarch64-linux-gnu")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/aarch64-linux-gnu"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/aarch64-linux-gnu"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/aarch64-linux-gnu"
            ;;
        "arm-linux-musleabihf")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/arm-linux-musleabihf"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/arm-linux-musleabihf"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/arm-linux-musleabihf"
            ;;
        "aarch64-linux-musl")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/aarch64-linux-musl"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/aarch64-linux-musl"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/aarch64-linux-musl"
            ;;
        "riscv64-linux-gnu")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/riscv64-linux-gnu"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/riscv64-linux-gnu"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/riscv64-linux-gnu"
            ;;
        "riscv64-linux-musl")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/riscv64-linux-musl"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/riscv64-linux-musl"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/riscv64-linux-musl"
            ;;
        "aarch64-linux-android")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/aarch64-linux-android"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/aarch64-linux-android"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/aarch64-linux-android"
            ;;
        "arm-linux-android")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/arm-linux-android"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/arm-linux-android"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/arm-linux-android"
            ;;
        "x86_64-linux-gnu")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/x86_64-linux-gnu"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/x86_64-linux-gnu"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/x86_64-linux-gnu"
            ;;
        "x86_64-windows-gnu")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/x86_64-windows-gnu"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/x86_64-windows-gnu"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/x86_64-windows-gnu"
            ;;
        "x86_64-macos")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/x86_64-macos"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/x86_64-macos"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/x86_64-macos"
            ;;
        "aarch64-macos")
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp/aarch64-macos"
            rkrga_dir="${OUTPUTS_DIR}/rkrga/aarch64-macos"
            libdrm_dir="${OUTPUTS_DIR}/libdrm/aarch64-macos"
            ;;
        *)
            rkmpp_dir="${OUTPUTS_DIR}/rkmpp"
            rkrga_dir="${OUTPUTS_DIR}/rkrga"
            libdrm_dir="${OUTPUTS_DIR}/libdrm"
            ;;
    esac
    
    # 检查依赖是否都存在
    if [ ! -d "$rkmpp_dir" ]; then
        log_error "rkmpp dependency not found: $rkmpp_dir"
        return 1
    fi
    
    if [ ! -d "$rkrga_dir" ]; then
        log_error "rkrga dependency not found: $rkrga_dir"
        return 1
    fi
    
    if [ ! -d "$libdrm_dir" ]; then
        log_error "libdrm dependency not found: $libdrm_dir"
        return 1
    fi
    
    # 设置环境变量
    export RKMPP_PATH="$rkmpp_dir"
    export RKRGA_PATH="$rkrga_dir"
    export LIBDRM_PATH="$libdrm_dir"
    export PKG_CONFIG_PATH="${RKMPP_PATH}/lib/pkgconfig:${RKRGA_PATH}/lib/pkgconfig:${LIBDRM_PATH}/lib/pkgconfig:${PKG_CONFIG_PATH}"
    export CFLAGS="-I${RKMPP_PATH}/include -I${RKRGA_PATH}/include -I${LIBDRM_PATH}/include -DHAVE_SYSCTL=0 ${CFLAGS}"
    export LDFLAGS="-L${RKMPP_PATH}/lib -L${RKRGA_PATH}/lib -L${LIBDRM_PATH}/lib ${LDFLAGS}"
    
    log_success "Dependency environment variables set"
    log_info "  RKMPP_PATH: $RKMPP_PATH"
    log_info "  RKRGA_PATH: $RKRGA_PATH"
    log_info "  LIBDRM_PATH: $LIBDRM_PATH"
}

# 获取交叉编译工具
get_cross_tools() {
    local target="$1"
    local cross_prefix=""
    
    case "$target" in
        "arm-linux-gnueabihf")
            cross_prefix="arm-linux-gnueabihf-"
            ;;
        "aarch64-linux-gnu")
            cross_prefix="aarch64-linux-gnu-"
            ;;
        "arm-linux-musleabihf")
            cross_prefix="arm-linux-musleabihf-"
            ;;
        "aarch64-linux-musl")
            cross_prefix="aarch64-linux-musl-"
            ;;
        "riscv64-linux-gnu")
            cross_prefix="riscv64-linux-gnu-"
            ;;
        "riscv64-linux-musl")
            cross_prefix="riscv64-linux-musl-"
            ;;
        "aarch64-linux-android")
            cross_prefix="aarch64-linux-android-"
            ;;
        "arm-linux-android")
            cross_prefix="arm-linux-androideabi-"
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
        *)
            cross_prefix=""
            ;;
    esac
    
    echo "$cross_prefix"
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

# 设置架构和目标操作系统
setup_arch_and_os() {
    local target="$1"
    local arch=""
    local target_os=""
    
    # 设置架构
    case "$target" in
        arm-*)
            arch="arm"
            ;;
        aarch64-*)
            arch="aarch64"
            ;;
        x86-*)
            arch="x86"
            ;;
        x86_64-*)
            arch="x86_64"
            ;;
        riscv64-*)
            arch="riscv64"
            ;;
        loongarch64-*)
            arch="loongarch64"
            ;;
    esac
    
    # 设置目标操作系统
    case "$target" in
        *-android)
            target_os="android"
            ;;
        *-windows-*)
            target_os="mingw32"
            ;;
        *-macos)
            target_os="darwin"
            ;;
        *)
            target_os="linux"
            ;;
    esac
    
    echo "$arch:$target_os"
}

# 获取RockChip特定的配置选项
get_rk_only_options() {
    echo "--disable-everything \
        --disable-x86asm \
        --disable-programs \
        --disable-doc \
        --disable-swscale \
        --disable-swresample \
        --disable-postproc \
        --disable-network \
        --disable-static \
        --disable-stripping \
        --enable-shared \
        --enable-version3 \
        --enable-ffmpeg \
        --enable-libdrm \
        --enable-rkrga \
        --enable-rkmpp \
        \
        --enable-protocol=file \
        \
        --enable-muxer=mp4 \
        --enable-muxer=avi \
        --enable-muxer=null \
        --enable-demuxer=mov \
        --enable-demuxer=matroska \
        --enable-demuxer=avi \
        \
        --enable-encoder=wrapped_avframe \
        --enable-encoder=rawvideo \
        --enable-encoder=h264_rkmpp \
        --enable-encoder=hevc_rkmpp \
        --enable-encoder=mjpeg_rkmpp \
        \
        --enable-decoder=wrapped_avframe \
        --enable-decoder=rawvideo \
        --enable-decoder=h264_rkmpp \
        --enable-decoder=av1_rkmpp \
        --enable-decoder=mjpeg_rkmpp \
        --enable-decoder=hevc_rkmpp \
        --enable-decoder=vp8_rkmpp \
        --enable-decoder=vp9_rkmpp \
        --enable-decoder=h263_rkmpp \
        --enable-decoder=mpeg1_rkmpp \
        --enable-decoder=mpeg2_rkmpp \
        --enable-decoder=mpeg4_rkmpp \
        \
        --enable-parser=h264 \
        --enable-parser=hevc \
        --enable-parser=mjpeg \
        --enable-parser=av1 \
        --enable-parser=vp8 \
        --enable-parser=vp9 \
        --enable-parser=h263 \
        --enable-parser=mpegvideo \
        --enable-parser=mpeg4video \
        \
        --enable-avfilter \
        --enable-indev=lavfi \
        --enable-filter=testsrc \
        --enable-filter=testsrc2 \
        --enable-filter=format \
        --enable-filter=hwupload \
        --enable-filter=hwdownload \
        --enable-filter=scale_rkrga \
        --enable-filter=overlay_rkrga \
        --enable-filter=vpp_rkrga"
}

# Android构建函数
build_android_target() {
    local target_name="$1"
    local output_dir="$2"
    
    log_info "Building Android target: $target_name..."
    
    # 初始化Android环境
    init_android_env "$target_name"
    
    # 设置依赖环境变量
    if ! setup_dependency_env "$target_name"; then
        return 1
    fi
    
    # 设置架构和目标操作系统
    local arch_and_os
    arch_and_os=$(setup_arch_and_os "$target_name")
    local ARCH
    local TARGET_OS
    IFS=':' read -r ARCH TARGET_OS <<< "$arch_and_os"
    
    # 设置Android特定的编译器
    local CC="${TOOLCHAIN}/bin/${ANDROID_TARGET}${API_LEVEL}-clang"
    local CXX="${TOOLCHAIN}/bin/${ANDROID_TARGET}${API_LEVEL}-clang++"
    local AR="${TOOLCHAIN}/bin/llvm-ar"
    local RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
    
    # 使用统一的构建执行函数
    if execute_build_process "$target_name" "$output_dir" "$ARCH" "$TARGET_OS" "$CC" "$CXX" "$AR" "$RANLIB" "" "$CFLAGS" "$LDFLAGS"; then
        return 0
    else
        return 1
    fi
}

# 执行构建流程（配置、编译、安装）
execute_build_process() {
    local target_name="$1"
    local output_dir="$2"
    local ARCH="$3"
    local TARGET_OS="$4"
    local CC="$5"
    local CXX="$6"
    local AR="$7"
    local RANLIB="$8"
    local cross_prefix="$9"
    local CFLAGS="${10}"
    local LDFLAGS="${11}"
    
    # 创建输出目录
    mkdir -p "$output_dir"
    
    # 进入源码目录
    cd "${FFMPEG_SOURCE_DIR}"
    
    # 构建配置命令
    local CONFIGURE_CMD="./configure"
    
    if [ -n "$cross_prefix" ]; then
        CONFIGURE_CMD="$CONFIGURE_CMD --cross-prefix='$cross_prefix'"
    fi
    
    CONFIGURE_CMD="$CONFIGURE_CMD --arch=$ARCH"
    CONFIGURE_CMD="$CONFIGURE_CMD --target-os=$TARGET_OS"
    CONFIGURE_CMD="$CONFIGURE_CMD --enable-cross-compile"
    CONFIGURE_CMD="$CONFIGURE_CMD --prefix=$output_dir"
    CONFIGURE_CMD="$CONFIGURE_CMD --cc='$CC'"
    CONFIGURE_CMD="$CONFIGURE_CMD --cxx='$CXX'"
    CONFIGURE_CMD="$CONFIGURE_CMD --ar='$AR'"
    CONFIGURE_CMD="$CONFIGURE_CMD --ranlib='$RANLIB'"
    CONFIGURE_CMD="$CONFIGURE_CMD --pkg-config=pkg-config"
    CONFIGURE_CMD="$CONFIGURE_CMD --extra-cflags='$CFLAGS'"
    CONFIGURE_CMD="$CONFIGURE_CMD --extra-ldflags='$LDFLAGS'"
    
    # 添加RockChip配置选项
    local RK_ONLY_OPTIONS
    RK_ONLY_OPTIONS=$(get_rk_only_options)
    CONFIGURE_CMD="$CONFIGURE_CMD $RK_ONLY_OPTIONS"
    
    # 配置
    log_info "Configuring FFmpeg for $target_name..."
    log_info "Configure command: $CONFIGURE_CMD"
    
    # 执行配置命令
    eval "$CONFIGURE_CMD"
    
    if [ $? -ne 0 ]; then
        log_error "Configure failed for $target_name"
        return 1
    fi
    
    # 清理之前的构建
    make clean
    
    # 编译
    log_info "Compiling FFmpeg for $target_name..."
    make -j$(nproc)
    
    if [ $? -ne 0 ]; then
        log_error "Build failed for $target_name"
        return 1
    fi
    
    # 安装
    log_info "Installing FFmpeg for $target_name..."
    make install
    
    if [ $? -ne 0 ]; then
        log_error "Install failed for $target_name"
        return 1
    fi
    
    log_success "Target $target_name build completed successfully"
    
    # 返回到工作目录
    cd "$WORKSPACE_DIR"
    
    return 0
}

# 构建单个目标
build_target() {
    local target_name="$1"
    local output_dir="$2"
    
    log_info "Building target: $target_name"
    
    # 检查是否为Android目标
    if [[ "$target_name" == *"-android" ]]; then
        # Android目标使用专门的构建函数
        if build_android_target "$target_name" "$output_dir"; then
            return 0
        else
            return 1
        fi
    fi
    
    # 设置依赖环境变量
    if ! setup_dependency_env "$target_name"; then
        return 1
    fi
    
    # 创建输出目录
    mkdir -p "$output_dir"
    
    # 获取交叉编译工具前缀
    local cross_prefix
    cross_prefix=$(get_cross_tools "$target_name")
    
    # 设置架构和目标操作系统
    local arch_and_os
    arch_and_os=$(setup_arch_and_os "$target_name")
    local ARCH
    local TARGET_OS
    IFS=':' read -r ARCH TARGET_OS <<< "$arch_and_os"
    
    # 设置编译器
    local CC="${cross_prefix}gcc"
    local CXX="${cross_prefix}g++"
    local AR="${cross_prefix}ar"
    local RANLIB="${cross_prefix}ranlib"
    
    # 如果是本地编译，使用系统默认编译器
    if [ -z "$cross_prefix" ]; then
        CC="gcc"
        CXX="g++"
        AR="ar"
        RANLIB="ranlib"
    fi
    
    # 使用统一的构建执行函数
    if execute_build_process "$target_name" "$output_dir" "$ARCH" "$TARGET_OS" "$CC" "$CXX" "$AR" "$RANLIB" "$cross_prefix" "$CFLAGS" "$LDFLAGS"; then
        return 0
    else
        return 1
    fi
}

# 获取默认构建目标
get_default_build_targets() {
    local targets=${1:-$_DEFAULT_BUILD_TARGETS}
    local result=""
    
    IFS=',' read -ra target_list <<< "$targets"
    for target in "${target_list[@]}"; do
        local target_config
        target_config=$(get_target_config "$target")
        if [ -n "$target_config" ]; then
            result="${result}${target_config}"$'\n'
        fi
    done
    
    echo -n "$result"
}

# 解析命令行参数
parse_arguments() {
    local target=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
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
                if [ -z "$target" ]; then
                    target="$1"
                else
                    log_error "Unknown argument: $1"
                    show_help
                    exit 1
                fi
                ;;
        esac
        shift
    done
    
    echo "$target"
}

# 主函数
main() {
    local target_to_build="$1"
    
    log_info "Starting FFmpeg Rockchip build process..."
    
    # 检查必要工具
    check_tools
    
    # 克隆源码
    clone_ffmpeg
    
    if [ -n "$target_to_build" ]; then
        # 构建特定目标
        local target_config
        target_config=$(get_target_config "$target_to_build")
        
        if [ -z "$target_config" ]; then
            log_error "Unknown target: $target_to_build"
            show_help
            exit 1
        fi
        
        IFS=':' read -r target_name output_dir <<< "$target_config"
        
        if build_target "$target_name" "$output_dir"; then
            log_success "Build completed successfully for $target_name"
        else
            log_error "Failed to build $target_name"
            exit 1
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
            
            IFS=':' read -r target_name output_dir <<< "$target_config"
            
            # 构建目标
            if ! build_target "$target_name" "$output_dir"; then
                log_warning "Failed to build $target_name, continuing with next target"
                continue
            fi
        done <<< "$targets_to_build"
    fi
    
    log_success "Build process completed!"
    log_info "Output directory: $FFMPEG_OUTPUT_DIR"
    
    # 显示目录结构
    log_info "Directory structure:"
    find "$FFMPEG_OUTPUT_DIR" -maxdepth 2 -type d | sort
}

# 清理函数
cleanup() {
    log_info "Cleaning up..."
    
    # 清理构建目录
    if [ -d "${FFMPEG_SOURCE_DIR}" ]; then
        find "${FFMPEG_SOURCE_DIR}" -name "build_*" -type d -exec rm -rf {} + 2>/dev/null || true
    fi
}

# 清理所有
clean_all() {
    log_info "Cleaning all..."
    
    # 清理源码目录
    if [ -d "${SOURCES_DIR}" ]; then
        log_info "Removing sources directory: ${SOURCES_DIR}"
        rm -rf "${FFMPEG_SOURCE_DIR}"
    fi
    
    # 清理输出目录
    if [ -d "${FFMPEG_OUTPUT_DIR}" ]; then
        log_info "Removing output directory: ${FFMPEG_OUTPUT_DIR}"
        rm -rf "${FFMPEG_OUTPUT_DIR}"
    fi
    
    log_success "Clean completed"
}

# 帮助信息
show_help() {
    echo "FFmpeg Rockchip Build Script"
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
    echo "  ANDROID_NDK_HOME      Path to Android NDK (default: ~/sdk/android_ndk/android-ndk-r25c)"
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