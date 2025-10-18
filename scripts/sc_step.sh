#!/usr/bin/env bash
set -euo pipefail
echo "[DNS] ping fapi.binance.com"; ping -c 1 fapi.binance.com || true
echo "[Docker] version"; docker --version
echo "[Docker] compose"; docker compose version 2>/dev/null || docker-compose -v 2>/dev/null || true
echo "[Git] status"; git -C /opt/ats-quant status -sb || true
echo "[Telegram] send test"
source .env 2>/dev/null || true
scripts/sc_send.sh "✅ ATS 自检：网络正常 $(date -u +"%F %T") UTC" || true
echo "All steps done."
