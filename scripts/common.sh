#!/bin/bash

# Shared helpers for build scripts
# shellcheck disable=SC2034

if [[ -n "${__BUILD_COMMON_LOADED:-}" ]]; then
    return 0
fi
__BUILD_COMMON_LOADED=1

# -------------------------
# Logging helpers
# -------------------------
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

reset_build_type_state() {
    BUILD_TYPE="Release"
    BUILD_TYPE_LOWER="release"
    BUILD_TYPE_SET="false"
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
            if [ "${BUILD_TYPE_SET:-false}" = "true" ] && [ "${BUILD_TYPE_LOWER:-}" != "debug" ]; then
                log_error "Conflicting build type arguments detected"
                exit 1
            fi
            BUILD_TYPE="Debug"
            BUILD_TYPE_LOWER="debug"
            BUILD_TYPE_SET="true"
            ;;
        release)
            if [ "${BUILD_TYPE_SET:-false}" = "true" ] && [ "${BUILD_TYPE_LOWER:-}" != "release" ]; then
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

    if [ "${BUILD_TYPE_LOWER:-release}" = "debug" ]; then
        echo "${base_dir}-debug"
    else
        echo "$base_dir"
    fi
}

split_csv_to_lines() {
    local csv="$1"
    local delimiter="${2:-,}"

    if [ -z "$csv" ]; then
        return 0
    fi

    IFS="$delimiter" read -ra values <<< "$csv"
    for item in "${values[@]}"; do
        item="${item//[[:space:]]/}"
        [ -z "$item" ] && continue
        printf '%s\n' "$item"
    done
}

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

_detect_ndk_toolchain_dir() {
    local ndk_root="${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}"
    [ -z "$ndk_root" ] && return 1
    [ ! -d "$ndk_root" ] && return 1

    local host_os
    host_os=$(uname -s | tr '[:upper:]' '[:lower:]')
    local host_arch
    host_arch=$(uname -m)
    case "$host_arch" in
        x86_64|amd64)
            host_arch="x86_64"
            ;;
        arm64|aarch64)
            host_arch="arm64"
            ;;
        *)
            host_arch="x86_64"
            ;;
    esac

    local candidate="${ndk_root}/toolchains/llvm/prebuilt/${host_os}-${host_arch}"
    if [ -d "$candidate/bin" ]; then
        printf '%s' "$candidate"
        return 0
    fi

    for fallback in "${ndk_root}/toolchains/llvm/prebuilt/linux-x86_64" \
                    "${ndk_root}/toolchains/llvm/prebuilt/darwin-x86_64" \
                    "${ndk_root}/toolchains/llvm/prebuilt/darwin-arm64"; do
        if [ -d "$fallback/bin" ]; then
            printf '%s' "$fallback"
            return 0
        fi
    done

    return 1
}

