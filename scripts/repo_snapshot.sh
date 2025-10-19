#!/usr/bin/env bash
set -euo pipefail
ROOT="/opt/ats-quant"
REPORT_DIR="${ROOT}/reports"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${REPORT_DIR}/repo_snapshot_${TS}.md"

mkdir -p "${REPORT_DIR}"

# 读 .env（只为发送电报，生成报告时会打码）
set +e
if [ -f "${ROOT}/.env" ]; then set -a; . "${ROOT}/.env"; set +a; fi
set -e

mask () { # 打码
  local s="$1"; local n=${#s}
  [ -z "$s" ] && { echo ""; return; }
  [ "$n" -le 8 ] && { echo "***"; return; }
  echo "${s:0:4}$(printf '%*s' $((n-8)) | tr ' ' '*')${s: -4}"
}

# 基本 Git 信息
BRANCH="$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
LAST="$(git -C "${ROOT}" log -1 --pretty=format:'%h %ad %s' --date=iso 2>/dev/null || echo 'n/a')"
REMOTE="$(git -C "${ROOT}" remote -v 2>/dev/null | sed 's/\t/  /g' || true)"
CHANGES="$(git -C "${ROOT}" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

# docker-compose 关键检查
COMPOSE="${ROOT}/docker-compose.yml"
HAS_ENV_FILE=$(grep -q 'env_file' "${COMPOSE}" 2>/dev/null && echo "yes" || echo "no")
USES_MODULE=$(grep -q 'python -m ats.app' "${COMPOSE}" 2>/dev/null && echo "yes" || echo "no")

# params 关键参数（用 sed 提取，尽量兼容）
MAX_SYM=$(sed -n 's/^[[:space:]]*max_symbols:[[:space:]]*\([0-9]\+\)$/\1/p' "${ROOT}/params.yml" | head -n1)
MIN_QV=$(sed -n 's/^[[:space:]]*min_quote_vol:[[:space:]]*\([0-9][0-9]*\).*$/\1/p' "${ROOT}/params.yml" | head -n1)
SCAN_MAX=$(sed -n 's/^[[:space:]]*max_symbols_per_scan:[[:space:]]*\([0-9]\+\)$/\1/p' "${ROOT}/params.yml" | head -n1)
SCAN_PAUSE=$(sed -n 's/^[[:space:]]*per_symbol_pause_ms:[[:space:]]*\([0-9]\+\)$/\1/p' "${ROOT}/params.yml" | head -n1)

# 统计
PY_COUNT=$(find "${ROOT}" -type f -name "*.py" -not -path "*/.git/*" | wc -l | tr -d ' ')
SH_COUNT=$(find "${ROOT}/scripts" -type f -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')
YML_COUNT=$(find "${ROOT}" -type f -name "*.yml" -o -name "*.yaml" | wc -l | tr -d ' ')
MD_COUNT=$(find "${ROOT}" -type f -name "*.md" | wc -l | tr -d ' ')
LOC_PY=$(find "${ROOT}" -type f -name "*.py" -not -path "*/.git/*" -print0 | xargs -0 -I{} wc -l "{}" | awk 'END{print $1}')
LOC_SH=$(find "${ROOT}/scripts" -type f -name "*.sh" 2>/dev/null -print0 | xargs -0 -I{} wc -l "{}" 2>/dev/null | awk 'END{print $1+0}')

# 文件树（最多 3 层，过滤常见大目录）
TREE=$( \
  cd "${ROOT}" && \
  find . -maxdepth 3 -type f \
    -not -path "./.git/*" \
    -not -path "./data/*" \
    -not -path "./db/*" \
    -not -path "./reports/*" \
    | sed 's#^\./##' | sort \
)

# Python 依赖关系（仅 ats.* 绝对导入；相对导入会标注为 relative）
DEPS=$(
python3 - <<'PY'
import os, ast, sys, pathlib, json
root = pathlib.Path("/opt/ats-quant")
edges = []
rel_refs = 0
for p in root.rglob("*.py"):
    if "/.git/" in str(p): 
        continue
    mod = str(p.relative_to(root)).replace("/", ".").removesuffix(".py")
    try:
        tree = ast.parse(p.read_text(encoding="utf-8"), filename=str(p))
    except Exception:
        continue
    pkg = ".".join(mod.split(".")[:-1])
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            for a in n.names:
                if a.name.startswith("ats."):
                    edges.append((mod, a.name))
        elif isinstance(n, ast.ImportFrom):
            # 绝对 from ats.x import y
            if n.level == 0 and n.module and n.module.startswith("ats."):
                edges.append((mod, n.module))
            elif n.level>0:  # 相对导入，做个标记
                rel_refs += 1
print(json.dumps({"edges": edges, "rel": rel_refs}))
PY
)

# 生成报告
{
  echo "# ATS 仓库快照 ${TS}"
  echo
  echo "## 基本信息"
  echo "- Host: \`$(hostname)\`"
  echo "- PWD: \`${ROOT}\`"
  echo "- Branch: \`${BRANCH}\`"
  echo "- Last Commit: \`${LAST}\`"
  echo "- Local changes: \`${CHANGES}\`"
  echo
  echo "Remotes:"
  echo '```'
  echo "${REMOTE}"
  echo '```'
  echo
  echo "## 计数统计"
  echo "- Python files: \`${PY_COUNT}\`  (LOC≈\`${LOC_PY}\`)"
  echo "- Shell scripts: \`${SH_COUNT}\` (LOC≈\`${LOC_SH}\`)"
  echo "- YAML: \`${YML_COUNT}\`   Markdown: \`${MD_COUNT}\`"
  echo
  echo "## docker-compose 关键项"
  echo "- env_file .env 注入: \`${HAS_ENV_FILE}\`  |  模块启动 \`python -m ats.app\`: \`${USES_MODULE}\`"
  echo
  echo "## params 关键项"
  echo "- symbol_pool.max_symbols: \`${MAX_SYM:-unset}\`"
  echo "- symbol_pool.min_quote_vol: \`${MIN_QV:-unset}\`"
  echo "- scan.max_symbols_per_scan: \`${SCAN_MAX:-unset}\`"
  echo "- scan.per_symbol_pause_ms: \`${SCAN_PAUSE:-unset}\`"
  echo
  echo "## .env（打码）"
  echo "- BINANCE_API_KEY: \`$(mask "${BINANCE_API_KEY:-}")\`"
  echo "- BINANCE_API_SECRET: \`$(mask "${BINANCE_API_SECRET:-}")\`"
  echo "- TELEGRAM_BOT_TOKEN: \`$(mask "${TELEGRAM_BOT_TOKEN:-}")\`"
  echo "- TELEGRAM_CHAT_ID_PRIMARY: \`${TELEGRAM_CHAT_ID_PRIMARY:-}\`"
  echo
  echo "## 目录树（3 层内）"
  echo '```'
  echo "${TREE}"
  echo '```'
  echo
  echo "## Python 内部依赖（ats.* 绝对导入）"
  echo '```'
  echo "${DEPS}"
  echo '```'
  echo
  echo "## 快速体检结论"
  WARN=0
  [ "${HAS_ENV_FILE}" != "yes" ] && { echo "- ⚠️ docker-compose **未**通过 \`env_file: .env\` 注入环境变量"; WARN=1; }
  [ "${USES_MODULE}" != "yes" ] && { echo "- ⚠️ 启动命令不是 \`python -m ats.app\`，相对导入可能报错"; WARN=1; }
  [ -z "${MAX_SYM:-}" ] && { echo "- ⚠️ params.yml 未设置 \`symbol_pool.max_symbols\`"; WARN=1; }
  [ -z "${MIN_QV:-}" ] && { echo "- ⚠️ params.yml 未设置 \`symbol_pool.min_quote_vol\`"; WARN=1; }
  [ -z "${SCAN_MAX:-}" ] && { echo "- ℹ️ 未设置 \`scan.max_symbols_per_scan\`（将采用代码默认值）"; }
  [ -z "${SCAN_PAUSE:-}" ] && { echo "- ℹ️ 未设置 \`scan.per_symbol_pause_ms\`（将采用代码默认值）"; }
  [ "${CHANGES}" != "0" ] && { echo "- ℹ️ 工作区有本地改动数量：${CHANGES}（如需对齐远端可 \`git reset --hard origin/main\`）"; }
  [ "${WARN}" = "0" ] && echo "- ✅ 关键配置看起来正常"
} > "${OUT}"

echo "✅ 报告已生成: ${OUT}"

# 发送到 Telegram（如已配置）
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID_PRIMARY:-}" ]; then
  echo "尝试发送到 Telegram..."
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
    -F "caption=ATS 仓库快照 ${TS}" \
    -F "document=@${OUT}" >/dev/null \
    && echo "✅ 已发送到 Telegram" \
    || echo "⚠️ 发送失败（网络或 chat_id/token 问题）"
else
  echo "ℹ️ 未配置 TELEGRAM_BOT_TOKEN/CHAT_ID，跳过推送"
fi
