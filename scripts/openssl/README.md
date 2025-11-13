# OpenSSL 构建脚本

这个脚本用于交叉编译 OpenSSL 库，支持多种目标平台。

## 功能特性

- 支持多种交叉编译目标平台
- 自动下载指定版本的 OpenSSL 源码
- 支持 Debug 和 Release 构建类型
- 集成 Android NDK 交叉编译支持
- 自动压缩构建产物（Release 模式）
- 使用与项目其他构建脚本一致的架构

## 支持的目标平台

- `aarch64-linux-gnu` - ARM64 Linux GNU
- `arm-linux-gnueabihf` - ARM Linux GNU EABI HF  
- `x86_64-linux-gnu` - x86_64 Linux GNU
- `aarch64-linux-android` - ARM64 Android
- `arm-linux-android` - ARM Android

## 使用方法

### 基本用法

```bash
# 构建默认目标平台（所有支持的Linux目标）
./scripts/openssl/build.sh

# 构建指定目标平台
./scripts/openssl/build.sh aarch64-linux-gnu

# 构建多个目标平台
./scripts/openssl/build.sh aarch64-linux-gnu x86_64-linux-gnu

# 构建所有支持的目标平台
./scripts/openssl/build.sh --all
```

### 构建类型

```bash
# Debug 构建
./scripts/openssl/build.sh --build-type Debug aarch64-linux-gnu

# Release 构建（默认）
./scripts/openssl/build.sh --build-type Release aarch64-linux-gnu
```

### 环境变量

```bash
# 指定 OpenSSL 版本（默认：3.5.4）
export OPENSSL_VERSION=3.5.4
./scripts/openssl/build.sh
```

## 构建输出

构建产物位于 `outputs/openssl/` 目录下，按目标平台组织：

```
outputs/openssl/
├── aarch64-linux-gnu/          # Release 版本
├── aarch64-linux-gnu-debug/    # Debug 版本
├── arm-linux-gnueabihf/
├── arm-linux-gnueabihf-debug/
├── x86_64-linux-gnu/
├── x86_64-linux-gnu-debug/
├── aarch64-linux-android/
├── aarch64-linux-android-debug/
├── arm-linux-android/
└── arm-linux-android-debug/
```

每个目标目录包含：
- `bin/` - 可执行文件
- `lib/` - 静态库文件
- `include/` - 头文件
- `ssl/` - SSL 配置和证书文件

## 依赖要求

- `wget` - 下载 OpenSSL 源码
- `tar` - 解压源码包
- `make` - 构建工具
- `gcc` - 主机编译器
- Android NDK（仅 Android 目标需要）

## 配置选项

脚本使用 OpenSSL 的 Configure 命令，包含以下选项：

```bash
./Configure \
    --prefix="$INSTALL_DIR" \
    --openssldir="$INSTALL_DIR/ssl" \
    --libdir=lib \
    no-shared \      # 仅构建静态库
    no-tests \       # 跳过测试构建
    "$OPENSSL_TARGET"  # 目标平台
```

## 示例

```bash
# 构建所有平台的 Release 版本
./scripts/openssl/build.sh --all

# 构建 ARM64 Linux 的 Debug 版本
./scripts/openssl/build.sh --build-type Debug aarch64-linux-gnu

# 构建指定版本并指定平台
OPENSSL_VERSION=3.5.4 ./scripts/openssl/build.sh aarch64-linux-gnu x86_64-linux-gnu

# 查看帮助信息
./scripts/openssl/build.sh --help
```

## 注意事项

1. Android 构建需要配置 Android NDK 环境
2. 交叉编译工具链文件位于 `toolchain/` 目录
3. 首次运行会自动下载 OpenSSL 源码，可能需要较长时间
4. Release 构建会自动压缩输出文件以减小体积
5. 构建过程会清理之前的构建缓存