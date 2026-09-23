#!/usr/bin/env bash
# 04-setup-keepalive.sh
#
# 目的：给 sing-box 的 systemd 服务加上"保活"能力，分两部分：
#       1) 崩溃自动重启优化 —— 通过 override.conf 设置重启间隔 + 取消重试次数限制，
#          避免短时间内连续崩溃触发 systemd 的 StartLimitBurst 保护后被放弃拉起。
#       2) 定时重启 —— 新建一个 systemd service + timer，按天在指定时间重启一次，
#          规避长期运行可能出现的内存增长 / 连接堆积问题。
#
# 只新增/覆盖以下几个文件，不改动 sing-box 主配置本身：
#   /etc/systemd/system/<SERVICE_NAME>.service.d/override.conf
#   /etc/systemd/system/<SERVICE_NAME>-restart.service
#   /etc/systemd/system/<SERVICE_NAME>-restart.timer
#
# 幂等：重复执行只会覆盖同名文件，不会产生重复的 timer/service。
#
# 用法：sudo bash 04-setup-keepalive.sh

set -euo pipefail

SERVICE_NAME="sing-box"   # 如果实际服务名不同，改这里
RESTART_TIME="04:00:00"   # 每日定时重启时间（24小时制），建议选流量低谷时段
RESTART_SEC=5             # 崩溃后等待几秒再拉起，避免瞬间循环重启

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 权限运行" >&2
  exit 1
fi

if ! systemctl list-unit-files | grep -q "^${SERVICE_NAME}.service"; then
  echo "错误: 未找到服务 ${SERVICE_NAME}.service，请检查 SERVICE_NAME 变量是否正确。" >&2
  exit 1
fi

echo ">> 1/3 写入崩溃重启优化参数 (override.conf)"
mkdir -p "/etc/systemd/system/${SERVICE_NAME}.service.d"
cat > "/etc/systemd/system/${SERVICE_NAME}.service.d/override.conf" <<EOF
[Service]
RestartSec=${RESTART_SEC}

[Unit]
StartLimitIntervalSec=0
EOF

echo ">> 2/3 写入定时重启 service + timer"
cat > "/etc/systemd/system/${SERVICE_NAME}-restart.service" <<EOF
[Unit]
Description=Restart ${SERVICE_NAME} periodically

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl restart ${SERVICE_NAME}.service
EOF

cat > "/etc/systemd/system/${SERVICE_NAME}-restart.timer" <<EOF
[Unit]
Description=Daily restart timer for ${SERVICE_NAME}

[Timer]
OnCalendar=*-*-* ${RESTART_TIME}
Persistent=true

[Install]
WantedBy=timers.target
EOF

echo ">> 3/3 重新加载 systemd 并启用定时器"
systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}-restart.timer"

echo ""
echo "== 保活配置完成 =="
echo "崩溃重启: ${SERVICE_NAME} 崩溃后 ${RESTART_SEC} 秒自动拉起，不限重试次数"
echo "定时重启: 每天 ${RESTART_TIME} 自动重启一次"
echo ""
echo "验证命令："
echo "  systemctl cat ${SERVICE_NAME}                 # 确认崩溃重启参数已生效"
echo "  systemctl list-timers | grep ${SERVICE_NAME}  # 确认定时器已注册且下次触发时间正确"
