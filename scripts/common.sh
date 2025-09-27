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

ensure_tools_available() {
    if [ $# -eq 0 ]; then
        return 0
    fi

    local missing=()
    local tool
    for tool in "$@"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing required tool(s): ${missing[*]}"
        exit 1
    fi
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

    if [ -z "$ndk_root" ]; then
        local default_ndk_root="$HOME/sdk/android_ndk"
        if [ -d "$default_ndk_root" ]; then
            local newest_ndk
            newest_ndk=$(find "$default_ndk_root" -maxdepth 1 -mindepth 1 -type d -name 'android-ndk-*' | sort -V | tail -n1 || true)
            if [ -n "$newest_ndk" ]; then
                ndk_root="$newest_ndk"
                export ANDROID_NDK_HOME="$ndk_root"
            fi
        fi
    fi

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

apply_meson_clockskew_patch() {
    local patch_script

    if [ -z "${WORKSPACE_DIR:-}" ]; then
        log_warning "WORKSPACE_DIR is not set; skipping meson clockskew patch"
        return 0
    fi

    patch_script="${WORKSPACE_DIR}/patches/patch_meson_clockskew.py"

    log_info "Applying meson clockskew patch..."

    if [ ! -f "$patch_script" ]; then
        log_warning "Meson clockskew patch script not found: $patch_script"
        log_warning "Compilation may fail due to clock skew issues"
        return 0
    fi

    if python3 "$patch_script"; then
        log_success "Meson clockskew patch applied successfully"
    else
        log_warning "Failed to apply meson clockskew patch"
        log_warning "Compilation may fail due to clock skew issues"
    fi
}

compress_artifacts_in_dir() {
    local output_dir="$1"
    local target_name="$2"
    local available_tools="$3"
    shift 3 || true

    local locale="en"
    local allow_upx=false
    local allow_xz=false
    local allow_gzip=false
    local print_details=false
    local summary_label=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --allow-upx)
                allow_upx=true
                ;;
            --allow-xz)
                allow_xz=true
                ;;
            --allow-gzip)
                allow_gzip=true
                ;;
            --print-details)
                print_details=true
                ;;
            --summary-label)
                summary_label="$2"
                shift
                ;;
            --locale)
                locale="$2"
                shift
                ;;
            *)
                log_warning "Unknown compression option: $1"
                ;;
        esac
        shift
    done

    local strip_cmd=""
    local objcopy_cmd=""
    local upx_cmd=""
    local xz_cmd=""
    local gzip_cmd=""

    for entry in $available_tools; do
        case "$entry" in
            strip:*)
                strip_cmd="${entry#strip:}"
                ;;
            objcopy:*)
                objcopy_cmd="${entry#objcopy:}"
                ;;
            upx:*)
                upx_cmd="${entry#upx:}"
                ;;
            xz:*)
                xz_cmd="${entry#xz:}"
                ;;
            gzip:*)
                gzip_cmd="${entry#gzip:}"
                ;;
        esac
    done

    [[ "$allow_upx" != "true" ]] && upx_cmd=""
    [[ "$allow_xz" != "true" ]] && xz_cmd=""
    [[ "$allow_gzip" != "true" ]] && gzip_cmd=""

    if [ -z "$strip_cmd" ] && [ -z "$objcopy_cmd" ] && [ -z "$upx_cmd" ] && [ -z "$xz_cmd" ] && [ -z "$gzip_cmd" ]; then
        if [ "$locale" = "zh" ]; then
            log_warning "未找到可用的压缩工具，跳过压缩"
        else
            log_warning "No compression tools available for $target_name"
        fi
        return 0
    fi

    if [ "$locale" = "zh" ]; then
        log_info "可用压缩工具:"
        [ -n "$strip_cmd" ] && log_info "  Strip: $strip_cmd"
        [ -n "$objcopy_cmd" ] && log_info "  Objcopy: $objcopy_cmd"
        [ -n "$upx_cmd" ] && log_info "  UPX: $upx_cmd"
        [ -n "$xz_cmd" ] && log_info "  XZ: $xz_cmd"
        [ -n "$gzip_cmd" ] && log_info "  GZIP: $gzip_cmd"
    else
        log_info "Available compression tools:"
        [ -n "$strip_cmd" ] && log_info "  Strip: $strip_cmd"
        [ -n "$objcopy_cmd" ] && log_info "  Objcopy: $objcopy_cmd"
        [ -n "$upx_cmd" ] && log_info "  UPX: $upx_cmd"
        [ -n "$xz_cmd" ] && log_info "  XZ: $xz_cmd"
        [ -n "$gzip_cmd" ] && log_info "  GZIP: $gzip_cmd"
    fi

    local lib_files
    lib_files=$(find "$output_dir" -type f \( -name "*.so*" -o -name "*.a" \) 2>/dev/null || true)

    if [ -z "$lib_files" ]; then
        if [ "$locale" = "zh" ]; then
            log_warning "在 $output_dir 中未找到库文件"
        else
            log_warning "No library files found in $output_dir"
        fi
        return 0
    fi

    local total_original_size=0
    local total_compressed_size=0
    local compressed_count=0
    local total_files=0
    local details=()

    while IFS= read -r lib_file; do
        [ -z "$lib_file" ] && continue
        total_files=$((total_files + 1))

        local original_size
        original_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "0")
        total_original_size=$((total_original_size + original_size))

        if [ "$locale" = "zh" ]; then
            log_info "  处理: $(basename "$lib_file") (${original_size} 字节)"
        else
            log_info "  Processing: $(basename "$lib_file") (${original_size} bytes)"
        fi

        local final_size=$original_size
        local compression_applied=false

        if [ -n "$strip_cmd" ]; then
            if [ "$locale" = "zh" ]; then
                log_info "    使用 $strip_cmd 移除符号表..."
            else
                log_info "    Using $strip_cmd to strip symbols..."
            fi

            local backup_file="${lib_file}.backup"
            cp "$lib_file" "$backup_file"

            if [[ "$lib_file" == *.so* ]]; then
                "$strip_cmd" --strip-unneeded "$lib_file" 2>/dev/null || true
            else
                "$strip_cmd" --strip-debug "$lib_file" 2>/dev/null || true
            fi

            local stripped_size
            stripped_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "$original_size")

            if [ "$stripped_size" -lt "$original_size" ]; then
                final_size=$stripped_size
                compression_applied=true
                rm -f "$backup_file"
                if [ "$original_size" -gt 0 ]; then
                    local strip_reduction
                    strip_reduction=$(((original_size - stripped_size) * 100 / original_size))
                    if [ "$locale" = "zh" ]; then
                        log_success "      移除 ${strip_reduction}% 符号 ($strip_cmd)"
                    else
                        log_success "      Stripped ${strip_reduction}% of symbols ($strip_cmd)"
                    fi
                fi
            else
                mv "$backup_file" "$lib_file"
                if [ "$locale" = "zh" ]; then
                    log_info "      Strip 操作无效"
                else
                    log_info "      Strip had no effect"
                fi
            fi
        fi

        if [ -n "$upx_cmd" ] && [[ "$lib_file" == *.so* ]]; then
            if [ "$locale" = "zh" ]; then
                log_info "    使用 $upx_cmd 进行 UPX 压缩..."
            else
                log_info "    Trying UPX compression with $upx_cmd..."
            fi

            local upx_temp="${lib_file}.upx"
            if "$upx_cmd" --best --lzma -o "$upx_temp" "$lib_file" &>/dev/null; then
                local upx_size
                upx_size=$(stat -c%s "$upx_temp" 2>/dev/null || echo "$final_size")
                if [ "$upx_size" -lt "$final_size" ]; then
                    if [ "$final_size" -gt 0 ]; then
                        local upx_reduction
                        upx_reduction=$(((final_size - upx_size) * 100 / final_size))
                        if [ "$locale" = "zh" ]; then
                            log_success "      UPX 压缩额外减少 ${upx_reduction}%"
                        else
                            log_success "      UPX compression saved an additional ${upx_reduction}%"
                        fi
                    fi
                    mv "$upx_temp" "$lib_file"
                    final_size=$upx_size
                    compression_applied=true
                else
                    rm -f "$upx_temp"
                    if [ "$locale" = "zh" ]; then
                        log_info "      UPX 压缩未带来收益"
                    else
                        log_info "      UPX compression not beneficial"
                    fi
                fi
            else
                rm -f "$upx_temp"
                if [ "$locale" = "zh" ]; then
                    log_info "      UPX 压缩失败"
                else
                    log_info "      UPX compression failed"
                fi
            fi
        fi

        if [ -n "$objcopy_cmd" ] && [ "$compression_applied" = "true" ]; then
            if [ "$locale" = "zh" ]; then
                log_info "    使用 $objcopy_cmd 优化..."
            else
                log_info "    Optimizing with $objcopy_cmd..."
            fi
            if "$objcopy_cmd" --remove-section=.comment --remove-section=.note "$lib_file" 2>/dev/null; then
                local objcopy_size
                objcopy_size=$(stat -c%s "$lib_file" 2>/dev/null || echo "$final_size")
                if [ "$objcopy_size" -lt "$final_size" ]; then
                    final_size=$objcopy_size
                    if [ "$locale" = "zh" ]; then
                        log_info "      objcopy 优化完成"
                    else
                        log_info "      objcopy optimization applied"
                    fi
                fi
            fi
        fi

        total_compressed_size=$((total_compressed_size + final_size))

        if [ "$compression_applied" = "true" ]; then
            compressed_count=$((compressed_count + 1))
            local file_reduction=0
            if [ "$original_size" -gt 0 ]; then
                file_reduction=$(((original_size - final_size) * 100 / original_size))
            fi
            if [ "$locale" = "zh" ]; then
                log_success "    最终: $original_size → $final_size 字节 (-${file_reduction}%)"
            else
                log_success "    Final: $original_size → $final_size bytes (-${file_reduction}%)"
            fi
        else
            if [ "$locale" = "zh" ]; then
                log_info "    未应用压缩"
            else
                log_info "    No compression applied"
            fi
        fi

        details+=("$lib_file:$final_size")

    done <<< "$lib_files"

    if [ -z "$summary_label" ]; then
        if [ "$locale" = "zh" ]; then
            summary_label="${target_name} 压缩统计:"
        else
            summary_label="Compression summary for $target_name:"
        fi
    fi

    local total_reduction=0
    if [ "$total_original_size" -gt 0 ]; then
        total_reduction=$(((total_original_size - total_compressed_size) * 100 / total_original_size))
    fi

    if [ "$compressed_count" -gt 0 ]; then
        log_success "$summary_label"
        if [ "$locale" = "zh" ]; then
            log_success "  处理文件数: $total_files"
            log_success "  优化文件数: $compressed_count"
            log_success "  总大小: $total_original_size → $total_compressed_size 字节 (-${total_reduction}%)"
        else
            log_success "  Files processed: $total_files"
            log_success "  Files optimized: $compressed_count"
            log_success "  Total size: $total_original_size → $total_compressed_size bytes (-${total_reduction}%)"
        fi
    else
        if [ "$locale" = "zh" ]; then
            log_info "$target_name 未实现显著压缩 (文件可能已优化)"
        else
            log_info "No significant compression achieved for $target_name (files may already be optimized)"
        fi
    fi

    if [ "$print_details" = "true" ]; then
        if [ "$locale" = "zh" ]; then
            log_info "最终库文件大小:"
        else
            log_info "Final library file sizes:"
        fi
        local entry
        for entry in "${details[@]}"; do
            local path="${entry%%:*}"
            local size="${entry##*:}"
            local size_kb=$(( (size + 1023) / 1024 ))
            log_info "  $(basename "$path"): ${size_kb} KB"
        done
    fi

    return 0
}