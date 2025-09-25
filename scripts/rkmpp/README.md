# Rockchip MPP 编译脚本

这个目录包含了用于编译 Rockchip Media Process Platform (MPP) 的脚本和相关文件。

## 目录结构

```
rkmpp/
├── build.sh          # 主编译脚本
└── README.md         # 本说明文件
```

## 使用方法

### 基本用法

```bash
# 进入脚本目录
cd scripts/rkmpp

# 构建所有默认目标
./build.sh

# 构建特定目标
./build.sh aarch64-linux-gnu

# 显示帮助信息
./build.sh --help

# 清理构建目录
./build.sh --clean

# 清理所有内容（包括源码和输出）
./build.sh --clean-all
```

### 支持的目标平台

- `aarch64-linux-gnu` - ARM 64位 glibc 版本
- `arm-linux-gnueabihf` - ARM 32位 glibc 版本
- `aarch64-linux-android` - Android ARM 64位版本
- `arm-linux-android` - Android ARM 32位版本
- `aarch64-linux-musl` - ARM 64位 musl 版本
- `arm-linux-musleabihf` - ARM 32位 musl 版本
- `riscv64-linux-gnu` - RISC-V 64位 glibc 版本
- `riscv64-linux-musl` - RISC-V 64位 musl 版本
- `x86_64-linux-gnu` - x86_64 Linux 版本
- `x86_64-windows-gnu` - x86_64 Windows 版本
- `x86_64-macos` - x86_64 macOS 版本
- `aarch64-macos` - ARM64 macOS 版本

### 环境变量

- `ANDROID_NDK_HOME` - Android NDK 路径（默认：~/sdk/android_ndk/android-ndk-r25c）
- `TOOLCHAIN_ROOT_DIR` - 交叉编译工具链路径（可选）

## 功能特性

- 支持多种交叉编译工具链
- 自动克隆 Rockchip MPP 源码
- 支持 Android NDK 编译
- 自动库文件压缩优化
- 详细的构建日志输出
- 支持单目标和多目标构建

## 输出目录

编译输出位于工作区的 `outputs/rkmpp/` 目录下，每个目标平台会有独立的子目录。

## 依赖工具

- git
- cmake
- make
- 对应的交叉编译工具链

## 注意事项

1. 首次运行会自动克隆源码
2. 需要预先安装对应的交叉编译工具链
3. Android 构建需要安装 Android NDK
4. 脚本会自动进行库文件压缩优化以减小体积