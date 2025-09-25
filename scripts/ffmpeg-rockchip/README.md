# FFmpeg Rockchip 构建脚本

这个构建脚本用于编译针对 Rockchip 平台优化的 FFmpeg 版本，支持硬件加速编解码。

## 功能特性

- 支持 Rockchip MPP (Media Process Platform) 硬件编解码器
- 支持 Rockchip RGA (2D Raster Graphic Acceleration) 硬件图像处理
- 支持多种交叉编译目标平台
- 支持 Android 和 Linux 等多种操作系统

## 依赖项

在构建 FFmpeg Rockchip 之前，需要确保以下依赖项已经构建：

1. rkmpp - Rockchip Media Process Platform 库
2. rkrga - Rockchip 2D 图形加速库
3. libdrm - Direct Rendering Manager 库

这些依赖项应该已经通过相应的构建脚本构建完成，并位于 `outputs` 目录中。

## 支持的编解码器和过滤器

### 解码器/Hwaccel
```
V..... av1_rkmpp            Rockchip MPP AV1 解码器
V..... h263_rkmpp           Rockchip MPP H263 解码器
V..... h264_rkmpp           Rockchip MPP H264 解码器
V..... hevc_rkmpp           Rockchip MPP HEVC 解码器
V..... mjpeg_rkmpp          Rockchip MPP MJPEG 解码器
V..... mpeg1_rkmpp          Rockchip MPP MPEG1VIDEO 解码器
V..... mpeg2_rkmpp          Rockchip MPP MPEG2VIDEO 解码器
V..... mpeg4_rkmpp          Rockchip MPP MPEG4 解码器
V..... vp8_rkmpp            Rockchip MPP VP8 解码器
V..... vp9_rkmpp            Rockchip MPP VP9 解码器
```

### 编码器
```
V..... h264_rkmpp           Rockchip MPP H264 编码器
V..... hevc_rkmpp           Rockchip MPP HEVC 编码器
V..... mjpeg_rkmpp          Rockchip MPP MJPEG 编码器
```

### 过滤器
```
... overlay_rkrga     Rockchip RGA 视频合成器
... scale_rkrga       Rockchip RGA 视频缩放和格式转换器
... vpp_rkrga         Rockchip RGA 视频后处理 (缩放/裁剪/转置)
```

## 使用方法

### 构建所有默认目标平台

```bash
./build.sh
```

默认构建以下目标平台：
- aarch64-linux-gnu (ARM 64位 Linux)
- arm-linux-gnueabihf (ARM 32位 Linux)
- aarch64-linux-android (ARM 64位 Android)
- arm-linux-android (ARM 32位 Android)

### 构建特定目标平台

```bash
./build.sh aarch64-linux-gnu
```

### 支持的目标平台

- arm-linux-gnueabihf    - ARM 32位 glibc 版本
- aarch64-linux-gnu      - ARM 64位 glibc 版本
- riscv64-linux-gnu      - RISC-V 64位 glibc 版本
- arm-linux-musleabihf   - ARM 32位 musl 版本
- aarch64-linux-musl     - ARM 64位 musl 版本
- riscv64-linux-musl     - RISC-V 64位 musl 版本
- aarch64-linux-android  - Android ARM 64位版本
- arm-linux-android      - Android ARM 32位版本
- x86_64-linux-gnu       - x86_64 Linux 版本
- x86_64-windows-gnu     - x86_64 Windows 版本
- x86_64-macos           - x86_64 macOS 版本
- aarch64-macos          - ARM 64位 macOS 版本

### 清理构建目录

```bash
./build.sh --clean
```

### 完全清理（包括源码和输出）

```bash
./build.sh --clean-all
```

## 输出目录结构

构建完成后，输出文件将位于 `outputs/ffmpeg-rockchip/` 目录下，按目标平台分类：

```
outputs/ffmpeg-rockchip/
├── aarch64-linux-gnu/
│   ├── bin/
│   ├── include/
│   ├── lib/
│   └── share/
├── arm-linux-gnueabihf/
│   ├── bin/
│   ├── include/
│   ├── lib/
│   └── share/
└── ...
```

## 环境要求

- Git
- Make
- 支持相应目标平台的交叉编译工具链

## 注意事项

1. 构建前请确保 rkmpp、rkrga 和 libdrm 已经为相应目标平台构建完成
2. 对于 Android 平台，需要设置 ANDROID_NDK_HOME 环境变量
3. 构建脚本会自动下载 ffmpeg-rockchip 源码到 sources 目录
4. 构建过程可能需要较长时间，取决于系统性能和目标平台数量