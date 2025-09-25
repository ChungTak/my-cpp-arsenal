# libdrm 构建脚本

这是一个用于交叉编译 libdrm 库的自动化构建脚本，基于 [scirpts/rkrga/build.sh](../rkrga/build.sh) 的结构开发。

## 特性

- **固定版本**: libdrm 2.4.125
- **源码获取**: 自动从 https://dri.freedesktop.org/libdrm/libdrm-2.4.125.tar.xz 下载
- **构建系统**: 使用 meson 替代 cmake
- **交叉编译**: 通过 cross-build.txt 文件支持多种架构
- **时钟偏差修复**: 自动应用 meson 时钟补丁，解决编译时的时间同步问题
- **自动优化**: 库文件自动压缩和符号剥离
- **多平台支持**: 支持 ARM、RISC-V、Android 等多种目标平台

## 系统要求

### 必需工具
- `meson` - 构建系统
- `ninja` - 构建工具
- `wget` - 下载源码
- `tar` - 解压源码

### 可选工具
- `upx` - 动态库压缩（推荐）
- `strip` - 符号剥离（大多数工具链包含）
- `objcopy` - 二进制优化（大多数工具链包含）

## 支持的目标平台

### 常规 Linux 目标
- `arm-linux-gnueabihf` - ARM 32位 glibc 版本
- `aarch64-linux-gnu` - ARM 64位 glibc 版本
- `riscv64-linux-gnu` - RISC-V 64位 glibc 版本
- `aarch64-linux-musl` - ARM 64位 musl 版本
- `arm-linux-musleabihf` - ARM 32位 musl 版本
- `riscv64-linux-musl` - RISC-V 64位 musl 版本
- `x86_64-linux-gnu` - x86_64 Linux 版本

### Android 目标
- `aarch64-linux-android` - Android ARM 64位版本
- `arm-linux-android` - Android ARM 32位版本

### 其他平台
- `x86_64-windows-gnu` - x86_64 Windows 版本
- `x86_64-macos` - x86_64 macOS 版本
- `aarch64-macos` - ARM64 macOS 版本

## 使用方法

### 基本用法

```bash
# 构建默认目标（aarch64-linux-gnu, arm-linux-musleabihf, aarch64-linux-android, arm-linux-android）
./build.sh

# 构建特定目标
./build.sh aarch64-linux-gnu    # ARM 64位 glibc 版本
./build.sh aarch64-linux-musl   # ARM 64位 musl 版本
./build.sh aarch64-linux-android  # Android ARM 64位版本

# 显示帮助信息
./build.sh --help

# 清理构建目录
./build.sh --clean

# 清理所有（包括源码和输出）
./build.sh --clean-all
```

### 环境变量

```bash
# 设置交叉编译工具链目录（可选）
export TOOLCHAIN_ROOT_DIR=/path/to/your/toolchains

# 设置 Android NDK 路径（Android 目标需要）
export ANDROID_NDK_HOME=/path/to/android-ndk
```

## 构建流程

1. **检查工具**: 验证必需的构建工具是否可用
2. **获取源码**: 自动下载并解压 libdrm 源码
3. **配置交叉编译**: 根据目标平台生成 cross-build.txt 配置文件
4. **应用时钟补丁**: 自动运行 `patches/patch_meson_clockskew.py` 解决 meson 时钟偏差问题
5. **配置构建**: 使用 meson 配置针对目标平台的构建选项
6. **编译**: 使用 ninja 执行编译
7. **安装**: 将编译结果安装到输出目录
8. **优化**: 自动压缩库文件并剥离符号以减小体积

## 交叉编译配置

脚本会根据目标平台自动生成 `cross-build.txt` 配置文件，包含：

### 常规 Linux 平台示例
```ini
[binaries]
c = ['aarch64-linux-gnu-gcc']
cpp = ['aarch64-linux-gnu-g++']
ar = ['aarch64-linux-gnu-ar']
strip = ['aarch64-linux-gnu-strip']
pkg-config = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_std = 'c11'
default_library = 'both'
```

