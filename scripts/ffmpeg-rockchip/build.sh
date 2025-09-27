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

# 默认构建类型配置
BUILD_TYPE="Release"
BUILD_TYPE_LOWER="release"
BUILD_TYPE_SET="false"
PARSED_TARGET=""

# 记录成功构建的输出目录
declare -a COMPLETED_OUTPUT_DIRS=()

# 限制默认编译目标
_DEFAULT_BUILD_TARGETS="aarch64-linux-gnu,arm-linux-gnueabihf,aarch64-linux-android,arm-linux-android"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 记录初始依赖环境变量，便于在不同目标之间恢复
ORIGINAL_PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"
ORIGINAL_CFLAGS="${CFLAGS:-}"
ORIGINAL_LDFLAGS="${LDFLAGS:-}"
ORIGINAL_RKMPP_PATH="${RKMPP_PATH:-}"
ORIGINAL_RKRGA_PATH="${RKRGA_PATH:-}"
ORIGINAL_LIBDRM_PATH="${LIBDRM_PATH:-}"

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

get_output_dir_for_build_type() {
    local base_dir="$1"

    if [ -z "$base_dir" ]; then
        echo ""
        return 0
    fi

    if [ "$BUILD_TYPE_LOWER" = "debug" ]; then
        echo "${base_dir}-debug"
    else
        echo "$base_dir"
    fi
}

# 检查工具是否存在
check_tool_exists() {
    local tool_name="$1"
    local cross_prefix="$2"
    local tool_path=""
    
    if [ -n "$cross_prefix" ]; then
        tool_path="${cross_prefix}${tool_name}"
        if command -v "$tool_path" &> /dev/null; then
            echo "$tool_path"
            return 0
        fi
    fi
    
    if command -v "$tool_name" &> /dev/null; then
        echo "$tool_name"
        return 0
    fi
    
    return 1
}

# 检查工具列表
check_tools_list() {
    local cross_prefix="$1"
    local tools_string="$2"

    local tools_status=""

    read -ra tools <<< "$tools_string"

    for tool in "${tools[@]}"; do
        local tool_path
        if tool_path=$(check_tool_exists "$tool" "$cross_prefix"); then
            tools_status="${tools_status}${tool}:${tool_path} "
        fi
    done

    echo "$tools_status"
}

# 归一化交叉编译前缀，确保以连字符结尾
normalize_cross_prefix() {
    local prefix="$1"

    if [ -z "$prefix" ]; then
        echo ""
        return 0
    fi

    prefix="$(echo "$prefix" | tr -d '[:space:]')"
    if [ -z "$prefix" ]; then
        echo ""
        return 0
    fi

    if [[ "$prefix" != *- ]]; then
        prefix="${prefix}-"
    fi

    echo "$prefix"
}

