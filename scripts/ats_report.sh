#!/usr/bin/env bash
set -euo pipefail

ts(){ date -u +%Y%m%dT%H%M%SZ; }

tg_doc(){  # tg_doc <path> <caption>
  set -a; . /opt/ats-quant/.env; set +a
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
    -F "caption=${2}" -F "document=@${1}" >/dev/null || true
}

mask(){ awk '{if(length($0)>12){print substr($0,1,4)"***"substr($0,length($0)-3)}else{print "****"}}'; }

health(){
  mkdir -p /opt/ats-quant/reports
  local T="$(ts)" HOST="$(hostname)"

  # 采集信息
  local DVER=$(docker --version 2>&1 | tr -d '\r')
  local CVER=$(docker compose version 2>&1 | tr -d '\r')
  local PS="$(docker compose ps 2>&1 | tr -d '\r')"

  # 读取 .env（打码展示）
  set -a; . /opt/ats-quant/.env; set +a
  local ENV_MASK=$(printf "HOST_TAG=%s\nTRADING_ENABLED=%s DRY_RUN=%s\nBINANCE_API_KEY=%s\nTELEGRAM_BOT_TOKEN=%s\n" \
    "${HOST_TAG:-}" "${TRADING_ENABLED:-}" "${DRY_RUN:-}" \
    "$(printf %s "${BINANCE_API_KEY:-}" | mask)" \
    "$(printf %s "${TELEGRAM_BOT_TOKEN:-}" | mask)")

  # 网络连通
  local BIN_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "https://fapi.binance.com/fapi/v1/ping" || echo "000")
  local TG_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" || echo "000")

  # 汇总报告
  local OUT="/opt/ats-quant/reports/health_${T}.md"
  {
    echo "# ATS 健康自检 ${T}"
    echo "- Host: \`${HOST}\`"
    echo "- PWD: \`/opt/ats-quant\`"
    echo
    echo "## Docker"
    echo '```'; echo "${DVER}"; echo "${CVER}"; echo; echo "[compose ps]"; echo "${PS}"; echo '```'
    echo
    echo "## .env（打码）"
    echo '```'; echo "${ENV_MASK}"; echo '```'
    echo
    echo "## 连通性"
    echo "- Binance ping HTTP: \`${BIN_HTTP}\`（期望 200）"
    echo "- Telegram getMe HTTP: \`${TG_HTTP}\`（期望 200）"
  } > "${OUT}"

  tg_doc "${OUT}" "📋 ATS 健康报告 ${T}"

  # 附带最近1200行日志
  logs 1200
}

logs(){  # logs [N]
  mkdir -p /opt/ats-quant/reports
  local N="${1:-1200}"
  local T="$(ts)"
  docker logs --tail "${N}" ats-quant > "/opt/ats-quant/reports/ats_logs_${T}.txt" 2>&1 || true
  tg_doc "/opt/ats-quant/reports/ats_logs_${T}.txt" "📜 ATS 原始日志（最近${N}行） ${T}"
  echo "已发送最近${N}行日志到 Telegram"
}

cmd(){  # cmd '<命令...>'
  mkdir -p /opt/ats-quant/reports
  local T="$(ts)" OUT="/opt/ats-quant/reports/cmd_${T}.txt"
  bash -lc "$*" > "${OUT}" 2>&1 || true
  tg_doc "${OUT}" "🧰 ATS 远程命令输出 ${T}"
}

repo(){
  mkdir -p /opt/ats-quant/reports
  local T="$(ts)" OUT="/opt/ats-quant/reports/repo_${T}.md"
  {
    echo "# 仓库结构快照 ${T}"
    echo '```'
    (command -v tree >/dev/null && tree -L 2) || find . -maxdepth 2 -type d -printf '%p\n'
    echo '```'
  } > "${OUT}"
  tg_doc "${OUT}" "🗂️ ATS 仓库结构 ${T}"
}

case "${1:-health}" in
  health) health ;;
  logs) shift || true; logs "${1:-1200}" ;;
  cmd) shift; cmd "$*" ;;
  repo) repo ;;
  *) echo "用法：bash scripts/ats_report.sh {health|logs [N]|cmd '<命令>'|repo}" ;;
esac
