#!/usr/bin/env bash
set -euo pipefail
APP="/opt/ats-quant"; LOG="$APP/logs"; SELF="$APP/self_check_v2.sh"; ENVF="$APP/.env"
mkdir -p "$LOG"

# 读 .env（只导入 KEY=VAL）
while IFS='=' read -r k v; do [[ -z "$k" || "$k" =~ ^# ]] && continue; v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"; export "$k"="$v"; done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENVF" || true)

TS=$(date -u +%Y%m%d_%H%M%S); OUT="$LOG/selfcheck_${TS}.txt"; HOST=$(hostname)
# 跑全面自检并落盘（不中断）
bash "$SELF" | tee "$OUT" || true

# 发送：①常规 ②IP 直连 ③分段文本兜底（全程强制 IPv4）
CAPTION="🧪 ATS 自检报告 ${TS} (UTC) — ${HOST}"
RESP=$(curl -sS -4 -m 25 -F chat_id="$TELEGRAM_CHAT_ID_PRIMARY" -F caption="$CAPTION" -F document=@"$OUT" \
       "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" || true)
if ! echo "$RESP" | grep -q '"ok":true'; then
  for IP in 149.154.167.220 149.154.167.233 149.154.167.198; do
    RESP=$(curl -sS -4 -m 25 --resolve api.telegram.org:443:$IP \
           -F chat_id="$TELEGRAM_CHAT_ID_PRIMARY" -F caption="$CAPTION" -F document=@"$OUT" \
           "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" || true)
    echo "sendDocument($IP) => $RESP"
    echo "$RESP" | grep -q '"ok":true' && break
  done
fi
if ! echo "$RESP" | grep -q '"ok":true'; then
  echo "[WARN] sendDocument failed, fallback to chunked text."
  split -b 3500 "$OUT" "$OUT.part." || true
  for f in "$OUT.part."*; do
    [ -f "$f" ] || continue
    curl -sS -4 -m 20 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID_PRIMARY" --data-urlencode text@"$f" >/dev/null || true
  done
fi
echo "[OK] report sent (file or chunked text)."
