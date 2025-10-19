#!/usr/bin/env bash
set -euo pipefail

# ====== 基本变量 ======
REPO_DIR="/opt/ats-quant"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
NEW_BRANCH="feat/qf-v1.0-bootstrap-${TS}"   # 默认推到新分支，网页上合并到 main
TARGET_BRANCH="${1:-}"                       # 如想直接推 main，可执行：bash bootstrap_qf_v1.sh main

# ====== 预检 ======
cd "$REPO_DIR"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "这里不是 git 仓库"; exit 1; }
git fetch --all -p || true

# worktree 位置（临时，不污染当前工作区）
WT="/tmp/ats-wt-${TS}"
BR="${TARGET_BRANCH:-$NEW_BRANCH}"

# 创建/重置 worktree 分支
if git show-ref --verify --quiet "refs/heads/${BR}"; then
  git worktree add -f "${WT}" "${BR}"
else
  git worktree add -b "${BR}" "${WT}"
fi

# 在 worktree 下写入全部代码
cd "${WT}"
mkdir -p ats scripts data db reports

# ---------- 根目录 ----------
cat > .gitignore <<'EOF'
__pycache__/
*.pyc
*.pyo
*.pyd
*.log

.env
db/
data/
reports/
backups/
*.parquet
.parquet
*.pid
EOF

cat > docker-compose.yml <<'EOF'
version: "3.9"
services:
  ats-quant:
    image: python:3.11-slim
    container_name: ats-quant
    working_dir: /app
    volumes:
      - "./:/app"
    environment:
      - TZ=UTC
    command: ["sh","-c","pip install --no-cache-dir -r requirements.txt && python -u ats/app.py"]
    restart: unless-stopped
EOF

cat > requirements.txt <<'EOF'
requests==2.32.3
PyYAML==6.0.2
pandas==2.2.3
numpy==2.1.3
python-dateutil==2.9.0.post0
pyarrow==17.0.0
tenacity==9.0.0
loguru==0.7.2
EOF

cat > params.yml <<'EOF'
# ===== Quality-First v1.0 · Felix =====
sampling:
  main_interval: "1h"
  overlay_decay_hours: 2
thresholds:
  trend: { ema30_slope_min: 0.25, r2_min: 0.45 }
  struct:
    zigzag_min_atr: { base: 0.4, overlay: 0.6 }
    score_gate: { base: 0.70, overlay: 0.75, phaseA: 0.78 }
  volume:
    vboost_min: { base: 1.8, overlay: 2.7, phaseA: 3.2 }
    cvd_mix_pct: { long: 0.12, short: -0.12 }
    tib_abs_min: { base: 0.20, overlay: 0.30 }
  aplus: { min_total: 90, block_min: 65, chop_add: 5 }
  gates:
    A: { lookback: 72, breakout_pad: 0.002, close_outside: 0.003, body_atr_max: { default: 1.2, phaseA: 1.0 } }
    B:
      anchors: { L2_ema10_atr: 0.05, L1_breakout_atr: 0.10, L3_avwap_atr: 0.05 }
      confirm: { vboost: 1.3, tib_abs: 0.20, body_pct_min: 0.35, close_zone: 0.35, pullback_atr_max: 0.5, phaseA_pullback_tr: 0.45 }
    C: { funding_abs_max: 0.02, speed_pctl: 75, z_extreme: { big: 1.8, small: 2.3 } }  # 简化版：用绝对 funding 上限代替分位
    D: { impact_bps: 10, obi_abs: 0.30, spread_bps: 25, room_atr_min: 0.6, cost_R_max: 0.12 }
planner:
  weights:
    default: [0.6,0.3,0.1]
    hi: [0.7,0.2,0.1]
    lo: [0.5,0.4,0.1]
  tick_nudge_sec: 25
  atr_mult:
    entry: [0.25, 0.5, 0.75]   # L1/L2/L3 回撤倍数（LONG）
    sl: 1.2
    tp1: 0.6
    tp2: 1.8
risk:
  RISK_PCT: 0.005
  RISK_USDT_CAP: 6
  RISK_USDT_FLOOR: 3
  MAX_CONCURRENT_POS: 3
  HOURLY_RISK_BUDGET_PCT: 0.015
  MAX_PORTFOLIO_RISK_PCT: 0.02
  cooldown: { loss: "8h", profit: "3h" }
  breadth: { open_threshold: 0.60, tighten_threshold: 0.35 }
  bucket: { BTC: 2, ETH: 2, SOL: 2, BNB: 2, OTHER: 2 }
  cluster: { lookback_days: 7, corr_threshold: 0.65 }
