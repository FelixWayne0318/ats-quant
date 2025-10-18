#!/usr/bin/env bash
set -euo pipefail
TEXT="${1:-Hello from ATS}"
BOT="${TELEGRAM_BOT_TOKEN:-}"
CHAT="${TELEGRAM_CHAT_ID_PRIMARY:-}"
if [[ -z "${BOT}" || -z "${CHAT}" ]]; then
  echo "BOT/CHAT not set"; exit 1
fi
curl -sS -X POST "https://api.telegram.org/bot${BOT}/sendMessage" \
  -d "chat_id=${CHAT}" -d "parse_mode=Markdown" \
  --data-urlencode "text=${TEXT}" >/dev/null && echo "OK"
