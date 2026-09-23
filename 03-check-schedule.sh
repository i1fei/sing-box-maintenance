#!/usr/bin/env bash
# 03-check-schedule.sh
#
# 目的：纯检测，确认系统是否已有自动机制会定期运行 logrotate
#       （systemd 的 logrotate.timer，或传统的 /etc/cron.daily/logrotate）。
#       不修改任何东西。绝大多数系统这一步会直接确认"已存在，无需操作"。
#
# 用法：sudo bash 03-check-schedule.sh

set -euo pipefail

FOUND=0

echo "== 检查 systemd timer 方式 =="
if systemctl list-timers 2>/dev/null | grep -qi logrotate; then
  echo "已启用 logrotate.timer，系统会自动定时执行，无需额外操作"
  systemctl list-timers | grep -i logrotate
  FOUND=1
else
  echo "未找到 logrotate.timer"
fi

echo ""
echo "== 检查 cron.daily 方式 =="
if [ -f /etc/cron.daily/logrotate ]; then
  if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
    echo "/etc/cron.daily/logrotate 存在，且 cron 服务正在运行，会每天自动触发"
    FOUND=1
  else
    echo "/etc/cron.daily/logrotate 存在，但 cron 服务似乎没在跑"
  fi
else
  echo "未找到 /etc/cron.daily/logrotate"
fi

echo ""
if [ "$FOUND" -eq 1 ]; then
  echo "结论：系统已有自动调度机制，日志轮转会按天自动循环，不用再建任何计划任务/服务。"
else
  echo "结论：没检测到可用的自动调度，需要手动补一个 cron 任务，执行以下命令即可（幂等，重复跑不会重复添加）："
  echo '  ( crontab -l 2>/dev/null | grep -v "logrotate /etc/logrotate.d/sing-box" ; echo "0 3 * * * /usr/sbin/logrotate /etc/logrotate.d/sing-box" ) | crontab -'
fi
