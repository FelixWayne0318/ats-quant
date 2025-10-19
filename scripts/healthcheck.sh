#!/usr/bin/env bash
set -euo pipefail

ROOT="/opt/ats-quant"
REPORT_DIR="${ROOT}/reports"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT="${REPORT_DIR}/health_${TS}.md"

mkdir -p "${REPORT_DIR}"

# 读取 .env（如存在）
set +e
if [ -f "${ROOT}/.env" ]; then
  set -a; . "${ROOT}/.env"; set +a
fi
set -e

mask() {  # 简单打码
  s="$1"; n=${#s}
  [ -z "$s" ] && { echo ""; return; }
  [ "$n" -le 8 ] && { echo "***"; return; }
  head="${s:0:4}"; tail="${s:n-4:4}"
  printf "%s%s%s" "$head" "$(printf '%*s' $((n-8)) | tr ' ' '*')" "$tail"
}

# 基本信息
HOST="$(hostname)"
NOW="$(date -u +'%F %T')"

# Git 信息
BRANCH="$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
LAST="$(git -C "${ROOT}" log -1 --pretty=format:'%h %ad %s' --date=iso 2>/dev/null || echo 'n/a')"
REMOTE="$(git -C "${ROOT}" remote -v 2>/dev/null || echo 'n/a')"

# Docker 与容器状态
if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"; else COMPOSE="docker-compose"; fi
DOCKER_VER="$(docker --version 2>/dev/null || echo 'docker: not found')"
COMPOSE_VER="$(${COMPOSE} version 2>/dev/null || echo 'compose: not found')"
PS="$(${COMPOSE} -f ${ROOT}/docker-compose.yml ps 2>/dev/null || echo 'compose ps: n/a')"
LOGS="$(docker logs --tail=120 ats-quant 2>&1 || true)"

# 网络连通（200/204 视为成功）
BIN_HTTP="$(curl -s -o /dev/null -w '%{http_code}' https://fapi.binance.com/fapi/v1/ping || echo 000)"
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  TG_HTTP="$(curl -s -o /dev/null -w '%{http_code}' "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" || echo 000)"
else
  TG_HTTP="(token-empty)"
fi

# 写报告
{
  echo "# ATS 健康自检 ${TS}"
  echo "- Host: \`${HOST}\`"
  echo "- Time(UTC): \`${NOW}\`"
  echo "- PWD: \`$(pwd)\`"
  echo
  echo "## Git"
  echo "- Branch: \`${BRANCH}\`"
  echo "- Last: \`${LAST}\`"
  echo
  echo "Remotes:"
  echo '```'
  echo "${REMOTE}"
  echo '```'
  echo
  echo "## Docker"
  echo '```'
  echo "${DOCKER_VER}"
  echo "${COMPOSE_VER}"
  echo
  echo "[compose ps]"
  echo "${PS}"
  echo '```'
  echo
  echo "## .env（打码展示）"
  echo "- HOST_TAG: \`${HOST_TAG:-}\`"
  [ -n "${BINANCE_API_KEY:-}" ] && echo "- BINANCE_API_KEY: \`$(mask "${BINANCE_API_KEY}")\`"
  [ -n "${BINANCE_API_SECRET:-}" ] && echo "- BINANCE_API_SECRET: \`$(mask "${BINANCE_API_SECRET}")\`"
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && echo "- TELEGRAM_BOT_TOKEN: \`$(mask "${TELEGRAM_BOT_TOKEN}")\`"
  echo "- TRADING_ENABLED: \`${TRADING_ENABLED:-}\`  DRY_RUN: \`${DRY_RUN:-}\`"
  echo
  echo "## 网络连通"
  echo "- Binance ping HTTP: \`${BIN_HTTP}\`（期望 200）"
  echo "- Telegram getMe HTTP: \`${TG_HTTP}\`（期望 200）"
  echo
  echo "## 容器日志（最近120行）"
  echo '```'
  echo "${LOGS}"
  echo '```'
} > "${REPORT}"

echo "✅ 报告已生成: ${REPORT}"

# 发送到 Telegram（如可用）
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID_PRIMARY:-}" ]; then
  echo "尝试发送到 Telegram..."
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
    -F "caption=ATS 健康自检 ${TS} (host=${HOST_TAG:-${HOST}})" \
    -F "document=@${REPORT}" >/dev/null \
    && echo "✅ 已发送到 Telegram" \
    || echo "⚠️ 发送失败（网络可能不可达），请手工查看 ${REPORT}"
else
  echo "⚠️ 未设置 TELEGRAM_BOT_TOKEN/CHAT_ID，已跳过推送。"
fi
