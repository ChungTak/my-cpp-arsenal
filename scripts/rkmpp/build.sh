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

# 默认构建类型设置
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
NC='\033[0m' # No Color

# 日志函数
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

# 错误处理函数
handle_error() {
    local message="$1"
    local exit_code="${2:-1}"
    log_error "$message"
    exit $exit_code
}

# 检查命令执行结果
check_command_result() {
    local result=$1
    local message="$2"
    if [ $result -ne 0 ]; then
        handle_error "$message" $result
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
    
    # 将空格分隔的工具字符串转换为数组
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

    # 去除所有空白字符
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

# 设置构建类型参数
set_build_type_from_arg() {
    local input="$1"

    if [ -z "$input" ]; then
        log_error "--build_type requires a value (Debug or Release)"
        exit 1
    fi

    local normalized
    normalized=$(echo "$input" | tr '[:upper:]' '[:lower:]')

    case "$normalized" in
        debug)
            BUILD_TYPE="Debug"
            BUILD_TYPE_LOWER="debug"
            ;;
        release)
            BUILD_TYPE="Release"
            BUILD_TYPE_LOWER="release"
            ;;
        *)
            log_error "Invalid build type: $input (valid: Debug, Release)"
            exit 1
            ;;
    esac

    BUILD_TYPE_SET="true"
    log_info "已选择构建类型: $BUILD_TYPE" >&2
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

    # 如果是相对路径，尝试解析
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

# 在 PATH 中查找交叉编译工具
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

# 在候选目录中查找交叉编译工具
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

    # 从 CMakeCache.txt 中提取工具路径
    if [ -n "$build_dir" ]; then
        cmake_cache="${build_dir%/}/CMakeCache.txt"
        if [ -f "$cmake_cache" ]; then
            local cache_strip
            cache_strip=$(sed -n 's/^CMAKE_STRIP:FILEPATH=//p' "$cmake_cache" | head -n1)
            strip_cmd=$(validate_cross_tool_path "$cache_strip" "$cross_prefix" "strip")

            local cache_objcopy
            cache_objcopy=$(sed -n 's/^CMAKE_OBJCOPY:FILEPATH=//p' "$cmake_cache" | head -n1)
            objcopy_cmd=$(validate_cross_tool_path "$cache_objcopy" "$cross_prefix" "objcopy")

            local cache_compiler
            cache_compiler=$(sed -n 's/^CMAKE_C_COMPILER:FILEPATH=//p' "$cmake_cache" | head -n1)
            if [ -n "$cache_compiler" ]; then
                compiler_dir="$(dirname "$cache_compiler")"
            fi
        fi
    fi

    # 构建候选目录列表
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

    # 允许通过环境变量 CROSS_COMPILE 提供后备前缀
    if [ -z "$cross_prefix" ] && [ -n "$CROSS_COMPILE" ]; then
        cross_prefix="$(normalize_cross_prefix "$CROSS_COMPILE")"
    fi

    # 综合搜索 strip 与 objcopy
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

    # 如果 CMakeCache 中的工具未匹配前缀，允许作为最终兜底
    if [ -z "$strip_cmd" ]; then
        strip_cmd=$(validate_cross_tool_path "$cache_strip" "" "strip")
    fi
    if [ -z "$objcopy_cmd" ]; then
        objcopy_cmd=$(validate_cross_tool_path "$cache_objcopy" "" "objcopy")
    fi
    
    if [ -n "$strip_cmd" ]; then
        tools_status+="strip:$strip_cmd "
    fi

    if [ -n "$objcopy_cmd" ]; then
        tools_status+="objcopy:$objcopy_cmd "
    fi
    
    # 检查通用压缩工具
    for tool in upx xz gzip; do
        if command -v "$tool" &> /dev/null; then
            tools_status="${tools_status}${tool}:${tool} "
        fi
    done
    
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
        # 使用 sed 提取前缀，支持带引号和不带引号的格式
        local prefix
        # 匹配格式: set( CROSS_COMPILE aarch64-linux-gnu- ) 或 set(CROSS_COMPILE "aarch64-linux-gnu-")
        prefix=$(echo "$cross_compile_line" | sed -E 's/.*set\s*\(\s*CROSS_COMPILE\s+["]?([a-zA-Z0-9_-]+)-["]?\s*\).*/\1/')
        
        if [ -n "$prefix" ] && [ "$prefix" != "$cross_compile_line" ]; then
            normalize_cross_prefix "$prefix"
        else
            echo ""
        fi
    else
        # 如果未找到，返回空字符串（使用系统默认工具）
        echo ""
    fi
}

