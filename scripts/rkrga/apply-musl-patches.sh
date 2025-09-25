#!/bin/bash

# RK RGA musl libc 兼容性补丁应用脚本

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="${SCRIPT_DIR}/patch"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SOURCES_DIR="${WORKSPACE_DIR}/sources"
LIBRGA_SOURCE_DIR="${SOURCES_DIR}/rkrga"

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

# 检查源码目录是否存在
check_source_dir() {
    if [ ! -d "${LIBRGA_SOURCE_DIR}" ]; then
        log_error "librga source directory not found: ${LIBRGA_SOURCE_DIR}"
        log_error "Please run build.sh first to clone the repository"
        exit 1
    fi
    
    if [ ! -f "${LIBRGA_SOURCE_DIR}/CMakeLists.txt" ]; then
        log_error "librga source appears to be incomplete (missing CMakeLists.txt)"
        exit 1
    fi
}

# 复制兼容性头文件
copy_compatibility_header() {
    log_info "Copying musl compatibility header..."
    
    local target_dir="${LIBRGA_SOURCE_DIR}/include"
    if [ ! -d "$target_dir" ]; then
        log_error "Target include directory not found: $target_dir"
        exit 1
    fi
    
    cp "${PATCH_DIR}/musl-compatibility.h" "$target_dir/"
    
    if [ $? -eq 0 ]; then
        log_success "musl-compatibility.h copied to ${target_dir}/"
    else
        log_error "Failed to copy musl-compatibility.h"
        exit 1
    fi
}

# 应用单个补丁
apply_single_patch() {
    local file_path="$1"
    local patch_content="$2"
    
    log_info "Applying patch to: $file_path"
    
    # 检查文件是否存在
    if [ ! -f "$file_path" ]; then
        log_error "Target file not found: $file_path"
        return 1
    fi
    
    # 创建备份
    cp "$file_path" "${file_path}.backup"
    
    # 应用补丁内容
    case "$file_path" in
        */include/drmrga.h)
            # 修复 drmrga.h
            sed -i '/#include <sys\/cdefs.h>/c\
\
/* musl libc compatibility fix */\
#ifdef __MUSL__\
#include "musl-compatibility.h"\
#else\
#include <sys/cdefs.h>\
#endif' "$file_path"
            ;;
        */samples/utils/utils.cpp)
            # 修复 utils.cpp - 在 #include "RgaUtils.h" 之前添加 cstdint
            sed -i '/^#include "RgaUtils.h"/i\
#include <cstdint>' "$file_path"
            ;;
        */core/3rdparty/android_hal/hardware/hardware_rockchip.h)
            # 修复 hardware_rockchip.h
            sed -i '/^#include "stdio.h"/a\
\
/* musl libc compatibility fix */\
#ifdef __MUSL__\
#include "musl-compatibility.h"\
#else\
#include <sys/cdefs.h>\
#endif' "$file_path"
            ;;
        *)
            log_warning "Unknown file type: $file_path"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        log_success "Patch applied successfully to: $file_path"
        return 0
    else
        log_error "Failed to apply patch to: $file_path"
        # 恢复备份
        mv "${file_path}.backup" "$file_path"
        return 1
    fi
}

# 应用所有补丁
apply_patches() {
    log_info "Applying musl libc compatibility patches..."
    
    local failed_count=0
    
    # 应用各个文件的补丁
    apply_single_patch "${LIBRGA_SOURCE_DIR}/include/drmrga.h" "drmrga"
    [ $? -ne 0 ] && ((failed_count++))
    
    apply_single_patch "${LIBRGA_SOURCE_DIR}/samples/utils/utils.cpp" "utils"
    [ $? -ne 0 ] && ((failed_count++))
    
    apply_single_patch "${LIBRGA_SOURCE_DIR}/core/3rdparty/android_hal/hardware/hardware_rockchip.h" "hardware_rockchip"
    [ $? -ne 0 ] && ((failed_count++))
    
    if [ $failed_count -eq 0 ]; then
        log_success "All patches applied successfully!"
        return 0
    else
        log_error "$failed_count patch(es) failed to apply"
        return 1
    fi
}