symbol_pool:
  max_symbols: 60      # 从 24hr 排名前 N
  min_quote_vol: 2e7   # 24小时成交额下限（USDT）
trade:
  side: "LONG_ONLY"    # LONG_ONLY | SHORT_ONLY | BOTH
  maker_only: true
  reduce_only_stop: true
  black_window_minutes: 5
EOF

cat > README.md <<'EOF'
# ATS-Quant · QF v1.0（完整流程 · 模块化）

- 扫描节奏：整点 + 15s
- 选币：24hr tickers → 过滤 → Overlay（热点只增不减）
- 评分：趋势(40) / 结构(30) / 量能(30)，A+≥90 单块≥65
- 闸门：A 真突破 → B 回踩确认 → C 拥挤否决 → D 可执行性
- 计划：L1/L2/L3 限价（maker-only），SL/TP，权重
- 风控：R 体系、并发、冷却、黑窗
- Runner：成交后 BE→TP2，时间止损，异常自愈
- 通知：电报推送（计划/成交/Runner/异常/自检）
- 默认 `DRY_RUN=true`、`TRADING_ENABLED=false`（只模拟）

> `.env` 请只放服务器，不要入库。
EOF

# ---------- scripts ----------
cat > scripts/sc_send.sh <<'EOF'
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
EOF

cat > scripts/pull_and_restart.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cd /opt/ats-quant
git fetch --all -p
git checkout main || true
git pull --rebase origin main
docker compose up -d --build
docker logs --tail=50 ats-quant
EOF

cat > scripts/backup_simple.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p backups
tar --exclude='db/*' --exclude='data/*' -czf "backups/ats-code-${TS}.tgz" \
  docker-compose.yml requirements.txt params.yml .env \
  ats scripts README.md .gitignore || true
echo "Saved to backups/ats-code-${TS}.tgz"
EOF

cat > scripts/sc_step.sh <<'EOF'
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
EOF

cat > scripts/sc_all.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
bash scripts/sc_step.sh
EOF