check_cross_compile_tools() {
    local cross_prefix="$1"
    local target_name="${2:-}"
    local build_dir="${3:-}"
    local toolchain_file="${4:-}"
    shift 4 || true
    local extra_dirs=("$@")

    log_info "检查 ${target_name:-unknown} 的交叉编译工具 (前缀: ${cross_prefix:-'系统默认'})..."

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
            strip_cmd="$(validate_cross_tool_path "$cache_strip" "$cross_prefix" "strip")"

            cache_objcopy=$(sed -n 's/^CMAKE_OBJCOPY:FILEPATH=//p' "$cmake_cache" | head -n1)
            objcopy_cmd="$(validate_cross_tool_path "$cache_objcopy" "$cross_prefix" "objcopy")"

            local cache_compiler
            cache_compiler=$(sed -n 's/^CMAKE_C_COMPILER:FILEPATH=//p' "$cmake_cache" | head -n1)
            if [ -n "$cache_compiler" ]; then
                compiler_dir="$(dirname "$cache_compiler")"
            fi
        fi
    fi

    local candidate_dirs=()
    [ -n "$compiler_dir" ] && candidate_dirs+=("$compiler_dir")
    if [ -n "${TOOLCHAIN_ROOT_DIR:-}" ]; then
        candidate_dirs+=("${TOOLCHAIN_ROOT_DIR}/bin" "${TOOLCHAIN_ROOT_DIR}/usr/bin")
    fi
    if [ -n "${TOOLCHAIN:-}" ]; then
        candidate_dirs+=("${TOOLCHAIN}/bin" "$TOOLCHAIN")
    fi
    if [ -n "${TOOLCHAIN_BIN_DIR:-}" ]; then
        candidate_dirs+=("$TOOLCHAIN_BIN_DIR")
    fi
    if [ -n "$toolchain_file" ]; then
        local tf_dir
        tf_dir="$(dirname "$toolchain_file")"
        candidate_dirs+=("$tf_dir" "${tf_dir}/bin" "$(dirname "$tf_dir")/bin")
    fi
    if [ ${#extra_dirs[@]} -gt 0 ]; then
        candidate_dirs+=("${extra_dirs[@]}")
    fi

    cross_prefix="$(normalize_cross_prefix "$cross_prefix")"

    if [ -z "$cross_prefix" ] && [ -n "${CROSS_COMPILE:-}" ]; then
        cross_prefix="$(normalize_cross_prefix "$CROSS_COMPILE")"
    fi

    if [[ "${target_name:-}" == *"-android" ]]; then
        local ndk_toolchain
        if ndk_toolchain="$(_detect_ndk_toolchain_dir)"; then
            candidate_dirs=("${ndk_toolchain}/bin" "${candidate_dirs[@]}")
            if [ -z "$strip_cmd" ] && [ -x "${ndk_toolchain}/bin/llvm-strip" ]; then
                strip_cmd="${ndk_toolchain}/bin/llvm-strip"
            fi
            if [ -z "$objcopy_cmd" ] && [ -x "${ndk_toolchain}/bin/llvm-objcopy" ]; then
                objcopy_cmd="${ndk_toolchain}/bin/llvm-objcopy"
            fi
        fi
    fi

    if [ -z "$strip_cmd" ]; then
        strip_cmd="$(find_cross_tool_in_path "$cross_prefix" "strip")"
    fi
    if [ -z "$objcopy_cmd" ]; then
        objcopy_cmd="$(find_cross_tool_in_path "$cross_prefix" "objcopy")"
    fi

    if [ -z "$strip_cmd" ]; then
        strip_cmd="$(find_cross_tool_in_dirs "$cross_prefix" "strip" "${candidate_dirs[@]}")"
    fi
    if [ -z "$objcopy_cmd" ]; then
        objcopy_cmd="$(find_cross_tool_in_dirs "$cross_prefix" "objcopy" "${candidate_dirs[@]}")"
    fi

    if [ -z "$strip_cmd" ]; then
        local llvm_strip
        llvm_strip="$(command -v llvm-strip 2>/dev/null || true)"
        if [ -z "$llvm_strip" ]; then
            llvm_strip="$(find_tool_in_dirs "llvm-strip" "${candidate_dirs[@]}")"
        fi
        strip_cmd="$(validate_cross_tool_path "$llvm_strip" "" "llvm-strip")"
    fi

    if [ -z "$objcopy_cmd" ]; then
        local llvm_objcopy
        llvm_objcopy="$(command -v llvm-objcopy 2>/dev/null || true)"
        if [ -z "$llvm_objcopy" ]; then
            llvm_objcopy="$(find_tool_in_dirs "llvm-objcopy" "${candidate_dirs[@]}")"
        fi
        objcopy_cmd="$(validate_cross_tool_path "$llvm_objcopy" "" "objcopy")"
    fi

    if [ -z "$strip_cmd" ] && [ -n "$cache_strip" ]; then
        strip_cmd="$(validate_cross_tool_path "$cache_strip" "" "strip")"
    fi
    if [ -z "$objcopy_cmd" ] && [ -n "$cache_objcopy" ]; then
        objcopy_cmd="$(validate_cross_tool_path "$cache_objcopy" "" "objcopy")"
    fi

    if [ -n "$strip_cmd" ]; then
        tools_status+="strip:$strip_cmd "
    fi
    if [ -n "$objcopy_cmd" ]; then
        tools_status+="objcopy:$objcopy_cmd "
    fi

    for tool in upx xz gzip; do
        if command -v "$tool" &> /dev/null; then
            tools_status+="${tool}:${tool} "
        fi
    done

    echo "$tools_status"
}