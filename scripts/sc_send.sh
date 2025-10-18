#!/usr/bin/env bash
set -Eeuo pipefail
APP_DIR="/opt/ats-quant"
ENV_FILE="$APP_DIR/.env"
[ -f "$ENV_FILE" ] && . "$ENV_FILE" || true

send_msg() {  # 用法：send_msg "文本"
  local text="$1"
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID_PRIMARY:-}" ]; then
    curl -sS -m 15 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
      --data-urlencode "text=${text}" \
      -d "disable_web_page_preview=true" >/dev/null || true
  fi
}

send_file() { # 用法：send_file "标题" /path/to/file
  local caption="$1" file="$2"
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID_PRIMARY:-}" ]; then
    curl -sS -m 45 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
      -F "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
      -F "caption=${caption}" \
      -F "document=@${file}" >/dev/null || true
  fi
}
