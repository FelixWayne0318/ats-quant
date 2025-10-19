#!/usr/bin/env bash
set -euo pipefail
ROOT="/opt/ats-quant"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${ROOT}/reports"
CNAME="${1:-ats-quant}"          # 容器名，默认 ats-quant
TAIL="${TAIL:-2000}"             # 可导出行数（默认 2000）
SINCE="${SINCE:-}"               # 可设 --since 时间窗口（如 3h / 1h / 15m）

mkdir -p "${OUT_DIR}"

# 读 .env 只为发电报（不把密钥写入报告）
set +e
[ -f "${ROOT}/.env" ] && { set -a; . "${ROOT}/.env"; set +a; }
set -e

LOG="${OUT_DIR}/docker_${CNAME}_${TS}.log"
SUM="${OUT_DIR}/log_summary_${TS}.md"

# 抓日志（容器存在才抓）
if docker ps -a --format '{{.Names}}' | grep -qx "${CNAME}"; then
  if [ -n "${SINCE}" ]; then
    docker logs --since "${SINCE}" "${CNAME}" > "${LOG}" 2>&1 || true
  else
    docker logs --tail "${TAIL}" "${CNAME}" > "${LOG}" 2>&1 || true
  fi
else
  echo "[WARN] container ${CNAME} not found" > "${LOG}"
fi

# 快速统计
rate418=$(grep -c -E '\b418\b' "${LOG}" || true)
rate429=$(grep -c -E '\b429\b' "${LOG}" || true)
rate1003=$(grep -c -E '-1003' "${LOG}" || true)
errors=$(grep -ci 'ERROR' "${LOG}" || true)
exceptions=$(grep -ci 'Traceback|exception' "${LOG}" || true)
scans=$(grep -c '扫描完成' "${LOG}" || true)
last_cand=$(grep '扫描完成' "${LOG}" | tail -n1 | sed -E 's/.*候选[[:space:]]+([0-9]+).*/\1/' || true)
build_tag=$(grep -m1 -E 'Build:' "${LOG}" | sed -E 's/.*Build:\s*`?([^`]+)`?.*/\1/' || true)
sleep_ticks=$(grep -c 'sleep [0-9]\+s until' "${LOG}" || true)

# Git/compose 摘要
BRANCH="$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '-')"
LAST="$(git -C "${ROOT}" log -1 --pretty=format:'%h %ad %s' --date=iso 2>/dev/null || echo '-')"

# 生成速览报告
{
  echo "# ATS 日志速览 ${TS}"
  echo "- Container: \`${CNAME}\`"
  echo "- Branch: \`${BRANCH}\`"
  echo "- Last commit: \`${LAST}\`"
  echo "- Build tag: \`${build_tag:-unknown}\`"
  echo "- Scans detected: \`${scans}\`（last candidates=\`${last_cand:-?}\`）"
  echo "- Sleep ticks: \`${sleep_ticks}\`（应 >0，表示确实按节奏休眠）"
  echo "- Rate-limit 命中：418=\`${rate418}\`，429=\`${rate429}\`，-1003=\`${rate1003}\`"
  echo "- ERROR 行：\`${errors}\`；Exceptions：\`${exceptions}\`"
  echo
  echo "## docker compose ps"
  docker compose ps || true
  echo
  echo "## Tail 预览（末尾 30 行）"
  tail -n 30 "${LOG}" || true
  echo
  echo "## params.yml 摘要"
} > "${SUM}"

# 追加 params 关键项（用 Python 读 YAML）
python3 - <<'PY' >> "${SUM}"
import yaml, json, pathlib
p = pathlib.Path('/opt/ats-quant/params.yml')
print()
if p.exists():
    params = yaml.safe_load(p.read_text()) or {}
    sp = params.get('symbol_pool', {}) or {}
    sc = params.get('scan', {}) or {}
    thD = (params.get('thresholds', {}) or {}).get('D', {}) or {}
    print(f"- symbol_pool: max_symbols={sp.get('max_symbols')}  min_quote_vol={sp.get('min_quote_vol')}")
    print(f"- scan: max_symbols_per_scan={sc.get('max_symbols_per_scan')}  per_symbol_pause_ms={sc.get('per_symbol_pause_ms')}  tickers_cache_sec={sc.get('tickers_cache_sec')}")
    print(f"- thresholds.D: spread_bps={thD.get('spread_bps')}  impact_bps={thD.get('impact_bps')}  obi_abs={thD.get('obi_abs')}  room_atr_min={thD.get('room_atr_min')}  cost_R_max={thD.get('cost_R_max')}")
else:
    print("(params.yml not found)")
PY

echo "✅ 已生成："
echo "  - ${SUM}"
echo "  - ${LOG}"

# 推送到电报（如配置）
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID_PRIMARY:-}" ]; then
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
    -F "caption=ATS 日志速览 ${TS}（含统计）" \
    -F "document=@${SUM}" >/dev/null && echo "✅ 速览已发送" || echo "⚠️ 速览发送失败"

  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
    -F "caption=ATS 原始日志 ${TS}" \
    -F "document=@${LOG}" >/dev/null && echo "✅ 日志已发送" || echo "⚠️ 日志发送失败"
else
  echo "ℹ️ 未配置 TELEGRAM_BOT_TOKEN/CHAT_ID，跳过推送"
fi
