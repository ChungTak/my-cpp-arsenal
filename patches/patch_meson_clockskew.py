#!/usr/bin/env python3
"""
Patch meson to skip clock skew checks
"""
import os
import sys
import subprocess
import tempfile
import shutil

def patch_meson():
    """Find and patch meson to skip clock skew checks"""
    
    # 查找 meson 安装位置
    try:
        result = subprocess.run(['python3', '-c', 'import mesonbuild; print(mesonbuild.__file__)'], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            meson_init_file = result.stdout.strip()
            meson_dir = os.path.dirname(meson_init_file)
            print(f"Found mesonbuild at: {meson_dir}")
            
            # 查找所有可能包含 clock skew 检查的文件
            potential_files = [
                os.path.join(meson_dir, 'interpreter', 'interpreter.py'),
                os.path.join(meson_dir, 'interpreterbase', 'interpreter.py'),
                os.path.join(meson_dir, 'msetup.py'),
                os.path.join(meson_dir, 'mesonmain.py'),
                os.path.join(meson_dir, 'wrap', 'wrap.py'),
                os.path.join(meson_dir, 'build.py'),
            ]
            
            # 递归查找所有 .py 文件中的 Clock skew detected
            for root, dirs, files in os.walk(meson_dir):
                for file in files:
                    if file.endswith('.py'):
                        potential_files.append(os.path.join(root, file))
            
            patched_files = []
            
            for file_path in potential_files:
                if os.path.exists(file_path):
                    try:
                        with open(file_path, 'r', encoding='utf-8') as f:
                            content = f.read()
                        
                        # 查找 Clock skew detected 相关的代码
                        if 'Clock skew detected' in content:
                            print(f"Found clock skew check in: {file_path}")
                            
                            # 备份原始文件
                            backup_file = file_path + '.backup'
                            if not os.path.exists(backup_file):
                                shutil.copy2(file_path, backup_file)
                                print(f"Backed up to: {backup_file}")
                            
                            # 逐行处理，替换包含 Clock skew detected 的 raise 语句
                            lines = content.split('\n')
                            modified = False
                            for i, line in enumerate(lines):
                                # 跳过已经被修补过的行
                                if 'PATCHED: Skip clock skew check' in line:
                                    continue
                                elif 'Clock skew detected' in line and 'raise' in line:
                                    # 获取缩进
                                    indent = len(line) - len(line.lstrip())
                                    # 替换为 pass 语句，保持相同缩进
                                    lines[i] = ' ' * indent + f"pass  # PATCHED: Skip clock skew check - {line.strip()}"
                                    modified = True
                                    print(f"Patched line: {lines[i]}")
                                elif 'raise MesonException' in line and 'Clock skew' in line:
                                    # 获取缩进
                                    indent = len(line) - len(line.lstrip())
                                    # 替换为 pass 语句，保持相同缩进
                                    lines[i] = ' ' * indent + f"pass  # PATCHED: Skip clock skew check - {line.strip()}"
                                    modified = True
                                    print(f"Patched line: {lines[i]}")
                            
                            if modified:
                                # 写回文件
                                with open(file_path, 'w', encoding='utf-8') as f:
                                    f.write('\n'.join(lines))
                                patched_files.append(file_path)
                                
                    except Exception as e:
                        print(f"Error processing {file_path}: {e}")
            
            if patched_files:
                print(f"✅ Meson patched successfully in {len(patched_files)} files:")
                for f in patched_files:
                    print(f"  - {f}")
                return True
            else:
                print("❌ No clock skew checks found to patch")
                return False
                
    except Exception as e:
        print(f"Error patching meson: {e}")
    
    return False

def restore_meson():
    """Restore original meson files"""
    try:
        result = subprocess.run(['python3', '-c', 'import mesonbuild; print(mesonbuild.__file__)'], 
                              capture_output=True, text=True)
        if result.returncode == 0:
            meson_init_file = result.stdout.strip()
            meson_dir = os.path.dirname(meson_init_file)
            
            # 查找所有备份文件并恢复
            restored_files = []
            for root, dirs, files in os.walk(meson_dir):
                for file in files:
                    if file.endswith('.backup'):
                        backup_file = os.path.join(root, file)
                        original_file = backup_file[:-7]  # 移除 .backup 后缀
                        
                        if os.path.exists(original_file):
                            shutil.copy2(backup_file, original_file)
                            os.remove(backup_file)
                            restored_files.append(original_file)
            
            if restored_files:
                print(f"✅ Meson restored successfully for {len(restored_files)} files:")
                for f in restored_files:
                    print(f"  - {f}")
                return True
            else:
                print("No backup files found to restore")
                return False
                
    except Exception as e:
        print(f"Error restoring meson: {e}")
    
    return False

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "restore":
        restore_meson()
    else:
        patch_meson()