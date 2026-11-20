#!/system/bin/sh
# ============================================================
#  SUSFS hosts 挂载隐藏 - 一键配置脚本
# ------------------------------------------------------------
#  前置条件（需要你先手动完成）：
#    1. 在 KernelSU Manager 里刷入以下两个模块 ZIP：
#       a) susfs_guard_lkm-module-<版本>-arm64.zip   (SUSFS LKM 加载器)
#       b) ksu_module_susfs_<版本>.zip               (用户态工具 ksu_susfs)
#    2. 重启一次，让 SUSFS LKM 加载。
#  本脚本负责（root 下执行）：
#    1. 检查前置条件
#    2. 开启挂载隐藏总开关
#    3. 创建 early_load（开机早加载，抢在去广告模块挂载前）
#    4. 立即隐藏目标挂载（本次开机生效）
#    5. 创建持久化模块（重启后自动生效）
#    6. 验证结果
#  用法：
#    su -c 'sh /sdcard/susfs_hosts_hide_setup.sh'
#  可重复执行（幂等）。
# ============================================================

# 要隐藏的挂载点（一般不用改）
TARGET="/system/etc/hosts"
MOD_ID="susfs_hosts_hide"
KSUSFS="/data/adb/ksu/bin/ksu_susfs"

log()  { echo "[*] $1"; }
ok()   { echo "[+] $1"; }
warn() { echo "[!] $1"; }
die()  { echo "[x] $1"; exit 1; }

echo "=============================================="
echo " SUSFS hosts 挂载隐藏 配置脚本"
echo "=============================================="

# ---- 1. root 检查 ----
[ "$(id -u)" = "0" ] || die "需要 root 权限执行"
ok "已以 root 运行"

# ---- 2. SUSFS LKM 加载检查 ----
if [ ! -e /proc/susfs_hide_mounts ]; then
  die "/proc/susfs_hide_mounts 不存在。请先刷入 susfs_guard_lkm 模块并重启一次"
fi
ok "SUSFS LKM 已加载"

# ---- 3. 开启挂载隐藏总开关 ----
if [ -x "$KSUSFS" ]; then
  if "$KSUSFS" 2>&1 | grep -q "susfs"; then
    "$KSUSFS" hide_sus_mnts_for_non_su_procs 1 >/dev/null 2>&1
    ok "已开启挂载隐藏总开关 (hide_sus_mnts_for_non_su_procs 1)"
  else
    warn "ksu_susfs 未识别到 SUSFS，跳过总开关"
  fi
else
  warn "未找到 $KSUSFS，跳过总开关（可能由 susfs4ksu 模块开机自动开启）"
fi

# ---- 4. 创建 early_load（开机早加载） ----
found=0
for d in /data/adb/modules/susfs_guard_lkm /data/adb/modules_update/susfs_guard_lkm; do
  if [ -d "$d" ]; then
    touch "$d/early_load" 2>/dev/null
    ok "已创建 $d/early_load"
    found=1
  fi
done
[ "$found" = "1" ] || warn "未找到 susfs_guard_lkm 模块目录，early_load 未创建"

# ---- 5. 立即隐藏目标挂载（本次开机生效） ----
if grep -q "$TARGET" /proc/susfs_hide_mounts 2>/dev/null; then
  ok "前缀 $TARGET 已存在，跳过添加"
else
  if echo "add $TARGET" > /proc/susfs_hide_mounts 2>/dev/null; then
    ok "已添加前缀 $TARGET（已触发 rescan）"
  else
    warn "添加前缀失败"
  fi
fi

# ---- 6. 创建持久化模块（重启后自动生效） ----
MOD_DIR="/data/adb/modules/$MOD_ID"
if [ -d "$MOD_DIR" ]; then
  ok "持久化模块 $MOD_ID 已存在"
else
  mkdir -p "$MOD_DIR" 2>/dev/null
  cat > "$MOD_DIR/module.prop" << EOF
id=$MOD_ID
name=SUSFS hosts 挂载隐藏
version=v1.0
versionCode=1
author=auto
description=开机把 $TARGET 加入 SUSFS 挂载隐藏前缀(配合 susfs_guard_lkm)
EOF
  cat > "$MOD_DIR/service.sh" << 'EOF'
#!/system/bin/sh
# 开机把 /system/etc/hosts 加入 SUSFS 挂载隐藏前缀
TARGET="/system/etc/hosts"
i=0
while [ ! -e /proc/susfs_hide_mounts ] && [ "$i" -lt 30 ]; do
  sleep 1
  i=$((i+1))
done
if [ -e /proc/susfs_hide_mounts ]; then
  if ! grep -q "$TARGET" /proc/susfs_hide_mounts 2>/dev/null; then
    echo "add $TARGET" > /proc/susfs_hide_mounts 2>/dev/null
  fi
fi
EOF
  sed -i 's/\r//g' "$MOD_DIR/service.sh" 2>/dev/null
  chmod 755 "$MOD_DIR/service.sh" 2>/dev/null
  chmod 644 "$MOD_DIR/module.prop" 2>/dev/null
  ok "已创建持久化模块 $MOD_DIR"
fi

# ---- 7. 验证 ----
echo ""
echo "============== 验证结果 =============="
echo "--- 前缀表 ---"
grep -E "prefixes:|rescans=" /proc/susfs_hide_mounts 2>/dev/null
echo "--- 挂载标记统计 (marked/ident 应为 1 或以上) ---"
cat /sys/module/susfs_guard_lkm/parameters/mount_stat 2>/dev/null | head -3
echo "--- su 视角挂载 (mntid 为 2000000000+ 表示已标记) ---"
grep -i "$(basename "$TARGET")" /proc/self/mountinfo 2>/dev/null | awk '{print "  mntid="$1" -> "$5}'

echo ""
ok "配置完成。重启后自动生效。"
echo "最终验证(非 root 视角，应返回空):"
echo "  adb shell \"grep -i hosts /proc/self/mountinfo\""
echo "  → 空输出 = 已隐藏成功"
