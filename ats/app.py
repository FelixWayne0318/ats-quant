import os, time, pandas as pd
from pathlib import Path
from loguru import logger

from .utils import utcnow, next_hour_plus_15s
from .notifier import send_text, send_text_plain
from .store import ensure_schema
from .binance import BinanceFutures
from .scoring import score_symbol, aplus_pass
from .gates import (gate_A_true_breakout, gate_B_pullback_confirm,
                    gate_C_crowded_check, gate_D_executable,
                    compute_c_metrics, gate_C_crowded_check_from_metrics,
                    estimate_orderbook_metrics)
from .planner import make_plan
from .risk import allow_new_open, switches
from .runner import on_plan, place_orders, runner_tick
from .base_pool import build_base_pool_from_24h
from .overlay import decay as overlay_decay, update_from_t24 as overlay_update, top as overlay_top

BUILD_TAG = "v1.2-full"

FALLBACK_POOL = ["BTCUSDT","ETHUSDT","SOLUSDT","BNBUSDT","XRPUSDT","ADAUSDT","DOGEUSDT","TONUSDT"]
_DAILY_POOL = {"date": None, "symbols": []}
_LAST_T24 = {"ts": 0, "data": []}

def fetch_df(bnz: BinanceFutures, symbol: str, interval="1h", limit=200) -> pd.DataFrame:
    arr = bnz.klines(symbol=symbol, interval=interval, limit=limit)
    cols = ["open_time","open","high","low","close","volume","close_time","qav","trades","taker_base","taker_quote","ignore"]
    df = pd.DataFrame(arr, columns=cols)
    for c in ["open","high","low","close","volume","qav","taker_base","taker_quote"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    return df[["open","high","low","close","volume"]]

def heartbeat(bnz: BinanceFutures):
    try:
        st = bnz.server_time()
        send_text(f"💓 *ATS heartbeat*\nBuild: `{BUILD_TAG}`\nServerTime: `{st.get('serverTime')}`")
    except Exception as e:
        logger.exception(e)

def _get_t24(bnz: BinanceFutures, cache_sec: int):
    now = time.time()
    if _LAST_T24["data"] and now - _LAST_T24["ts"] < cache_sec:
        return _LAST_T24["data"]
    t24 = bnz.tickers_24h()
    _LAST_T24.update(ts=now, data=t24)
    return t24

def refresh_daily_base_pool(bnz: BinanceFutures, params: dict):
    date_utc = utcnow().strftime("%Y-%m-%d")
    if _DAILY_POOL["date"] == date_utc and _DAILY_POOL["symbols"]:
        return _DAILY_POOL["symbols"]
    t24 = bnz.tickers_24h()
    size = int(params.get("symbol_pool", {}).get("base_pool_daily_size", 120))
    min_qv = float(params["symbol_pool"]["min_quote_vol"])
    base = build_base_pool_from_24h(t24, size, min_qv)
    if not base: base = FALLBACK_POOL
    _DAILY_POOL.update(date=date_utc, symbols=base)
    Path("reports").mkdir(exist_ok=True, parents=True)
    Path(f"reports/base_pool_{date_utc}.txt").write_text("\n".join(base))
    send_text(f"🗂️ 日基础池刷新 `{date_utc}`：{len(base)} 个")
    return base

def build_pool(bnz: BinanceFutures, params: dict):
    daily = refresh_daily_base_pool(bnz, params)
    cache_sec = int(params.get("scan",{}).get("tickers_cache_sec",600))
    t24 = _get_t24(bnz, cache_sec)
    overlay_decay(float(params.get("sampling",{}).get("overlay_decay_hours",2)))
    overlay_update(t24, int(params.get("overlay",{}).get("top_movers",30)))
    ol_top = overlay_top(limit=int(params["symbol_pool"]["max_symbols"]))
    merged=[]
    for s in ol_top + daily:
        if s not in merged: merged.append(s)
        if len(merged) >= int(params["symbol_pool"]["max_symbols"]): break
    return merged or (daily[:int(params["symbol_pool"]["max_symbols"])] or FALLBACK_POOL)

def scan_once():
    import yaml
    params = yaml.safe_load(open("params.yml")) or {}
    ensure_schema()
    bnz = BinanceFutures()
    sw = switches()

    scan_cfg = params.get("scan", {})
    max_per_scan = int(scan_cfg.get("max_symbols_per_scan", 18))
    pause_ms = int(scan_cfg.get("per_symbol_pause_ms", 350))
    pause_sec = max(0.05, pause_ms/1000.0)
    mute_err = os.getenv("NOTIFY_MUTE_ERRORS","0") == "1"

    picks = build_pool(bnz, params)[:max_per_scan]

    passed, errors = [], []
    for sym in picks:
        try:
            df = fetch_df(bnz, sym, params["sampling"]["main_interval"], 200)
            total, detail = score_symbol(df, params)
            gate_ctx = dict(**detail, total=total)
            if not aplus_pass(gate_ctx, params):               time.sleep(pause_sec); continue
            if not gate_A_true_breakout(df, params):           time.sleep(pause_sec); continue
            if not gate_B_pullback_confirm(df, params):        time.sleep(pause_sec); continue

            try:
                fr = bnz.funding_rate(sym, limit=30)
            except Exception:
                fr = []
            cmet = compute_c_metrics(df, fr)
            if not gate_C_crowded_check_from_metrics(cmet, params): time.sleep(pause_sec); continue

            plan = make_plan(df, "LONG", params)
            try:
                ob = bnz.depth(sym, limit=50)
                mid = float(df["close"].iloc[-1])
                notional = float(os.getenv("MAX_NOTIONAL_USDT","200") or 200)
                obm = estimate_orderbook_metrics(ob, mid, notional_usdt=notional)
                spread, impact, obi = obm["spread_bps"], obm["impact_bps"], obm["obi_abs"]
            except Exception:
                spread, impact, obi = 1e9, 1e9, 1e9
            if not gate_D_executable(spread, plan["room"], plan["costR"], params, impact_bps=impact, obi_abs=obi):
                time.sleep(pause_sec); continue

            passed.append((sym, plan, gate_ctx))
            on_plan(sym, plan, gate_ctx)
            if allow_new_open(params):
                place_orders(bnz, sym, plan, maker_only=True, dry=sw["dry"])
        except Exception as e:
            logger.exception(e)
            errors.append((sym, (repr(e) or "err")[:240]))
        finally:
            time.sleep(pause_sec)

    if errors and not mute_err:
        sample = "\n".join([f"{s}: {m}" for s,m in errors[:8]])
        send_text_plain(f"⚠️ 扫描异常 {len(errors)}/{len(picks)} 个：\n{sample}")
    send_text(f"📊 扫描完成：候选 {len(picks)} / 计划 {len(passed)}")
    runner_tick(bnz)

def main_loop():
    Path("reports").mkdir(parents=True, exist_ok=True)
    logger.add("reports/ats.log", rotation="10 MB", retention=5)
    send_text("🚀 ATS QF v1.2 启动（模拟模式默认）")
    heartbeat(BinanceFutures())
    while True:
        now = utcnow()
        tgt = next_hour_plus_15s(now)
        delay = max(1, int((tgt-now).total_seconds()))
        logger.info("sleep {}s until {}", delay, tgt.isoformat())
        time.sleep(delay)
        try:
            scan_once()
        except Exception as e:
            logger.exception(e)
            send_text_plain(f"❌ 扫描异常：{(repr(e) or 'unknown')[:400]}")
            time.sleep(5)

if __name__ == "__main__":
    main_loop()
