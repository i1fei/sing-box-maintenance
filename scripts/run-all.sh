#!/usr/bin/env bash
# run-all.sh — 按顺序执行全部三个脚本
# 用法：sudo bash run-all.sh

set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$DIR/01-fix-adblock.sh"
bash "$DIR/02-setup-logrotate.sh"
bash "$DIR/03-check-schedule.sh"
bash "$DIR/04-setup-keepalive.sh"