# 通用构建函数
build_target_common() {
    local target_name="$1"
    local toolchain_file="$2"
    local output_dir="$3"
    local is_android="$4"
    
    log_info "构建目标: $target_name..."
    
    # 创建输出目录
    mkdir -p "$output_dir"
    
    # 创建构建目录
    local build_dir="${MPP_SOURCE_DIR}/build_${target_name}"
    if [ "$is_android" = "true" ]; then
        build_dir="${MPP_SOURCE_DIR}/build/build_${target_name}"
    fi
    
    rm -rf "$build_dir"  # 清理旧的构建目录
    mkdir -p "$build_dir"
    
    # 进入构建目录
    cd "$build_dir"
    
    # 配置CMake参数
    local cmake_args=()
    if [ "$is_android" = "true" ]; then
        # Android构建参数
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
        # 普通交叉编译参数
        cmake_args+=(
            -DCMAKE_TOOLCHAIN_FILE="$toolchain_file"
        )
    fi
    
    cmake_args+=(
        "-DCMAKE_BUILD_TYPE=$BUILD_TYPE"
        "-DCMAKE_INSTALL_PREFIX=$output_dir"
        -DBUILD_SHARED_LIBS=ON
        -DBUILD_TEST=OFF
    )
    
    # 配置CMake
    if [ "$is_android" = "true" ]; then
        cmake ../.. "${cmake_args[@]}"
    else
        cmake .. "${cmake_args[@]}"
    fi
    
    check_command_result $? "CMake configuration failed for $target_name"
    
    # 编译
    make -j$(nproc)
    check_command_result $? "Build failed for $target_name"
    
    # 安装
    make install
    check_command_result $? "Install failed for $target_name"
    
    log_success "$target_name 构建完成"
    
    # 压缩库文件（仅在 Release 构建时执行）
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
            compress_libraries "$output_dir" "$target_name" "$available_tools"
        fi
    else
        log_info "Debug 构建类型，跳过库压缩"
    fi
    
    # 返回到工作目录
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

    compress_libraries "$output_dir" "$target_name" "$available_tools"
}

# 编译函数
build_target() {
    local target_name="$1"
    local toolchain_file="$2"
    local output_dir="$3"
    build_target_common "$target_name" "$toolchain_file" "$output_dir" "false"
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
            echo "arm-linux-gnueabihf:${TOOLCHAIN_DIR}/arm-linux-gnueabihf.cmake:${RKMPP_OUTPUT_DIR}/arm-linux-gnueabihf"
            ;;
        "aarch64-linux-gnu")
            echo "aarch64-linux-gnu:${TOOLCHAIN_DIR}/aarch64-linux-gnu.cmake:${RKMPP_OUTPUT_DIR}/aarch64-linux-gnu"
            ;;
        "arm-linux-musleabihf")
            echo "arm-linux-musleabihf:${TOOLCHAIN_DIR}/arm-linux-musleabihf.cmake:${RKMPP_OUTPUT_DIR}/arm-linux-musleabihf"
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

# 根据构建类型返回实际输出目录
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

# 获取默认编译目标列表
get_default_build_targets() {
    # 如果私有变量不存在或为空，返回所有目标的配置
    if [ -z "$_DEFAULT_BUILD_TARGETS" ]; then
        # 所有目标的配置
        echo "arm-linux-gnueabihf:${TOOLCHAIN_DIR}/arm-linux-gnueabihf.cmake:${RKMPP_OUTPUT_DIR}/arm-linux-gnueabihf"
        echo "aarch64-linux-gnu:${TOOLCHAIN_DIR}/aarch64-linux-gnu.cmake:${RKMPP_OUTPUT_DIR}/aarch64-linux-gnu"
        echo "arm-linux-musleabihf:${TOOLCHAIN_DIR}/arm-linux-musleabihf.cmake:${RKMPP_OUTPUT_DIR}/arm-linux-musleabihf"
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
    
    log_info "开始 RK MPP 构建过程..."
    log_info "当前构建类型: $BUILD_TYPE"
    
    # 检查工具
    check_tools
    
    # 克隆源码
    clone_mpp
    
    # 创建输出目录
    mkdir -p "$RKMPP_OUTPUT_DIR"
    
    if [ -n "$target_to_build" ]; then
        build_single_target "$target_to_build"
    else
        build_multiple_targets
    fi
    
    log_success "构建过程完成!"
    log_info "输出目录: $RKMPP_OUTPUT_DIR"
    
    # 生成version.ini文件
    create_version_file

    # 显示目录结构
    log_info "目录结构:"
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
    echo "  -h, --help             Show this help message"
    echo "  -c, --clean            Clean build directories only"
    echo "  --clean-all            Clean all (sources and outputs)"
    echo "  --build_type=TYPE      Specify CMake build type (Debug or Release, default: Release)"
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
    echo "  $0 --build_type Debug aarch64-linux-gnu  # Build Debug variant for ARM64"
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
        parse_arguments "$@"
        main "$PARSED_TARGET"
        ;;
esac