chmod +x scripts/*.sh || true

# ---------- ats（第1批文件） ----------
cat > ats/__init__.py <<'EOF'
__all__ = []
EOF

cat > ats/config.py <<'EOF'
from pathlib import Path
import yaml

PARAMS_PATH = Path("params.yml")

def load_params():
    if not PARAMS_PATH.exists():
        return {}
    return yaml.safe_load(PARAMS_PATH.read_text(encoding="utf-8"))
EOF

cat > ats/utils.py <<'EOF'
from datetime import datetime, timezone, timedelta

def utcnow():
    return datetime.now(timezone.utc)

def next_hour_plus_15s(now=None):
    now = now or utcnow()
    target = now.replace(minute=0, second=15, microsecond=0)
    if now >= target:
        target += timedelta(hours=1)
    return target

def is_funding_black_window(now=None, minutes=5):
    """Binance funding at 00:00/08:00/16:00 UTC，±minutes 禁新开"""
    now = now or utcnow()
    if now.minute >= 60 - minutes or now.minute <= minutes:
        return now.hour in (0, 8, 16)
    return False

def pct(a, b, eps=1e-9):
    return (a - b) / max(abs(b), eps)
EOF

cat > ats/notifier.py <<'EOF'
import os, requests
from loguru import logger

BOT = os.getenv("TELEGRAM_BOT_TOKEN", "")
CHAT = os.getenv("TELEGRAM_CHAT_ID_PRIMARY", "")

def send_text(text: str, parse_mode: str = "Markdown") -> bool:
    if not (BOT and CHAT):
        logger.warning("TELEGRAM env not set; skip notify.")
        return False
    url = f"https://api.telegram.org/bot{BOT}/sendMessage"
    payload = {"chat_id": CHAT, "text": text, "parse_mode": parse_mode}
    try:
        r = requests.post(url, data=payload, timeout=10)
        if r.ok:
            return True
        logger.error(f"telegram error: {r.status_code} {r.text}")
    except Exception as e:
        logger.exception(e)
    return False

def send_file(path: str, caption: str = "") -> bool:
    if not (BOT and CHAT):
        logger.warning("TELEGRAM env not set; skip file.")
        return False
    url = f"https://api.telegram.org/bot{BOT}/sendDocument"
    try:
        with open(path, "rb") as f:
            r = requests.post(url, data={"chat_id": CHAT, "caption": caption}, files={"document": f}, timeout=30)
        if r.ok:
            return True
        logger.error(f"telegram file error: {r.status_code} {r.text}")
    except Exception as e:
        logger.exception(e)
    return False
EOF

cat > ats/store.py <<'EOF'
from pathlib import Path
import sqlite3
from loguru import logger

DB_DIR = Path("db")
DATA_DIR = Path("data")
DB_PATH = DB_DIR / "state.db"

DDL = """
CREATE TABLE IF NOT EXISTS cooldowns(
  symbol TEXT, side TEXT, until_utc INTEGER, reason TEXT,
  PRIMARY KEY(symbol, side)
);
CREATE TABLE IF NOT EXISTS clusters(
  date TEXT, symbol TEXT, cluster_id INTEGER,
  PRIMARY KEY(date, symbol)
);
CREATE TABLE IF NOT EXISTS risk_budget(
  ts INTEGER, hourly_used REAL, portfolio_R REAL
);
CREATE TABLE IF NOT EXISTS overlay_queue(
  ts INTEGER, symbol TEXT, heat REAL, last_touch_ts INTEGER,
  PRIMARY KEY(symbol)
);
CREATE TABLE IF NOT EXISTS plans(
  ts INTEGER, symbol TEXT, side TEXT,
  l1 REAL, l2 REAL, l3 REAL, w1 REAL, w2 REAL, w3 REAL,
  sl REAL, tp1 REAL, tp2 REAL, R REAL, costR REAL, room REAL,
  gates TEXT, mode TEXT
);
"""

def ensure_dirs():
    DB_DIR.mkdir(exist_ok=True, parents=True)
    DATA_DIR.mkdir(exist_ok=True, parents=True)

def connect():
    ensure_dirs()
    return sqlite3.connect(DB_PATH)

def ensure_schema():
    conn = connect()
    with conn:
        conn.executescript(DDL)
    conn.close()
    logger.info("SQLite schema ensured at {}", DB_PATH)
EOF

cat > ats/binance.py <<'EOF'
import os, hmac, hashlib, time, requests
from urllib.parse import urlencode
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential

BASE = os.getenv("BINANCE_FAPI_BASE", "https://fapi.binance.com")
KEY  = os.getenv("BINANCE_API_KEY", "")
SEC  = os.getenv("BINANCE_API_SECRET", "")

class BinanceFutures:
    def __init__(self, base=BASE, key=KEY, secret=SEC, timeout=10):
        self.base = base.rstrip("/")
        self.key = key
        self.secret = secret.encode()
        self.timeout = timeout
        self.sess = requests.Session()
        if key:
            self.sess.headers.update({"X-MBX-APIKEY": key})

    def _sign(self, params: dict):
        q = urlencode(params, doseq=True)
        sig = hmac.new(self.secret, q.encode(), hashlib.sha256).hexdigest()
        return f"{q}&signature={sig}"

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=0.5, min=0.5, max=2))
    def _request(self, method: str, path: str, params=None, signed=False):
        params = params or {}
        url = self.base + path
        if signed:
            params["timestamp"] = int(time.time()*1000)
            qs = self._sign(params)
            if method == "GET":
                url = f"{url}?{qs}"
                params = None
            else:
                # POST/DELETE 用 query 放签名，body 为空或只放必要字段
                url = f"{url}?{qs}"
                params = None
        r = self.sess.request(method, url, params=params if method=="GET" else None,
                              data=None if method=="GET" else params, timeout=self.timeout)
        if r.status_code >= 400:
            logger.error("Binance error {}: {}", r.status_code, r.text)
        r.raise_for_status()
        if r.text:
            return r.json()
        return {}

    # Public
    def ping(self):         return self._request("GET", "/fapi/v1/ping")
    def server_time(self):  return self._request("GET", "/fapi/v1/time")
    def exchange_info(self):return self._request("GET", "/fapi/v1/exchangeInfo")
    def tickers_24h(self):  return self._request("GET", "/fapi/v1/ticker/24hr")
    def klines(self, symbol="BTCUSDT", interval="1h", limit=200):
        return self._request("GET", "/fapi/v1/klines", params={"symbol": symbol, "interval": interval, "limit": limit})

    # Account (signed)
    def open_orders(self, symbol=None):
        p = {"symbol": symbol} if symbol else {}
        return self._request("GET", "/fapi/v1/openOrders", params=p, signed=True)
    def position_risk(self): return self._request("GET", "/fapi/v2/positionRisk", signed=True)
    def account(self):       return self._request("GET", "/fapi/v2/account", signed=True)
    def funding_rate(self, symbol, limit=7):  # 最近几次 funding
        return self._request("GET", "/fapi/v1/fundingRate", params={"symbol": symbol, "limit": limit})

    # Orders
    def new_order(self, **kwargs):
        # 例：symbol, side, type, quantity, price, timeInForce=GTC, reduceOnly, newClientOrderId, ...
        return self._request("POST", "/fapi/v1/order", params=kwargs, signed=True)
    def cancel_all(self, symbol):
        return self._request("DELETE", "/fapi/v1/allOpenOrders", params={"symbol": symbol}, signed=True)
EOF

cat > ats/indicators.py <<'EOF'
import numpy as np
import pandas as pd

def ema(series: pd.Series, span: int) -> pd.Series:
    return series.ewm(span=span, adjust=False).mean()

def atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    high, low, close = df['high'], df['low'], df['close']
    prev_close = close.shift(1)
    tr = pd.concat([
        (high - low).abs(),
        (high - prev_close).abs(),
        (low - prev_close).abs()
    ], axis=1).max(axis=1)
    return tr.rolling(period).mean()

def chop(df: pd.DataFrame, period: int = 14) -> pd.Series:
    high, low, close = df['high'], df['low'], df['close']
    tr = atr(df, period) * period
    ch = (high.rolling(period).max() - low.rolling(period).min()).replace(0, np.nan)
    ci = 100 * np.log10(tr / ch) / np.log10(period)
    return ci.fillna(method="bfill").clip(0,100)

def zigzag_pivots(df: pd.DataFrame, atr_mult: float = 0.5, period: int = 14):
    # 简化版：基于 ATR 的上下翻转
    a = atr(df, period)
    close = df['close']
    piv = pd.Series(index=df.index, dtype=float)
    direction = 0  # 1 up, -1 down
    last_pivot = close.iloc[0]
    piv.iloc[0] = last_pivot
    for i in range(1, len(close)):
        th = a.iloc[i] * atr_mult
        if direction >= 0 and close.iloc[i] <= last_pivot - th:
            direction = -1
            last_pivot = close.iloc[i]
            piv.iloc[i] = last_pivot
        elif direction <= 0 and close.iloc[i] >= last_pivot + th:
            direction = 1
            last_pivot = close.iloc[i]
            piv.iloc[i] = last_pivot
    return piv

def vboost(vol: pd.Series, lookback: int = 30) -> float:
    base = vol.tail(lookback).median() + 1e-9
    return float(vol.iloc[-1] / base)

def slope_r2(series: pd.Series, lookback: int = 30):
    y = series.tail(lookback).values
    x = np.arange(len(y))
    if len(y) < 2:
        return 0.0, 0.0
    A = np.vstack([x, np.ones(len(x))]).T
    m, c = np.linalg.lstsq(A, y, rcond=None)[0]
    y_pred = m * x + c
    ss_res = np.sum((y - y_pred)**2)
    ss_tot = np.sum((y - y.mean())**2) + 1e-9
    r2 = 1 - ss_res/ss_tot
    return float(m), float(r2)

def tib_abs(df: pd.DataFrame, period:int=14) -> float:
    body = (df['close'] - df['open']).abs()
    a = atr(df, period)
    return float((body / (a + 1e-9)).iloc[-1])
EOF

cat > ats/base_pool.py <<'EOF'
from loguru import logger

def build_base_pool_from_24h(tickers: list, max_symbols: int, min_quote_vol: float):
    # 从 24hr 排行选主力 USDT 本位合约
    rows = []
    for x in tickers:
        s = x.get("symbol","")
        if not s.endswith("USDT"): continue
        if "PERP" in s: continue  # 交割合约可能带特殊后缀，简化：只留标准 USDT
        qv = float(x.get("quoteVolume", 0) or 0.0)
        if qv < min_quote_vol: continue
        rows.append((s, qv))
    rows.sort(key=lambda t: t[1], reverse=True)
    picks = [s for s,_ in rows[:max_symbols]]
    logger.info("Base pool size={} (min_quote_vol={})", len(picks), min_quote_vol)
    return picks
EOF

# （其余模块、gates/score/planner/risk/runner/app 会在第二段补齐）

# 先做一次最小提交，保证大文件写入不卡
git add -A
git commit -m "chore: QF v1.0 bootstrap (part 1/2) - infra, io, indicators, pool"

echo ">>> 第一段写入完成，等待第二段继续追加文件并一次性推送..."
echo "当前 worktree: ${WT} 分支: ${BR}"
