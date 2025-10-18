#!/usr/bin/env bash
set -euo pipefail
APP_DIR="/opt/ats-quant"
cd "$APP_DIR"

# 读 .env（安全导入 KEY=VAL）
while IFS='=' read -r k v; do
  [[ -z "$k" || "$k" =~ ^# ]] && continue
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  export "$k"="$v"
done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' ".env" || true)

tg(){ # 失败不终止
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID_PRIMARY:-}" ] || return 0
  curl -sS -4 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID_PRIMARY" \
    --data-urlencode text="$1" >/dev/null || true
}

# 拉取并判断是否有更新
OLD=$(git rev-parse HEAD 2>/dev/null || echo "")
git fetch origin
NEW=$(git rev-parse origin/main)

if [ "$OLD" = "$NEW" ]; then
  tg "ℹ️ 无更新 | $(hostname)"
  exit 0
fi

tg "⬇️ 拉取更新… | $(hostname)"
git reset --hard "$NEW"

tg "♻️ 重建并重启容器… | $(hostname)"
docker compose up -d --build

sleep 2
if docker ps --format '{{.Names}}: {{.Status}}' | grep -q '^ats-quant:'; then
  tg "✅ 部署完成 | $(hostname)"
else
  tg "❌ 部署失败（容器未运行）| $(hostname)"
fi