# 校验工具路径是否存在并与预期前缀匹配
validate_cross_tool_path() {
    local candidate="$1"
    local expected_prefix="$2"
    local tool_name="$3"

    if [ -z "$candidate" ]; then
        echo ""
        return 1
    fi

    if [[ "$candidate" != /* ]]; then
        candidate="$(command -v "$candidate" 2>/dev/null || true)"
    fi

    if [ -z "$candidate" ] || [ ! -x "$candidate" ]; then
        echo ""
        return 1
    fi

    if [ -n "$expected_prefix" ]; then
        local basename
        basename="$(basename "$candidate")"
        local expected_command="${expected_prefix}${tool_name}"
        if [ "$basename" != "$expected_command" ]; then
            echo ""
            return 1
        fi
    fi

    echo "$candidate"
    return 0
}

find_cross_tool_in_path() {
    local cross_prefix="$1"
    local tool_name="$2"

    if [ -z "$cross_prefix" ]; then
        echo ""
        return 1
    fi

    local resolved
    resolved="$(command -v "${cross_prefix}${tool_name}" 2>/dev/null || true)"
    resolved="$(validate_cross_tool_path "$resolved" "$cross_prefix" "$tool_name")"

    if [ -n "$resolved" ]; then
        echo "$resolved"
        return 0
    fi

    echo ""
    return 1
}

find_cross_tool_in_dirs() {
    local cross_prefix="$1"
    local tool_name="$2"
    shift 2

    if [ -z "$cross_prefix" ]; then
        echo ""
        return 1
    fi

    local candidate
    for dir in "$@"; do
        [ -z "$dir" ] && continue
        candidate="${dir%/}/${cross_prefix}${tool_name}"
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    echo ""
    return 1
}

find_tool_in_dirs() {
    local tool_name="$1"
    shift

    local candidate
    for dir in "$@"; do
        [ -z "$dir" ] && continue
        candidate="${dir%/}/${tool_name}"
        if [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done

    echo ""
    return 1
}

# 检查交叉编译工具是否可用
check_cross_compile_tools() {
    local cross_prefix="$1"
    local target_name="$2"
    local build_dir="$3"
    local toolchain_file="$4"

    log_info "检查 $target_name 的交叉编译工具 (前缀: ${cross_prefix:-'系统默认'})..."

    local tools_status=""
    local strip_cmd=""
    local objcopy_cmd=""
    local cmake_cache=""
    local compiler_dir=""
    local cache_strip=""
    local cache_objcopy=""

    if [ -n "$build_dir" ]; then
        cmake_cache="${build_dir%/}/CMakeCache.txt"
        if [ -f "$cmake_cache" ]; then
            cache_strip=$(sed -n 's/^CMAKE_STRIP:FILEPATH=//p' "$cmake_cache" | head -n1)
            strip_cmd=$(validate_cross_tool_path "$cache_strip" "$cross_prefix" "strip")

            cache_objcopy=$(sed -n 's/^CMAKE_OBJCOPY:FILEPATH=//p' "$cmake_cache" | head -n1)
            objcopy_cmd=$(validate_cross_tool_path "$cache_objcopy" "$cross_prefix" "objcopy")

            local cache_compiler
            cache_compiler=$(sed -n 's/^CMAKE_C_COMPILER:FILEPATH=//p' "$cmake_cache" | head -n1)
            if [ -n "$cache_compiler" ]; then
                compiler_dir="$(dirname "$cache_compiler")"
            fi
        fi
    fi

    local candidate_dirs=()
    [ -n "$compiler_dir" ] && candidate_dirs+=("$compiler_dir")
    if [ -n "$TOOLCHAIN_ROOT_DIR" ]; then
        candidate_dirs+=("$TOOLCHAIN_ROOT_DIR/bin" "$TOOLCHAIN_ROOT_DIR/usr/bin")
    fi
    if [ -n "$TOOLCHAIN" ]; then
        candidate_dirs+=("$TOOLCHAIN/bin" "$TOOLCHAIN")
    fi
    if [ -n "$TOOLCHAIN_BIN_DIR" ]; then
        candidate_dirs+=("$TOOLCHAIN_BIN_DIR")
    fi
    if [ -n "$toolchain_file" ]; then
        local tf_dir
        tf_dir="$(dirname "$toolchain_file")"
        candidate_dirs+=("$tf_dir" "$tf_dir/bin" "$(dirname "$tf_dir")/bin")
    fi

    if [ -z "$cross_prefix" ] && [ -n "$CROSS_COMPILE" ]; then
        cross_prefix="$(normalize_cross_prefix "$CROSS_COMPILE")"
    fi

    cross_prefix="$(normalize_cross_prefix "$cross_prefix")"

    if [ -z "$strip_cmd" ]; then
        strip_cmd=$(find_cross_tool_in_path "$cross_prefix" "strip")
    fi
    if [ -z "$objcopy_cmd" ]; then
        objcopy_cmd=$(find_cross_tool_in_path "$cross_prefix" "objcopy")
    fi

    if [ -z "$strip_cmd" ]; then
        strip_cmd=$(find_cross_tool_in_dirs "$cross_prefix" "strip" "${candidate_dirs[@]}")
    fi
    if [ -z "$objcopy_cmd" ]; then
        objcopy_cmd=$(find_cross_tool_in_dirs "$cross_prefix" "objcopy" "${candidate_dirs[@]}")
    fi

    if [ -z "$strip_cmd" ]; then
        local llvm_strip
        llvm_strip=$(command -v llvm-strip 2>/dev/null || true)
        if [ -z "$llvm_strip" ]; then
            llvm_strip=$(find_tool_in_dirs "llvm-strip" "${candidate_dirs[@]}")
        fi
        strip_cmd=$(validate_cross_tool_path "$llvm_strip" "" "llvm-strip")
    fi

    if [ -z "$objcopy_cmd" ]; then
        local llvm_objcopy
        llvm_objcopy=$(command -v llvm-objcopy 2>/dev/null || true)
        if [ -z "$llvm_objcopy" ]; then
            llvm_objcopy=$(find_tool_in_dirs "llvm-objcopy" "${candidate_dirs[@]}")
        fi
        objcopy_cmd=$(validate_cross_tool_path "$llvm_objcopy" "" "llvm-objcopy")
    fi

    if [ -z "$strip_cmd" ] && [ -n "$cache_strip" ]; then
        strip_cmd=$(validate_cross_tool_path "$cache_strip" "" "strip")
    fi
    if [ -z "$objcopy_cmd" ] && [ -n "$cache_objcopy" ]; then
        objcopy_cmd=$(validate_cross_tool_path "$cache_objcopy" "" "objcopy")
    fi

    if [ -n "$strip_cmd" ]; then
        tools_status+="strip:$strip_cmd "
    fi

    if [ -n "$objcopy_cmd" ]; then
        tools_status+="objcopy:$objcopy_cmd "
    fi

    for tool in upx xz gzip; do
        if command -v "$tool" &> /dev/null; then
            tools_status="${tools_status}${tool}:${tool} "
        fi
    done

    echo "$tools_status"
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

# 检查依赖是否已构建
check_dependency_built() {
    local target="$1"
    local dependency="$2"
    local dependency_dir="${OUTPUTS_DIR}/${dependency}/${target}"

    dependency_dir=$(get_output_dir_for_build_type "$dependency_dir")
    
    # 检查依赖目录是否存在且包含必要的文件
    if [ -d "$dependency_dir" ]; then
        case "$dependency" in
            "rkmpp")
                if [ -f "$dependency_dir/lib/pkgconfig/rockchip_mpp.pc" ]; then
                    return 0
                fi
                ;;
            "rkrga")
                if [ -f "$dependency_dir/lib/pkgconfig/librga.pc" ]; then
                    return 0
                fi
                ;;
            "libdrm")
                if [ -f "$dependency_dir/lib/pkgconfig/libdrm.pc" ]; then
                    return 0
                fi
                ;;
        esac
    fi
    
    return 1
}

# 构建依赖
build_dependency() {
    local target="$1"
    local dependency="$2"
    
    log_info "Building $dependency for target: $target"
    
    # 修正路径计算：使用脚本目录的父目录
    local build_script="${SCRIPT_DIR}/../${dependency}/build.sh"
    
    # 检查构建脚本是否存在
    if [ ! -f "$build_script" ]; then
        log_error "Build script not found: $build_script"
        return 1
    fi
    
    # 检查脚本是否可执行
    if [ ! -x "$build_script" ]; then
        chmod +x "$build_script"
    fi
    
    # 执行构建脚本，透传目标参数
    log_info "Executing: $build_script --build_type $BUILD_TYPE $target"
    if "$build_script" --build_type "$BUILD_TYPE" "$target"; then
        log_success "$dependency build completed successfully for $target"
        return 0
    else
        log_error "Failed to build $dependency for $target"
        return 1
    fi
}

# 恢复依赖相关环境变量，避免不同目标之间交叉污染
reset_dependency_env() {
    if [ -n "$ORIGINAL_PKG_CONFIG_PATH" ]; then
        export PKG_CONFIG_PATH="$ORIGINAL_PKG_CONFIG_PATH"
    else
        unset PKG_CONFIG_PATH
    fi

    if [ -n "$ORIGINAL_CFLAGS" ]; then
        export CFLAGS="$ORIGINAL_CFLAGS"
    else
        unset CFLAGS
    fi

    if [ -n "$ORIGINAL_LDFLAGS" ]; then
        export LDFLAGS="$ORIGINAL_LDFLAGS"
    else
        unset LDFLAGS
    fi

    if [ -n "$ORIGINAL_RKMPP_PATH" ]; then
        export RKMPP_PATH="$ORIGINAL_RKMPP_PATH"
    else
        unset RKMPP_PATH
    fi

    if [ -n "$ORIGINAL_RKRGA_PATH" ]; then
        export RKRGA_PATH="$ORIGINAL_RKRGA_PATH"
    else
        unset RKRGA_PATH
    fi

    if [ -n "$ORIGINAL_LIBDRM_PATH" ]; then
        export LIBDRM_PATH="$ORIGINAL_LIBDRM_PATH"
    else
        unset LIBDRM_PATH
    fi
}

# 检查并构建所有依赖
check_and_build_dependencies() {
    local target="$1"
    
    reset_dependency_env

    log_info "Checking dependencies for target: $target"
    
    local dependencies=("rkmpp" "rkrga" "libdrm")
    local all_dependencies_built=true
    
    # 首先检查所有依赖是否都已构建
    for dependency in "${dependencies[@]}"; do
        if ! check_dependency_built "$target" "$dependency"; then
            all_dependencies_built=false
            break
        fi
    done
    
    # 如果所有依赖都已构建，直接返回
    if [ "$all_dependencies_built" = true ]; then
        log_success "All dependencies already built for $target"
        return 0
    fi
    
    # 构建缺失的依赖
    for dependency in "${dependencies[@]}"; do
        if ! check_dependency_built "$target" "$dependency"; then
            log_warning "$dependency dependency not found for $target, building..."
            if ! build_dependency "$target" "$dependency"; then
                log_error "Failed to build $dependency, exiting"
                exit 1
            fi
        else
            log_success "$dependency dependency already built for $target"
        fi
    done
    
    log_success "All dependencies built successfully for $target"
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

    rkmpp_dir=$(get_output_dir_for_build_type "$rkmpp_dir")
    rkrga_dir=$(get_output_dir_for_build_type "$rkrga_dir")
    libdrm_dir=$(get_output_dir_for_build_type "$libdrm_dir")
    
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
    local pkg_paths="${RKMPP_PATH}/lib/pkgconfig:${RKRGA_PATH}/lib/pkgconfig:${LIBDRM_PATH}/lib/pkgconfig"
    if [ -n "$PKG_CONFIG_PATH" ]; then
        export PKG_CONFIG_PATH="${pkg_paths}:${PKG_CONFIG_PATH}"
    else
        export PKG_CONFIG_PATH="$pkg_paths"
    fi

    local extra_cflags="-I${RKMPP_PATH}/include -I${RKRGA_PATH}/include -I${LIBDRM_PATH}/include -DHAVE_SYSCTL=0"
    if [ -n "$CFLAGS" ]; then
        export CFLAGS="${extra_cflags} ${CFLAGS}"
    else
        export CFLAGS="$extra_cflags"
    fi

    local extra_ldflags="-L${RKMPP_PATH}/lib -L${RKRGA_PATH}/lib -L${LIBDRM_PATH}/lib"
    if [ -n "$LDFLAGS" ]; then
        export LDFLAGS="${extra_ldflags} ${LDFLAGS}"
    else
        export LDFLAGS="$extra_ldflags"
    fi
    
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

    if [ -z "$cross_prefix" ] && [ -n "$CROSS_COMPILE" ]; then
        cross_prefix="$CROSS_COMPILE"
    fi

    echo "$(normalize_cross_prefix "$cross_prefix")"
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
    
    # 检查并构建依赖
    if ! check_and_build_dependencies "$target_name"; then
        log_error "Failed to build dependencies for $target_name"
        return 1
    fi
    
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

    if [ "$BUILD_TYPE_LOWER" = "debug" ]; then
        CONFIGURE_CMD="$CONFIGURE_CMD --enable-debug"
    fi
    
    # 添加RockChip配置选项
    local RK_ONLY_OPTIONS
    RK_ONLY_OPTIONS=$(get_rk_only_options)
    CONFIGURE_CMD="$CONFIGURE_CMD $RK_ONLY_OPTIONS"
    
    # 配置
    log_info "Configuring FFmpeg for $target_name..."
    log_info "Configure command: $CONFIGURE_CMD"

    if ! eval "$CONFIGURE_CMD"; then
        log_error "Configure failed for $target_name"
        log_error "Check ffbuild/config.log for detailed error information"
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
    
    # 压缩库文件
    if [ "$BUILD_TYPE_LOWER" = "debug" ]; then
        log_info "Debug build type detected, skipping library compression"
    else
        if [[ "$target_name" == *"-android" ]]; then
            compress_android_libraries "$output_dir" "$target_name" "$FFMPEG_SOURCE_DIR"
        else
            local cross_prefix
            cross_prefix=$(get_cross_tools "$target_name")
            local available_tools
            available_tools=$(check_cross_compile_tools "$cross_prefix" "$target_name" "$FFMPEG_SOURCE_DIR" "")
            compress_libraries "$output_dir" "$target_name" "$available_tools"
        fi
    fi
    
    # 返回到工作目录
    cd "$WORKSPACE_DIR"
    
    return 0
}

# 构建单个目标
build_target() {
    local target_name="$1"
    local base_output_dir="$2"
    local build_status=0

    local output_dir
    output_dir=$(get_output_dir_for_build_type "$base_output_dir")

    trap 'reset_dependency_env' RETURN
    reset_dependency_env
    
    log_info "Building target: $target_name"
    log_info "Resolved output directory: $output_dir"
    
    # 检查并构建依赖
    if ! check_and_build_dependencies "$target_name"; then
        log_error "Failed to build dependencies for $target_name"
        return 1
    fi
    
    # 检查是否为Android目标
    if [[ "$target_name" == *"-android" ]]; then
        # Android目标使用专门的构建函数
        if build_android_target "$target_name" "$output_dir"; then
            COMPLETED_OUTPUT_DIRS+=("$output_dir")
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
        build_status=0
    else
        build_status=1
    fi

    if [ $build_status -eq 0 ]; then
        COMPLETED_OUTPUT_DIRS+=("$output_dir")
    fi

    return $build_status
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
            -c|--clean)
                cleanup
                exit 0
                ;;
            --clean-all)
                clean_all
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

# 压缩单个库文件
compress_single_library() {
    local lib_file="$1"
    local strip_cmd="$2"
    local objcopy_cmd="$3"
    
    local original_size
    original_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "0")
    
    local final_size=$original_size
    local compression_method="none"
    local compression_applied=false
    
    log_info "  处理: $(basename "$lib_file") (${original_size} 字节)" >&2
    
    # 使用 strip 工具移除符号表
    if [ -n "$strip_cmd" ]; then
        local backup_file="${lib_file}.backup"
        cp "$lib_file" "$backup_file"
        
    log_info "    使用 $strip_cmd 移除符号表..." >&2
        
        # 根据文件类型使用不同的 strip 参数
        if [[ "$lib_file" == *.so* ]]; then
            "$strip_cmd" --strip-unneeded "$lib_file" 2>/dev/null || true
        else
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
            log_success "      移除 ${strip_reduction}% 符号 ($strip_cmd)" >&2
        else
            mv "$backup_file" "$lib_file"
            log_info "      Strip 操作无效" >&2
        fi
    fi
    
    # 使用 objcopy 进一步优化
    if [ -n "$objcopy_cmd" ] && [ "$compression_applied" = "true" ]; then
        log_info "    使用 $objcopy_cmd 优化..." >&2
        if "$objcopy_cmd" --remove-section=.comment --remove-section=.note "$lib_file" 2>/dev/null; then
            local objcopy_size
            objcopy_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "$final_size")
            if [ "$objcopy_size" -lt "$final_size" ]; then
                final_size=$objcopy_size
                compression_method="${compression_method}+objcopy"
                log_info "      objcopy 优化完成" >&2
            fi
        fi
    fi
    
    if [ "$compression_applied" = "true" ]; then
        local total_reduction
        total_reduction=$(( (original_size - final_size) * 100 / original_size ))
        log_success "    最终: $original_size → $final_size 字节 (-${total_reduction}%, ${compression_method#none+})" >&2
    else
        log_info "    未应用压缩" >&2
    fi
    
    echo "$final_size:$compression_applied"
}

# 通用库文件压缩函数
compress_libraries() {
    local output_dir="$1"
    local target_name="$2"
    local available_tools="$3"
    
    log_info "压缩 $target_name 的库文件..."
    
    # 解析可用工具
    local strip_cmd=""
    local objcopy_cmd=""
    
    if [ -n "$available_tools" ]; then
        strip_cmd=$(echo "$available_tools" | grep -o "strip:[^ ]*" | cut -d: -f2)
        objcopy_cmd=$(echo "$available_tools" | grep -o "objcopy:[^ ]*" | cut -d: -f2)
    fi
    
    # 显示可用的工具
    if [ -n "$strip_cmd" ] || [ -n "$objcopy_cmd" ]; then
        log_info "可用压缩工具:"
        [ -n "$strip_cmd" ] && log_info "  Strip: $strip_cmd"
        [ -n "$objcopy_cmd" ] && log_info "  Objcopy: $objcopy_cmd"
    else
        log_warning "未找到可用的压缩工具，跳过压缩"
        return 0
    fi
    
    # 查找所有 .so 和 .a 文件
    local lib_files
    lib_files=$(find "$output_dir" -type f \( -name "*.so*" -o -name "*.a" \) 2>/dev/null || true)
    
    if [ -z "$lib_files" ]; then
        log_warning "在 $output_dir 中未找到库文件"
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
        
        local result
        result=$(compress_single_library "$lib_file" "$strip_cmd" "$objcopy_cmd")
        local final_size="${result%%:*}"
        local compression_applied="${result##*:}"
        
        total_compressed_size=$((total_compressed_size + final_size))
        
        if [ "$compression_applied" = "true" ]; then
            compressed_count=$((compressed_count + 1))
        fi
        
    done <<< "$lib_files"
    
    # 显示压缩统计
    if [ "$compressed_count" -gt 0 ]; then
        local total_reduction
        total_reduction=$(( (total_original_size - total_compressed_size) * 100 / total_original_size ))
        log_success "$target_name 压缩统计:"
        log_success "  处理文件数: $(echo "$lib_files" | wc -l)"
        log_success "  优化文件数: $compressed_count"
        log_success "  总大小: $total_original_size → $total_compressed_size 字节 (-${total_reduction}%)"
    else
        log_info "$target_name 未实现显著压缩 (文件可能已优化)"
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
            log_warning "未知的 Android 架构: $target_name，跳过压缩"
            return 0
            ;;
    esac

    local available_tools
    available_tools=$(check_cross_compile_tools "$cross_prefix" "$target_name" "$build_dir" "")

    compress_libraries "$output_dir" "$target_name" "$available_tools"
}

# 创建版本信息文件
create_version_file() {
    log_info "Creating version.ini file..."
    
    local version_file="${FFMPEG_OUTPUT_DIR}/version.ini"
    local changelog_file="${FFMPEG_SOURCE_DIR}/Changelog"
    
    # 检查Changelog是否存在
    if [ ! -f "$changelog_file" ]; then
        log_warning "Changelog not found: $changelog_file"
        echo "version=unknown" > "$version_file"
        log_warning "Created version.ini with unknown version"
        return 0
    fi
    
    # 提取最新版本号（格式：version 6.1:）
    local latest_version
    latest_version=$(grep -E "^version [0-9]+\.[0-9]+:" "$changelog_file" | head -1 | sed -E 's/^version ([0-9]+\.[0-9]+):.*/\1/')
    
    if [ -z "$latest_version" ]; then
        log_warning "Could not extract version from Changelog"
        echo "version=unknown" > "$version_file"
        log_warning "Created version.ini with unknown version"
        return 0
    fi
    
    # 写入版本信息到version.ini
    cat > "$version_file" << EOF
[version]
version=$latest_version
EOF
    
    log_success "Created version.ini with version: $latest_version"
}

# 主函数
main() {
    local target_to_build="$1"
    
    log_info "Starting FFmpeg Rockchip build process (build type: $BUILD_TYPE)..."
    
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
    
    log_success "Build process completed for build type: $BUILD_TYPE"

    if [ ${#COMPLETED_OUTPUT_DIRS[@]} -gt 0 ]; then
        log_info "Completed output directories:"
        for dir in "${COMPLETED_OUTPUT_DIRS[@]}"; do
            log_info "  - $dir"
        done
    else
        log_warning "No targets were built."
    fi
    
    log_info "Base output directory: $FFMPEG_OUTPUT_DIR"
    
    # 生成version.ini文件
    create_version_file

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
    echo "  -h, --help           Show this help message"
    echo "  -c, --clean          Clean build directories only"
    echo "  --clean-all          Clean all (sources and outputs)"
    echo "  --build_type=TYPE    Build configuration: Release (default) or Debug"
    echo ""
    echo "Environment Variables:"
    echo "  TOOLCHAIN_ROOT_DIR    Path to cross-compilation toolchain (optional)"
    echo "  ANDROID_NDK_HOME      Path to Android NDK (default: ~/sdk/android_ndk/android-ndk-r25c)"
    echo ""
    echo "Examples:"
    echo "  $0                                   # Build default targets (aarch64-linux-gnu, arm-linux-gnueabihf, aarch64-linux-android, arm-linux-android)"
    echo "  $0 --build_type=Debug                 # Build default targets with Debug configuration"
    echo "  $0 aarch64-linux-gnu                  # Build only ARM 64-bit glibc version"
    echo "  $0 aarch64-linux-gnu --build_type=Debug # Build ARM 64-bit glibc version with Debug configuration"
    echo "  $0 --clean                            # Clean build directories"
    echo "  $0 --clean-all                        # Clean everything"
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
        parse_arguments "$@"
        main "$PARSED_TARGET"
        ;;
esac