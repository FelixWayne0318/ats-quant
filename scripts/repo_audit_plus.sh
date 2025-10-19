#!/usr/bin/env bash
set -euo pipefail
ROOT="/opt/ats-quant"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${ROOT}/reports/repo_audit_${TS}.md"

# 读 .env（仅用于发电报；报告里不输出明文）
set +e
[ -f "${ROOT}/.env" ] && { set -a; . "${ROOT}/.env"; set +a; }
set -e

# ------- 收集内容 -------
BRANCH="$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
LAST="$(git -C "${ROOT}" log -1 --pretty=format:'%h %ad %s' --date=iso 2>/dev/null || echo 'n/a')"
REMOTE="$(git -C "${ROOT}" remote -v 2>/dev/null | sed 's/\t/  /g' || true)"
CHANGES="$(git -C "${ROOT}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

# 文件树（3层）
TREE=$(cd "${ROOT}" && find . -maxdepth 3 -type f \
  -not -path "./.git/*" -not -path "./data/*" -not -path "./db/*" -not -path "./reports/*" \
  | sed 's#^\./##' | sort)

# compose / params / req / ignore
COMPOSE="$( [ -f docker-compose.yml ] && cat docker-compose.yml || echo '(missing docker-compose.yml)' )"
PARAMS="$( [ -f params.yml ] && cat params.yml || echo '(missing params.yml)' )"
REQS="$( [ -f requirements.txt ] && cat requirements.txt || echo '(missing requirements.txt)' )"
GITIGNORE="$( [ -f .gitignore ] && cat .gitignore || echo '(missing .gitignore)' )"

# 脚本列表与权限
SCRIPTS_LIST="$( [ -d scripts ] && ls -l scripts || echo '(no scripts directory)' )"

# ats 目录概览（行数/文件大小）
ATS_WC="$(find ats -maxdepth 1 -type f -name '*.py' -print0 2>/dev/null | xargs -0 -I{} sh -c 'wc -l "{}";' 2>/dev/null || true)"
ATS_DU="$(du -h ats/*.py 2>/dev/null || true)"

# Python 静态编译测试（语法+导入基础）
PYCHK=$(
python3 - <<'PY'
import sys, compileall, pkgutil, json, traceback
ok = compileall.compile_dir('ats', quiet=1)
err = None
try:
    # 仅测试能否遍历包，不执行网络逻辑
    import ats
except Exception as e:
    err = "".join(traceback.format_exception_only(type(e), e)).strip()
print(json.dumps({"compile_ok": bool(ok), "import_error": err}))
PY
)

# ------- 写报告 -------
{
  echo "# ATS 仓库审计（增强版） ${TS}"
  echo
  echo "## Git"
  echo "- Branch: \`${BRANCH}\`"
  echo "- Last: \`${LAST}\`"
  echo "- Local changes: \`${CHANGES}\`"
  echo
  echo "Remotes:"
  echo '```'
  echo "${REMOTE}"
  echo '```'
  echo
  echo "## 目录树（3 层内）"
  echo '```'
  echo "${TREE}"
  echo '```'
  echo
  echo "## docker-compose.yml"
  echo '```yaml'
  echo "${COMPOSE}"
  echo '```'
  echo
  echo "## params.yml"
  echo '```yaml'
  echo "${PARAMS}"
  echo '```'
  echo
  echo "## requirements.txt"
  echo '```'
  echo "${REQS}"
  echo '```'
  echo
  echo "## .gitignore（关键信息：应包含 .env）"
  echo '```'
  echo "${GITIGNORE}"
  echo '```'
  echo
  echo "## scripts/ 列表与权限"
  echo '```'
  echo "${SCRIPTS_LIST}"
  echo '```'
  echo
  echo "## ats/*.py 行数与大小"
  echo '```'
  echo "${ATS_WC}"
  echo
  echo "${ATS_DU}"
  echo '```'
  echo
  echo "## Python 静态检查（compile/import）"
  echo '```json'
  echo "${PYCHK}"
  echo '```'
} > "${OUT}"

echo "✅ 报告已生成: ${OUT}"

# 发送到 Telegram（如配置）
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID_PRIMARY:-}" ]; then
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
    -F "caption=ATS 仓库审计 ${TS}" \
    -F "document=@${OUT}" >/dev/null && echo "✅ 已发送到 Telegram" || echo "⚠️ 发送失败"
else
  echo "ℹ️ 未配置 TELEGRAM_BOT_TOKEN/CHAT_ID，跳过推送"
fi
