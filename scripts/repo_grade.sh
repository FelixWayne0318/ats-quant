#!/usr/bin/env bash
set -euo pipefail
ROOT="/opt/ats-quant"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${ROOT}/reports/repo_grade_${TS}.md"

# 读取 .env （仅为发电报，不会写入报告明文）
set +e
[ -f "${ROOT}/.env" ] && { set -a; . "${ROOT}/.env"; set +a; }
set -e

pass=1
warns=()

# ---------- 基本信息 ----------
BRANCH="$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
LAST="$(git -C "${ROOT}" log -1 --pretty=format:'%h %ad %s' --date=iso 2>/dev/null || echo 'n/a')"
CHANGES="$(git -C "${ROOT}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

# ---------- docker-compose 检查 ----------
COMPOSE="${ROOT}/docker-compose.yml"
[ -f "${COMPOSE}" ] || { echo "❌ 缺少 docker-compose.yml"; pass=0; }

HAS_ENV_FILE="no"; USES_MODULE="no"
if [ -f "${COMPOSE}" ]; then
  grep -q 'env_file' "${COMPOSE}" && HAS_ENV_FILE="yes"
  grep -q 'python -m ats.app' "${COMPOSE}" && USES_MODULE="yes"
  [ "${HAS_ENV_FILE}" = "no" ] && { warns+=("⚠️ docker-compose 未通过 env_file:.env 注入环境变量"); pass=0; }
  [ "${USES_MODULE}" = "no" ] && { warns+=("⚠️ 启动命令不是 python -m ats.app，可能导致相对导入失败"); pass=0; }
fi

# ---------- params.yml 关键项（用 sed 提取） ----------
PARAMS="${ROOT}/params.yml"
[ -f "${PARAMS}" ] || { echo "❌ 缺少 params.yml"; pass=0; }
MAX_SYM=""; MIN_QV=""; SCAN_MAX=""; SCAN_PAUSE=""
if [ -f "${PARAMS}" ]; then
  MAX_SYM=$(sed -n 's/^[[:space:]]*max_symbols:[[:space:]]*\([0-9]\+\)$/\1/p' "${PARAMS}" | head -n1)
  MIN_QV=$(sed -n 's/^[[:space:]]*min_quote_vol:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' "${PARAMS}" | head -n1)
  SCAN_MAX=$(sed -n 's/^[[:space:]]*max_symbols_per_scan:[[:space:]]*\([0-9]\+\)$/\1/p' "${PARAMS}" | head -n1)
  SCAN_PAUSE=$(sed -n 's/^[[:space:]]*per_symbol_pause_ms:[[:space:]]*\([0-9]\+\)$/\1/p' "${PARAMS}" | head -n1)

  # 规则：max_symbols <= 30（推荐 18）；min_quote_vol 必须有数值
  if [ -z "${MAX_SYM}" ]; then warns+=("⚠️ 未检测到 symbol_pool.max_symbols"); pass=0; fi
  if [ -n "${MAX_SYM}" ] && [ "${MAX_SYM}" -gt 30 ]; then warns+=("⚠️ max_symbols 太大=${MAX_SYM}（建议 ≤18）"); fi
  if [ -z "${MIN_QV}" ]; then warns+=("⚠️ 未检测到 symbol_pool.min_quote_vol 数值（不能是字符串 '2e7'）"); pass=0; fi
fi

# ---------- .gitignore ----------
IGNORE_OK="no"
if [ -f "${ROOT}/.gitignore" ]; then
  grep -qE '(^|/)\.env($|$)' "${ROOT}/.gitignore" && IGNORE_OK="yes"
fi
[ "${IGNORE_OK}" = "yes" ] || { warns+=("⚠️ .gitignore 未忽略 .env"); pass=0; }

# ---------- requirements ----------
REQS="${ROOT}/requirements.txt"
REQ_OK="yes"
missing=()
need=(pandas pyyaml requests loguru tenacity)
if [ -f "${REQS}" ]; then
  for r in "${need[@]}"; do
    if ! grep -qi "^${r}\b" "${REQS}"; then
      missing+=("${r}")
      REQ_OK="no"
    fi
  done
else
  REQ_OK="no"
fi
[ "${REQ_OK}" = "no" ] && { warns+=("⚠️ requirements 缺少: ${missing[*]}"); pass=0; }

# ---------- 脚本权限 ----------
SCRIPTS=(scripts/healthcheck.sh scripts/repo_snapshot.sh scripts/repo_audit_plus.sh)
for s in "${SCRIPTS[@]}"; do
  if [ -f "${ROOT}/${s}" ] && [ ! -x "${ROOT}/${s}" ]; then
    warns+=("⚠️ ${s} 无可执行权限（建议 chmod +x）")
  fi
done

# ---------- Python 语法编译（不导入第三方依赖） ----------
COMP_OK="true"
python3 - <<'PY' || COMP_OK="false"
import compileall; import sys
ok = compileall.compile_dir('ats', quiet=1)
sys.exit(0 if ok else 1)
PY
[ "${COMP_OK}" = "false" ] && { warns+=("⚠️ Python 语法编译失败（请检查 ats/*.py）"); pass=0; }

# ---------- 生成报告 ----------
{
  echo "# ATS 仓库体检（打分版） ${TS}"
  echo
  echo "## 结论"
  if [ "${pass}" -eq 1 ]; then
    echo "- ✅ PASS（关键项满足要求）"
  else
    echo "- ❌ FAIL（关键项存在问题，详见下方）"
  fi
  [ "${#warns[@]}" -gt 0 ] && { echo; echo "### 发现的问题"; for w in "${warns[@]}"; do echo "- ${w}"; done; }
  echo
  echo "## 基本信息"
  echo "- Branch: \`${BRANCH}\`"
  echo "- Last Commit: \`${LAST}\`"
  echo "- Local changes: \`${CHANGES}\`"
  echo
  echo "## docker-compose 关键项"
  echo "- env_file .env 注入: \`${HAS_ENV_FILE}\`"
  echo "- 模块方式启动 \`python -m ats.app\`: \`${USES_MODULE}\`"
  echo
  echo "## params 关键项（提取）"
  echo "- symbol_pool.max_symbols: \`${MAX_SYM:-unset}\`"
  echo "- symbol_pool.min_quote_vol: \`${MIN_QV:-unset}\`"
  echo "- scan.max_symbols_per_scan: \`${SCAN_MAX:-unset}\`"
  echo "- scan.per_symbol_pause_ms: \`${SCAN_PAUSE:-unset}\`"
  echo
  echo "## 其他检查"
  echo "- .gitignore 忽略 .env: \`${IGNORE_OK}\`"
  echo "- requirements 必备项齐全: \`$([ "${REQ_OK}" = "yes" ] && echo yes || echo no)\`"
  if [ "${REQ_OK}" = "no" ]; then echo "  - 缺失: \`${missing[*]}\`"; fi
  echo "- Python 语法编译 compileall: \`${COMP_OK}\`"
} > "${OUT}"

echo "✅ 报告已生成: ${OUT}"

# ---------- 发送电报 ----------
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID_PRIMARY:-}" ]; then
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
    -F "caption=ATS 仓库体检（打分版） ${TS}" \
    -F "document=@${OUT}" >/dev/null && echo "✅ 已发送到 Telegram" || echo "⚠️ 发送失败"
else
  echo "ℹ️ 未配置 TELEGRAM_BOT_TOKEN/CHAT_ID，跳过推送"
fi

# 控制台也顺便输出一行总评
if [ "${pass}" -eq 1 ]; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
fi
