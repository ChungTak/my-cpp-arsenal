# RK RGA musl libc 兼容性补丁

本目录包含了用于修复 RK RGA 库在 musl libc 环境下编译错误的补丁文件。

## 问题描述

在使用 musl libc 交叉编译工具链编译 RK RGA 库时，会遇到以下主要问题：

1. **缺少 `sys/cdefs.h` 头文件**
   - musl libc 不提供 `sys/cdefs.h`，这是 glibc 特有的头文件
   - 缺少 `__BEGIN_DECLS` 和 `__END_DECLS` 宏定义

2. **缺少 `int64_t` 类型定义**
   - 某些源文件缺少 `<cstdint>` 头文件包含

## 补丁文件说明

### musl-compatibility.h
- 提供 musl libc 兼容性宏定义
- 定义 `__BEGIN_DECLS`、`__END_DECLS` 等缺失的宏
- 包含必要的标准头文件

### 修复的文件
1. **include/drmrga.h**
   - 条件性包含 `musl-compatibility.h` 替代 `sys/cdefs.h`

2. **samples/utils/utils.cpp**
   - 添加 `<cstdint>` 头文件包含

3. **core/3rdparty/android_hal/hardware/hardware_rockchip.h**
   - 添加 musl libc 兼容性支持

## 使用方法

### 自动应用补丁
```bash
# 应用所有补丁
./apply-musl-patches.sh apply

# 验证补丁应用状态
./apply-musl-patches.sh verify

# 回滚补丁（如果需要）
./apply-musl-patches.sh rollback
```

### 手动应用补丁

如果需要手动应用补丁，可以：

1. 复制 `musl-compatibility.h` 到 `sources/rkrga/include/` 目录
2. 修改 `include/drmrga.h`:
   ```c
   // 替换
   #include <sys/cdefs.h>
   // 为
   #ifdef __MUSL__
   #include "musl-compatibility.h"
   #else
   #include <sys/cdefs.h>
   #endif
   ```

3. 修改 `samples/utils/utils.cpp`:
   ```cpp
   // 在 #include "RgaUtils.h" 之前添加
   #include <cstdint>
   ```

4. 修改 `core/3rdparty/android_hal/hardware/hardware_rockchip.h`:
   ```c
   // 在 #include "stdio.h" 之后添加
   #ifdef __MUSL__
   #include "musl-compatibility.h"
   #else
   #include <sys/cdefs.h>
   #endif
   ```

## 编译流程

应用补丁后，可以正常使用构建脚本：

```bash
# 编译 musl 版本
./build.sh musl_arm

# 或编译所有目标
./build.sh
```

## 注意事项

1. **源码目录清理**：由于 sources/rkrga 目录会被定期清理，补丁需要在每次重新克隆源码后重新应用。

2. **自动化集成**：建议在构建脚本中集成补丁应用流程，确保每次构建前自动应用补丁。

3. **兼容性**：这些补丁专门针对 musl libc 环境，不会影响 glibc 环境的编译。

## 错误排查

如果应用补丁后仍有编译错误，请检查：

1. 交叉编译工具链是否正确安装
2. 环境变量 `__MUSL__` 是否正确定义
3. 头文件路径是否正确

## 补丁版本

- 版本: 1.0
- 适用于: RK RGA jellyfin-rga 分支
- 测试环境: musl libc 1.2.x
- 交叉编译器: aarch64-linux-musl-gcc 11.2.1