### Android 平台示例
```ini
[binaries]
c = ['${TOOLCHAIN}/bin/aarch64-linux-android23-clang']
cpp = ['${TOOLCHAIN}/bin/aarch64-linux-android23-clang++']
ar = ['${TOOLCHAIN}/bin/llvm-ar']
strip = ['${TOOLCHAIN}/bin/llvm-strip']
pkgconfig = 'pkg-config'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'

[built-in options]
c_std = 'c11'
default_library = 'both'
```

## GPU 驱动支持配置

脚本根据目标平台自动配置 GPU 驱动支持：

- **x86 Linux**: 启用桌面 GPU 驱动 (Intel, AMD, NVIDIA)
- **ARM Linux**: 启用 ARM SoC 和 PCIe GPU 驱动
- **Android/移动平台**: 专注于移动 GPU 驱动 (Mali, Adreno, PowerVR)
- **RISC-V/LoongArch**: 保守的 GPU 支持配置
- **Windows**: 最小支持，禁用 Linux 特有功能
- **macOS**: 非常最小的支持，仅基本功能

## 输出结构

```
outputs/libdrm/
├── arm-linux-gnueabihf/    # ARM 32位 glibc 版本
├── aarch64-linux-gnu/      # ARM 64位 glibc 版本
├── riscv64-linux-gnu/      # RISC-V 64位 glibc 版本
├── aarch64-linux-musl/     # ARM 64位 musl 版本
├── arm-linux-musleabihf/   # ARM 32位 musl 版本
├── riscv64-linux-musl/     # RISC-V 64位 musl 版本
├── aarch64-linux-android/  # Android ARM 64位版本
├── arm-linux-android/      # Android ARM 32位版本
├── x86_64-linux-gnu/       # x86_64 Linux 版本
├── x86_64-windows-gnu/     # x86_64 Windows 版本
├── x86_64-macos/           # x86_64 macOS 版本
├── aarch64-macos/          # ARM64 macOS 版本
└── version.ini             # 版本信息文件
```

每个目标目录包含：
- `lib/` - 编译的库文件（.so 和 .a）
- `include/` - 头文件
- `lib/pkgconfig/` - pkg-config 文件

## 库文件优化

脚本自动对生成的库文件进行优化：

1. **符号剥离**: 使用 `strip` 工具移除调试符号
2. **UPX 压缩**: 对动态库进行 UPX 压缩（如果可用）
3. **段移除**: 使用 `objcopy` 移除不必要的段
4. **统计报告**: 显示压缩前后的大小对比

## 故障排除

### 常见问题

1. **工具链未找到**
   ```
   解决: 安装对应的交叉编译工具链或检查 PATH 环境变量
   ```

2. **Android NDK 未找到**
   ```
   解决: 设置 ANDROID_NDK_HOME 环境变量或安装 Android NDK
   ```

3. **meson 配置失败**
   ```
   解决: 检查工具链是否正确安装，查看错误日志定位具体问题
   ```

4. **依赖缺失**
   ```
   解决: 根据目标平台安装相应的开发依赖包
   ```

5. **Meson 时钟偏差错误**
   ```
   错误信息: Clock skew detected
   解决: 脚本会自动应用补丁，如果仍然失败，检查 patches/patch_meson_clockskew.py 是否存在
   ```

### 调试模式

查看详细的构建日志：
```bash
# 启用详细输出
./build.sh aarch64-linux-gnu 2>&1 | tee build.log
```

## 与 rkrga 构建脚本的差异

| 特性 | rkrga | libdrm |
|------|-------|---------|
| 构建系统 | CMake | Meson |
| 源码获取 | Git clone | wget 下载 |
| 版本管理 | Git 分支 | 固定版本 2.4.125 |
| 配置文件 | CMake toolchain | Meson cross-file |
| GPU 驱动 | 不适用 | 根据平台自动配置 |

## 许可证

本脚本遵循与 libdrm 相同的许可证。