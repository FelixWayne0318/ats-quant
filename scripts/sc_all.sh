#!/usr/bin/env bash
set -Eeuo pipefail
. /opt/ats-quant/scripts/sc_send.sh
TS="$(date -u +%Y-%m-%d_%H%M%S)"
send_msg "🧪 分步自检开始 ${TS} UTC | $(hostname)"
for S in telegram github binance docker cron system; do
  bash /opt/ats-quant/scripts/sc_step.sh "$S" || true
  sleep 2
done
TS2="$(date -u +%Y-%m-%d_%H%M%S)"
send_msg "✅ 分步自检完成 ${TS2} UTC | $(hostname)"
