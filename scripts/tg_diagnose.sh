#!/usr/bin/env bash
set -euo pipefail
APP_DIR="/opt/ats-quant"
ENV_FILE="$APP_DIR/.env"
LOG_DIR="$APP_DIR/logs"
mkdir -p "$LOG_DIR"

# 读取 .env
if [[ ! -f "$ENV_FILE" ]]; then echo "[FAIL] 未找到 $ENV_FILE"; exit 1; fi
while IFS='=' read -r k v; do
  [[ -z "$k" || "$k" =~ ^# ]] && continue
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  export "$k"="$v"
done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" || true)

: "${TELEGRAM_BOT_TOKEN:?缺少 TELEGRAM_BOT_TOKEN}"
: "${TELEGRAM_CHAT_ID_PRIMARY:?缺少 TELEGRAM_CHAT_ID_PRIMARY}"

echo "== 0) 到 Telegram 网络连通 =="
curl -sS -o /dev/null -w "%{http_code}\n" https://api.telegram.org

echo "== 1) getMe（验证 Token 是否有效）=="
curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe"; echo
BOT_ID=$(curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | sed -n 's/.*"id":[ ]*\([0-9]\+\).*/\1/p' | head -n1)

echo "== 2) getChat（用你的 ChatID 查询群）=="
curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getChat?chat_id=${TELEGRAM_CHAT_ID_PRIMARY}"; echo

echo "== 3) getChatMember（确认机器人在群里的身份）=="
curl -sS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getChatMember?chat_id=${TELEGRAM_CHAT_ID_PRIMARY}&user_id=${BOT_ID}"; echo

echo "== 4) sendMessage 测试（应返回 ok:true，并在群里出现一条文本）=="
curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID_PRIMARY}" \
  -d text="🔎 连通测试 $(date -u '+%F %T UTC') from $(hostname)" ; echo

# 找最近一份自检日志；没有就现跑一遍
LATEST=$(ls -1t "$LOG_DIR"/selfcheck_*.txt 2>/dev/null | head -n1 || true)
if [[ -z "${LATEST:-}" ]]; then
  echo "== 5) 未发现自检日志，现跑 /opt/ats-quant/self_check_v2.sh 生成 =="
  if [[ -x "$APP_DIR/self_check_v2.sh" ]]; then
    TS=$(date -u +%Y%m%d_%H%M%S)
    LATEST="$LOG_DIR/selfcheck_${TS}.txt"
    bash "$APP_DIR/self_check_v2.sh" | tee "$LATEST" || true
  else
    echo "[WARN] 没有自检脚本 $APP_DIR/self_check_v2.sh，跳过文件发送"
  fi
fi

if [[ -f "${LATEST:-/dev/null}" ]]; then
  echo "== 6) sendDocument 发送日志文件：$LATEST =="
  RESP=$(curl -sS -F chat_id="${TELEGRAM_CHAT_ID_PRIMARY}" \
               -F caption="🧪 ATS 自检日志 $(basename "$LATEST") — $(hostname)" \
               -F document=@"$LATEST" \
               "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument")
  echo "$RESP"
  echo "$RESP" | grep -q '"ok":true' || {
    echo "== 6b) 文件失败，改为分段文本 =="
    split -b 3500 "$LATEST" "$LATEST.part."
    for f in "$LATEST.part."*; do
      curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID_PRIMARY}" --data-urlencode text@"$f" >/dev/null || true
    done
    echo "[OK] 已改用分段文本发送。"
  }
fi
