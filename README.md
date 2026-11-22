# SUSFS hosts 挂载隐藏

在 KernelSU（LKM 模式）上，用 SUSFS 隐藏 `/system/etc/hosts` 的 bind mount，让去广告模块的挂载暴露被检测器（如 Duck Detector）无法通过 `/proc/self/mountinfo` 发现，同时**保留 hosts 去广告效果**。

## 原理

- `susfs_guard_lkm`（[susfs4ksu-for-lkm](https://github.com/inforcqb/susfs4ksu-for-lkm)）：SUSFS 的可加载内核模块版，提供内核层 `show_mountinfo` 挂钩。
- `susfs4ksu`（[sidex15/susfs4ksu-module](https://github.com/sidex15/susfs4ksu-module)）：用户态工具 `ksu_susfs`。
- 挂载隐藏默认前缀是 `/data/adb/`，但 hosts 挂载的源是 `/dev/block/sda29`、挂载点是 `/system/etc/hosts`，两者都不在前缀内，因此匹配不到。**把挂载点 `/system/etc/hosts` 加入前缀表即可隐藏。**

## 前置条件

1. 已 root（KernelSU LKM 模式）。
2. 已在 KernelSU Manager 刷入以下两个模块并重启：
   - `susfs_guard_lkm-module-v2.3.0-r18.8-arm64.zip`（**注意：用 r18.8，见下方"版本选择"**）
   - `ksu_module_susfs_<版本>.zip`

## 版本选择（重要）

`susfs4ksu-for-lkm` 在 **v2.3.0-r18.9** 起把内核符号解析器从「kprobe bootstrap」换成了「KallRecon」（release note #192）。KallRecon 靠**扫描内核内存找 kallsyms 符号表**，在部分非标准内核（如 5.15 HyperOS 移植内核）上会失败，表现为模块加载报错：

```
symbol_resolver: kallrecon discovery failed (4, klp=0), refusing to load
# init_module 返回 errno 61 (ENODATA)
```

因此：

- **5.15 HyperOS 移植内核（本用例）→ 用 v2.3.0-r18.8**（kprobe bootstrap，稳定）。
- 标准 GKI 内核可尝试最新版，但若遇到上述报错，同样降级到 r18.8。

## 使用方法

```sh
su -c "sh /sdcard/Download/susfs_hosts_hide_setup.sh"
```

脚本会（幂等，可重复执行）：

1. 检查 SUSFS LKM 是否加载；
2. 开启挂载隐藏总开关 `hide_sus_mnts_for_non_su_procs 1`；
3. 创建 `susfs_guard_lkm/early_load`（开机早加载）；
4. 立即添加 `/system/etc/hosts` 前缀并触发 rescan（本次开机生效）；
5. 创建持久化模块 `susfs_hosts_hide`（重启后自动加前缀）；
6. 验证配置。

## 验证

非 root 视角应看不到 hosts 挂载：

```sh
adb shell "grep -i hosts /proc/self/mountinfo"
# 空输出 = 已隐藏成功
```

su 视角仍应能看到（mnt_id 被标记为 `2000000000` 以上）：

```sh
su -c "grep -i hosts /proc/self/mountinfo"
```

## 注意事项

- 隐藏只对**非 su 域**进程生效，对 root/su 域进程无效（自己的工具不受影响）。
- 不要手动 `umount` / `mount` hosts 挂载，可能有崩溃风险。
- 这只能解决"挂载暴露"这一个检测点；其它检测点（如 TEE 指纹异常）是独立问题，需另行处理。
