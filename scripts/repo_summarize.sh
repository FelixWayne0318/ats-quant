#!/usr/bin/env bash
set -euo pipefail
ROOT="/opt/ats-quant"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="${ROOT}/reports/repo_summary_${TS}.md"

# 读取 .env 只为推送电报（不会写明文到报告）
set +e
[ -f "${ROOT}/.env" ] && { set -a; . "${ROOT}/.env"; set +a; }
set -e

python3 - <<'PY' > "${OUT}"
import os, ast, json, textwrap, pathlib, datetime, re, sys, yaml
root = pathlib.Path("/opt/ats-quant")
ts = os.popen("date -u +%Y-%m-%dT%H:%M:%SZ").read().strip()

def read(p):
    try: return p.read_text(encoding="utf-8")
    except: return ""

def doc1(mod_src):
    try:
        m = ast.parse(mod_src)
        d = ast.get_docstring(m) or ""
        return (d.strip().splitlines() or [""])[0][:160]
    except: return ""

def list_defs(mod_src):
    fn, cl = [], []
    try:
        m = ast.parse(mod_src)
        for n in m.body:
            if isinstance(n, ast.FunctionDef):
                fn.append(n.name)
            elif isinstance(n, ast.ClassDef):
                cl.append(n.name)
    except: pass
    return fn, cl

def edges_for(mod_name, mod_src):
    es = []
    try:
        m = ast.parse(mod_src)
        for n in ast.walk(m):
            if isinstance(n, ast.Import):
                for a in n.names:
                    if a.name.startswith("ats."): es.append((mod_name, a.name))
            elif isinstance(n, ast.ImportFrom):
                if n.level==0 and n.module and str(n.module).startswith("ats."):
                    es.append((mod_name, n.module))
    except: pass
    return es

# 基本信息
branch = os.popen("git -C /opt/ats-quant rev-parse --abbrev-ref HEAD 2>/dev/null").read().strip() or "unknown"
last   = os.popen("git -C /opt/ats-quant log -1 --pretty=format:'%h %ad %s' --date=iso 2>/dev/null").read().strip() or "n/a"
remote = os.popen("git -C /opt/ats-quant remote -v 2>/dev/null").read().strip()

# 目录树（3 层）
tree = os.popen(r"cd /opt/ats-quant && find . -maxdepth 3 -type f ! -path './.git/*' ! -path './data/*' ! -path './db/*' ! -path './reports/*' | sed 's#^\./##' | sort").read().strip()

# 汇总 ats 模块
mods = []
edges = []
for p in sorted((root/"ats").glob("*.py")):
    name = str(p.relative_to(root)).replace("/", ".").removesuffix(".py")
    src = read(p)
    d1  = doc1(src)
    fn, cl = list_defs(src)
    mods.append({"module": name, "doc": d1, "functions": fn, "classes": cl, "lines": src.count("\n")+1})
    edges += edges_for(name, src)

# 提炼“功能线索”（从命名与存在性推断，不执行代码）
have = {m["module"].split(".")[-1] for m in mods}
pipeline = []
if "binance" in have:   pipeline.append("BinanceFutures I/O")
if "base_pool" in have: pipeline.append("基础池构建 (24h tickers → 初筛)")
if "indicators" in have: pipeline.append("指标计算 (EMA/ATR/…)")
if "scoring" in have:   pipeline.append("评分 (趋势/结构/量能 → A+ 放行线)")
if "gates" in have:     pipeline.append("闸门 A/B/C/D（突破/回踩/拥挤/可执行）")
if "planner" in have:   pipeline.append("计划生成 (价带/SL/TP/仓位)")
if "risk" in have:      pipeline.append("风控 (R/预算/广度/簇)")
if "runner" in have:    pipeline.append("委托与 Runner（只上调/时间止损）")
if "notifier" in have:  pipeline.append("电报通知")
if "app" in have:       pipeline.append("调度（每小时 +15s 扫描/心跳）")

# 读取 params / compose 关键字段
params_text = read(root/"params.yml")
params = {}
try: params = yaml.safe_load(params_text) or {}
except: params = {}
sympool = params.get("symbol_pool", {})
scan    = params.get("scan", {})

compose_text = read(root/"docker-compose.yml")

# 生成报告
print(f"# ATS 代码结构与功能总结  {ts}")
print()
print("## 仓库信息")
print(f"- Branch: `{branch}`")
print(f"- Last: `{last}`")
print()
print("Remotes:")
print("```")
print(remote)
print("```")
print()
print("## 目录树（3 层内）")
print("```")
print(tree)
print("```")
print()
print("## 关键配置摘录")
print(f"- symbol_pool.max_symbols: `{sympool.get('max_symbols','unset')}`")
print(f"- symbol_pool.min_quote_vol: `{sympool.get('min_quote_vol','unset')}`")
print(f"- scan.max_symbols_per_scan: `{scan.get('max_symbols_per_scan','unset')}`")
print(f"- scan.per_symbol_pause_ms: `{scan.get('per_symbol_pause_ms','unset')}`")
print(f"- scan.tickers_cache_sec: `{scan.get('tickers_cache_sec','unset')}`")
print()
print("## docker-compose.yml（关键信息）")
flag_env = "env_file:" in compose_text
flag_cmd = "python -m ats.app" in compose_text
print(f"- env_file .env 注入: `{ 'yes' if flag_env else 'no' }`")
print(f"- 模块方式启动 python -m ats.app: `{ 'yes' if flag_cmd else 'no' }`")
print()
print("## 模块一览（按文件）")
for m in mods:
    fn = ", ".join(m["functions"][:8])
    cl = ", ".join(m["classes"][:6])
    if len(m["functions"])>8: fn += ", …"
    if len(m["classes"])>6:   cl += ", …"
    print(f"### {m['module']}  · {m['lines']} 行")
    if m["doc"]: print(f"> {m['doc']}")
    if cl: print(f"- 类: {cl}")
    if fn: print(f"- 函数: {fn}")
    print()
print("## 内部依赖（ats.* 绝对导入，源→目标）")
print("```json")
print(json.dumps({"edges": edges}, ensure_ascii=False))
print("```")
print()
print("## 交易流程（从代码结构推断）")
for i,step in enumerate(pipeline,1):
    print(f"{i}. {step}")
print()
print("—— 本报告仅基于源码静态解析生成（不运行容器，不调用外部接口）。")
PY

echo "✅ 报告已生成: ${OUT}"

# 发送到 Telegram（如配置）
if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID_PRIMARY:-}" ]; then
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
    -F "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
    -F "caption=ATS 代码结构总结 ${TS}" \
    -F "document=@${OUT}" >/dev/null \
    && echo "✅ 已发送到 Telegram" \
    || echo "⚠️ 发送失败（网络或 chat_id/token 问题）"
else
  echo "ℹ️ 未配置 TELEGRAM_BOT_TOKEN/CHAT_ID，跳过推送"
fi
