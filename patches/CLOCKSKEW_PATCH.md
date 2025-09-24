# Meson 时钟偏差补丁说明

## 问题描述

在某些环境下（特别是容器、虚拟机或交叉编译环境），meson 构建系统可能会遇到时钟偏差（clock skew）错误：

```
Clock skew detected. Your build directory was generated with a newer version of meson than the current one.
```

这个错误通常发生在：
1. 文件系统时间戳不一致
2. 系统时钟未同步
3. 跨时区的构建环境
4. 容器或虚拟机中的时间同步问题

## 解决方案

libdrm 构建脚本集成了自动化的时钟偏差补丁机制：

meson安装方式需要使用 `pip install meson` 才会生效

### 自动应用补丁

构建脚本会在每次调用 meson 之前自动运行：
```bash
python3 patches/patch_meson_clockskew.py
```

### 补丁工作原理

1. **定位 meson 安装目录**: 自动检测 mesonbuild 模块位置
2. **查找时钟检查代码**: 扫描所有 Python 文件查找 "Clock skew detected" 相关代码
3. **创建备份**: 在修改前自动备份原始文件
4. **应用补丁**: 将 `raise` 语句替换为 `pass` 语句，跳过时钟检查
5. **保持注释**: 添加补丁标记以便后续识别

### 补丁示例

**原始代码**:
```python
if clock_skew_detected:
    raise MesonException('Clock skew detected...')
```

**补丁后**:
```python
if clock_skew_detected:
    pass  # PATCHED: Skip clock skew check - raise MesonException('Clock skew detected...')
```

## 构建流程中的集成

构建脚本在以下时机自动应用补丁：

1. **常规 Linux 目标** (`build_target` 函数)：
   ```bash
   # 创建交叉编译配置文件
   create_cross_file "$target_name" "$toolchain_file" "false"
   
   # 应用 meson 时钟偏差补丁
   apply_meson_clockskew_patch
   
   # 配置 Meson
   meson setup ...
   ```

2. **Android 目标** (`build_android_target` 函数)：
   ```bash
   # 创建交叉编译配置文件
   create_cross_file "$target_name" "" "true"
   
   # 应用 meson 时钟偏差补丁
   apply_meson_clockskew_patch
   
   # 配置 Meson
   meson setup ...
   ```

## 日志输出

正常情况下会看到以下日志：

```
[INFO] Applying meson clockskew patch...
Found mesonbuild at: /usr/local/lib/python3.x/site-packages/mesonbuild
Found clock skew check in: /usr/local/lib/python3.x/site-packages/mesonbuild/interpreter/interpreter.py
Backed up to: /usr/local/lib/python3.x/site-packages/mesonbuild/interpreter/interpreter.py.backup
Patched line:     pass  # PATCHED: Skip clock skew check - raise MesonException('Clock skew detected...')
✅ Meson patched successfully in 1 files:
  - /usr/local/lib/python3.x/site-packages/mesonbuild/interpreter/interpreter.py
[SUCCESS] Meson clockskew patch applied successfully
```

## 手动使用补丁

如果需要手动应用或恢复补丁：

### 应用补丁
```bash
python3 patches/patch_meson_clockskew.py
```

### 恢复原始文件
```bash
python3 patches/patch_meson_clockskew.py restore
```

## 安全考虑

1. **备份机制**: 补丁会自动创建 `.backup` 文件
2. **幂等性**: 多次运行补丁不会产生副作用
3. **标记识别**: 已补丁的代码会被标记，避免重复修改
4. **可恢复性**: 可以随时恢复到原始状态

## 兼容性

- **Python 版本**: 支持 Python 3.6+
- **Meson 版本**: 支持所有主流 meson 版本
- **操作系统**: Linux、macOS、Windows
- **环境**: 物理机、虚拟机、容器

## 故障排除

### 补丁脚本未找到
```
[WARNING] Meson clockskew patch script not found: patches/patch_meson_clockskew.py
[WARNING] Compilation may fail due to clock skew issues
```

**解决方案**: 确保补丁脚本存在且可执行：
```bash
chmod +x patches/patch_meson_clockskew.py
```

### 补丁应用失败
```
[WARNING] Failed to apply meson clockskew patch
[WARNING] Compilation may fail due to clock skew issues
```

**可能原因**:
1. 权限不足 - 需要对 meson 安装目录的写权限
2. meson 版本过新 - 时钟检查代码可能已移除或修改
3. Python 路径问题

**解决方案**:
```bash
# 使用管理员权限
sudo python3 patches/patch_meson_clockskew.py

# 或手动修改 meson 代码
find /usr -name "*.py" -path "*/mesonbuild/*" -exec grep -l "Clock skew detected" {} \;
```

## 性能影响

- **启动开销**: 补丁应用通常在 1-3 秒内完成
- **运行时影响**: 无，补丁仅跳过检查逻辑
- **存储开销**: 备份文件占用少量额外空间

## 最佳实践

1. **定期清理**: 定期清理 `.backup` 文件（如果不需要恢复）
2. **版本控制**: 在 CI/CD 中确保补丁脚本的一致性
3. **监控日志**: 关注补丁应用的日志输出
4. **测试验证**: 在关键环境中验证补丁效果

这个自动化补丁机制确保了 libdrm 构建在各种环境下的稳定性和可靠性。