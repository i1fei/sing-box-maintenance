#!/usr/bin/env bash
# 02-setup-logrotate.sh
#
# 目的：给 sing-box 的访问日志配置系统级 logrotate 循环保留（rolling retention），
#       解决日志文件无限增长的问题。
#
# 完全不修改 sing-box 本身的配置或服务，只写入一份 /etc/logrotate.d/sing-box 规则，
# 交给操作系统自带的 logrotate 机制长期自动管理。
# 幂等：重复执行只会覆盖同名规则文件，不会重复添加；已压缩的历史日志会被跳过。
#
# 用法：sudo bash 02-setup-logrotate.sh

set -euo pipefail

LOG_FILE="/var/log/sing-box/access.log"
LOGROTATE_CONF="/etc/logrotate.d/sing-box"
KEEP_DAYS=30          # 想保留 60 天就把这里改成 60
MAX_SIZE="50M"         # 单个日志超过这个大小时，即使还没到每日轮转时间也会提前触发

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 权限运行" >&2
  exit 1
fi

if ! command -v logrotate >/dev/null 2>&1; then
  echo ">> 安装 logrotate..."
  if command -v apt >/dev/null 2>&1; then
    apt update -y && apt install -y logrotate
  elif command -v yum >/dev/null 2>&1; then
    yum install -y logrotate
  else
    echo "无法自动安装 logrotate，请手动安装后重试" >&2
    exit 1
  fi
fi

if [ ! -f "$LOG_FILE" ]; then
  echo "提示：未找到 $LOG_FILE，脚本仍会写入配置，等日志文件产生后自动生效"
fi

echo ">> 写入 logrotate 配置: $LOGROTATE_CONF"
# 注意：没有加 delaycompress —— 每次轮转会立即压缩，避免出现
# "轮转后的大文件要等到下一轮才压缩" 从而白白占用磁盘空间的情况。
# 用 copytruncate 而不是重命名+信号通知，这样不需要 sing-box 重启或重新打开文件句柄。
cat > "$LOGROTATE_CONF" <<EOF
$LOG_FILE {
    daily
    rotate $KEEP_DAYS
    maxsize $MAX_SIZE
    compress
    missingok
    notifempty
    copytruncate
}
EOF

echo ">> 立即执行一次轮转，把当前已经很大的日志先清理掉"
logrotate -f "$LOGROTATE_CONF" || true

echo ">> 检查是否有历史遗留的未压缩日志，顺手压缩掉"
shopt -s nullglob
for f in "${LOG_FILE}".[0-9]*; do
  case "$f" in
    *.gz) ;;  # 已经压缩过，跳过
    *)
      if [ -s "$f" ]; then
        echo "   压缩 $f"
        gzip -f "$f"
      fi
      ;;
  esac
done
shopt -u nullglob

echo ">> 当前日志目录情况："
ls -lh "$(dirname "$LOG_FILE")" 2>/dev/null || true

echo ">> 完成。此后系统每天自动检查，最多保留 ${KEEP_DAYS} 天压缩日志，单文件超过 ${MAX_SIZE} 也会提前轮转，轮转后立即压缩，不会再堆积未压缩的大文件。"
