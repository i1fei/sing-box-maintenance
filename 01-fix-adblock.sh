#!/usr/bin/env bash
# 01-fix-adblock.sh
#
# 目的：给 233boy sing-box 脚本管理的服务端配置加上"广告域名拒绝解析"规则，
#       恢复通过该节点上网时的去广告能力。
#
# 只会修改 /etc/sing-box/config.json 里的 dns.rules 和 route.rule_set 两处，
# 其余字段原样保留。幂等：重复执行不会叠加重复规则（先按 tag 去重再插入）。
#
# 用法：sudo bash 01-fix-adblock.sh

set -euo pipefail

CONFIG="/etc/sing-box/config.json"
TAG="ads"
RULESET_URL="https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs"
SERVICE_NAME="sing-box"

if [ "$(id -u)" -ne 0 ]; then
  echo "请用 root 权限运行" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo ">> 安装 jq..."
  if command -v apt >/dev/null 2>&1; then
    apt update -y && apt install -y jq
  elif command -v yum >/dev/null 2>&1; then
    yum install -y jq
  else
    echo "无法自动安装 jq，请手动安装后重试" >&2
    exit 1
  fi
fi

if [ ! -f "$CONFIG" ]; then
  echo "未找到 $CONFIG，请确认路径是否正确" >&2
  exit 1
fi

BACKUP="${CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
cp "$CONFIG" "$BACKUP"
echo ">> 已备份原配置到 $BACKUP"

NEW_CONFIG=$(jq \
  --arg tag "$TAG" \
  --arg url "$RULESET_URL" \
  '
  .dns.rules = ((.dns.rules // []) | map(select(.rule_set != $tag))) + [{"rule_set": $tag, "action": "reject"}]
  | .route.rule_set = ((.route.rule_set // []) | map(select(.tag != $tag))) + [{"tag": $tag, "type": "remote", "format": "binary", "url": $url, "download_detour": "direct"}]
  ' "$CONFIG")

echo "$NEW_CONFIG" > "$CONFIG"
echo ">> 已写入去广告规则"

echo ">> 重启 sing-box 使配置生效..."
if sing-box restart >/dev/null 2>&1; then
  :
elif systemctl restart "$SERVICE_NAME" >/dev/null 2>&1; then
  :
else
  echo "!! 重启命令执行失败，自动回滚配置" >&2
  cp "$BACKUP" "$CONFIG"
  exit 1
fi

# 重启命令返回成功不代表服务真的在跑（配置有误 / 规则集下载失败时进程可能启动后立刻退出）
# 233boy 脚本自带的 "test" 步骤在服务已运行时会直接跳过、不做真实校验，
# 所以这里改用重启后的真实运行状态来判定是否需要回滚。
sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
  echo ">> 服务确认正常运行，去广告规则已生效"
else
  echo "!! 服务未能正常运行（可能是配置有误或规则集下载失败），自动回滚" >&2
  cp "$BACKUP" "$CONFIG"
  sing-box restart >/dev/null 2>&1 || systemctl restart "$SERVICE_NAME" || true
  exit 1
fi

echo ">> 完成。可用 'sing-box status' 或 'journalctl -u ${SERVICE_NAME} -n 50' 查看详情。"
