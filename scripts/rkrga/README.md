# RK RGA 构建脚本使用说明

## 概述

`scripts/rkrga/build.sh` 是一个用于构建 RK RGA (Rockchip RGA) 库的多架构交叉编译脚本，支持多种架构和C库组合。

## 功能特性

- 自动克隆或检测现有的 librga 源码
- 支持多种交叉编译工具链
- 智能处理环境变量配置
- 自动创建软链接以兼容不同命名约定
- 完整的错误处理和日志输出
- 可选的清理功能

## 支持的架构

| 目录名 | 工具链 | 架构 | C库 | 说明 |
|--------|--------|------|-----|------|
| arm-linux-gnueabihf | arm-linux-gnueabihf-gcc | ARM 32-bit | glibc | 标准 ARM 32位 |
| aarch64-linux-gnu | aarch64-linux-gnu-gcc | ARM 64-bit | glibc | 标准 ARM 64位 |
| riscv64-linux-gnu | riscv64-linux-gnu-gcc | RISC-V 64-bit | glibc | RISC-V 64位 |
| aarch64-linux-musl | aarch64-linux-musl-gcc | ARM 64-bit | musl | ARM 64位 musl |
| arm-linux-musleabihf | arm-linux-musleabihf-gcc | ARM 32-bit | musl | ARM 32位 musl |
| riscv64-linux-musl | riscv64-linux-musl-gcc | RISC-V 64-bit | musl | RISC-V 64位 musl |
| aarch64-linux-android | aarch64-linux-android-clang | ARM 64-bit | bionic | Android ARM 64位 |
| arm-linux-android | arm-linux-androideabi-clang | ARM 32-bit | bionic | Android ARM 32位 |
| x86_64-linux-gnu | x86_64-linux-gnu-gcc | x86_64 | glibc | x86_64 Linux 版本 |
| x86_64-windows-gnu | x86_64-w64-mingw32-gcc | x86_64 | msvcrt | x86_64 Windows 版本 |
| x86_64-macos | x86_64-apple-darwin-clang | x86_64 | libc | x86_64 macOS 版本 |
| aarch64-macos | aarch64-apple-darwin-clang | ARM64 | libc | ARM64 macOS 版本 |

## 使用方法

### 基本用法

```bash
# 构建所有支持的架构
./scripts/rkrga/build.sh

# 构建指定的单个架构
./scripts/rkrga/build.sh aarch64-linux-gnu   # 构建ARM 64位 glibc版本
./scripts/rkrga/build.sh aarch64-linux-musl  # 构建ARM 64位 musl版本
./scripts/rkrga/build.sh aarch64-linux-android  # 构建Android ARM 64位版本

# 显示帮助信息
./scripts/rkrga/build.sh --help

# 清理构建目录
./scripts/rkrga/build.sh --clean

# 清理所有（源码和输出）
./scripts/rkrga/build.sh --clean-all
```

### 环境变量

- `TOOLCHAIN_ROOT_DIR`: 交叉编译工具链根目录（可选）
  - 如果设置，脚本会使用 `${TOOLCHAIN_ROOT_DIR}/bin/` 下的工具链
  - 如果未设置，脚本会使用系统PATH中的工具链

### 示例

```bash
# 使用系统默认工具链构建所有目标
./scripts/rkrga/build.sh

# 构建单个目标
./scripts/rkrga/build.sh aarch64-linux-gnu

# 使用自定义工具链路径构建特定目标
export TOOLCHAIN_ROOT_DIR=/opt/gcc-arm-10.3-2021.07-x86_64-aarch64-linux-gnu
./scripts/rkrga/build.sh aarch64-linux-gnu

# 构建Android目标（需要设置ANDROID_NDK_HOME环境变量）
export ANDROID_NDK_HOME=/opt/android-ndk-r25c
./scripts/rkrga/build.sh aarch64-linux-android

# 构建Windows目标
./scripts/rkrga/build.sh x86_64-windows-gnu

# 构建macOS目标
./scripts/rkrga/build.sh aarch64-macos
```

## 输出结构

构建完成后，输出目录结构如下：

```
outputs/rkrga/
├── arm-linux-gnueabihf/    # ARM 32-bit glibc
│   ├── bin/
│   ├── include/
│   └── lib/
├── aarch64-linux-gnu/      # ARM 64-bit glibc  
│   ├── bin/
│   ├── include/
│   └── lib/
├── riscv64-linux-gnu/      # RISC-V 64-bit glibc
├── aarch64-linux-musl/     # ARM 64-bit musl
├── arm-linux-musleabihf/   # ARM 32-bit musl
├── riscv64-linux-musl/     # RISC-V 64-bit musl
├── aarch64-linux-android/  # Android ARM 64-bit
├── arm-linux-android/      # Android ARM 32-bit
├── x86_64-linux-gnu/       # x86_64 Linux
├── x86_64-windows-gnu/     # x86_64 Windows
├── x86_64-macos/           # x86_64 macOS
├── aarch64-macos/          # ARM64 macOS
└── musl_arm -> musl        # 软链接
```

每个架构目录包含：
- `lib/`: 动态库和静态库文件 (`librga.so`, `librga.a`)
- `include/`: 头文件
- `bin/`: 示例程序 (`rgaImDemo`)

## 依赖要求

### 必需工具
- `git`: 用于克隆源码
- `cmake`: 构建系统
- `make`: 编译工具

### 交叉编译工具链
根据需要构建的架构，安装相应的交叉编译工具链：

```bash
# Ubuntu/Debian 系统
sudo apt install gcc-arm-linux-gnueabihf      # 32bit
sudo apt install gcc-aarch64-linux-gnu        # 64bit
sudo apt install gcc-riscv64-linux-gnu        # glibc_riscv64
# musl 工具链需要单独安装
```

## 常见问题

### 1. 工具链找不到
```
[WARNING] Toolchain file not found: xxx.cmake, skipping xxx
```
**解决方案**: 安装对应的交叉编译工具链，或设置 `TOOLCHAIN_ROOT_DIR` 环境变量

### 2. 源码克隆失败
```
[ERROR] Failed to clone librga
```
**解决方案**: 检查网络连接，或手动下载源码到 `sources/rkrga` 目录

### 3. 编译错误
**解决方案**: 
- 确保工具链版本兼容
- 检查系统依赖库是否完整
- 查看详细错误日志

## 技术说明

### 工具链配置
脚本使用 CMake toolchain 文件进行交叉编译配置，支持：
- 自动检测系统工具链 (`/usr/bin/`)
- 自定义工具链路径 (`TOOLCHAIN_ROOT_DIR`)
- 动态配置编译器路径和标志

### 构建流程
1. 检查必要工具
2. 克隆或验证 librga 源码
3. 为每个架构创建独立构建目录
4. 使用对应的 toolchain 文件配置 CMake
5. 编译和安装到指定输出目录
6. 创建软链接

## 贡献指南

如需添加新的架构支持：
1. 创建对应的 toolchain 文件在 `toolchain/` 目录
2. 在脚本的 `targets` 数组中添加新配置
3. 测试编译流程
4. 更新文档

---

**注意**: 此脚本已在 Ubuntu 24.04 环境下测试通过，其他系统可能需要适当调整。