# 清理备份文件
cleanup_backups() {
    log_info "Cleaning up backup files..."
    find "${LIBRGA_SOURCE_DIR}" -name "*.backup" -delete
    log_success "Backup files cleaned up"
}

# 验证补丁应用
verify_patches() {
    log_info "Verifying applied patches..."
    
    local verification_failed=0
    
    # 检查 drmrga.h
    if grep -q "musl-compatibility.h" "${LIBRGA_SOURCE_DIR}/include/drmrga.h"; then
        log_success "✓ drmrga.h patch verified"
    else
        log_error "✗ drmrga.h patch verification failed"
        ((verification_failed++))
    fi
    
    # 检查 utils.cpp
    if grep -q "#include <cstdint>" "${LIBRGA_SOURCE_DIR}/samples/utils/utils.cpp"; then
        log_success "✓ utils.cpp patch verified"
    else
        log_error "✗ utils.cpp patch verification failed"
        ((verification_failed++))
    fi
    
    # 检查 hardware_rockchip.h
    if grep -q "musl-compatibility.h" "${LIBRGA_SOURCE_DIR}/core/3rdparty/android_hal/hardware/hardware_rockchip.h"; then
        log_success "✓ hardware_rockchip.h patch verified"
    else
        log_error "✗ hardware_rockchip.h patch verification failed"
        ((verification_failed++))
    fi
    
    # 检查兼容性头文件
    if [ -f "${LIBRGA_SOURCE_DIR}/include/musl-compatibility.h" ]; then
        log_success "✓ musl-compatibility.h exists"
    else
        log_error "✗ musl-compatibility.h not found"
        ((verification_failed++))
    fi
    
    if [ $verification_failed -eq 0 ]; then
        log_success "All patches verified successfully!"
        return 0
    else
        log_error "$verification_failed verification(s) failed"
        return 1
    fi
}

# 回滚补丁
rollback_patches() {
    log_info "Rolling back patches..."
    
    find "${LIBRGA_SOURCE_DIR}" -name "*.backup" | while read -r backup_file; do
        original_file="${backup_file%.backup}"
        mv "$backup_file" "$original_file"
        log_info "Restored: $original_file"
    done
    
    # 删除兼容性头文件
    if [ -f "${LIBRGA_SOURCE_DIR}/include/musl-compatibility.h" ]; then
        rm "${LIBRGA_SOURCE_DIR}/include/musl-compatibility.h"
        log_info "Removed: musl-compatibility.h"
    fi
    
    log_success "Patches rolled back successfully"
}

# 显示帮助信息
show_help() {
    echo "RK RGA musl libc Compatibility Patch Script"
    echo ""
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  apply     Apply musl libc compatibility patches (default)"
    echo "  rollback  Rollback applied patches"
    echo "  verify    Verify applied patches"
    echo "  help      Show this help message"
    echo ""
    echo "This script applies compatibility patches to fix musl libc compilation issues:"
    echo "  - Adds musl-compatibility.h header"
    echo "  - Fixes sys/cdefs.h missing include"
    echo "  - Adds missing cstdint include"
    echo "  - Defines __BEGIN_DECLS and __END_DECLS macros"
    echo ""
}

# 主函数
main() {
    local command="${1:-apply}"
    
    case "$command" in
        apply)
            log_info "Starting musl libc compatibility patch application..."
            check_source_dir
            copy_compatibility_header
            apply_patches
            if [ $? -eq 0 ]; then
                verify_patches
                if [ $? -eq 0 ]; then
                    cleanup_backups
                    log_success "Patch application completed successfully!"
                    log_info "You can now run the build script with musl targets"
                else
                    log_error "Patch verification failed, keeping backup files"
                    exit 1
                fi
            else
                log_error "Patch application failed"
                exit 1
            fi
            ;;
        rollback)
            log_info "Starting patch rollback..."
            check_source_dir
            rollback_patches
            ;;
        verify)
            log_info "Starting patch verification..."
            check_source_dir
            verify_patches
            ;;
        help|-h|--help)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"