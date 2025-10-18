import os, math
import pandas as pd
from pathlib import Path
from loguru import logger
from time import sleep
from .config import load_params
from .utils import utcnow, next_hour_plus_15s
from .notifier import send_text
from .store import ensure_schema
from .binance import BinanceFutures
from .indicators import ema
from .scoring import score_symbol, aplus_pass
from .gates import gate_A_true_breakout, gate_B_pullback_confirm, gate_C_crowded_check, gate_D_executable
from .planner import make_plan
from .risk import allow_new_open, switches
from .runner import on_plan, place_orders, runner_tick
from .base_pool import build_base_pool_from_24h

def fetch_df(bnz: BinanceFutures, symbol: str, interval="1h", limit=200) -> pd.DataFrame:
    arr = bnz.klines(symbol=symbol, interval=interval, limit=limit)
    cols = ["open_time","open","high","low","close","volume","close_time","qav","trades","taker_base","taker_quote","ignore"]
    df = pd.DataFrame(arr, columns=cols)
    for c in ["open","high","low","close","volume","qav","taker_base","taker_quote"]:
        df[c]=pd.to_numeric(df[c], errors="coerce")
    return df[["open","high","low","close","volume"]]

def heartbeat(bnz: BinanceFutures):
    try:
        st = bnz.server_time()
        send_text(f"💓 *ATS heartbeat* \nServerTime: ")
    except Exception as e:
        logger.exception(e)

def build_pool(bnz: BinanceFutures, params: dict):
    t24 = bnz.tickers_24h()
    picks = build_base_pool_from_24h(t24, params["symbol_pool"]["max_symbols"], params["symbol_pool"]["min_quote_vol"])
    return picks

def scan_once():
    params = load_params()
    ensure_schema()
    bnz = BinanceFutures()
    s = switches()

    picks = build_pool(bnz, params)
    passed=[]
    for sym in picks[:30]:   # 先限制 30 个，避免速率压力
        try:
            df = fetch_df(bnz, sym, params["sampling"]["main_interval"], 200)
            total, detail = score_symbol(df, params)
            if not aplus_pass(dict(**detail, total=total), params):
                continue
            # Gate A/B
            if not gate_A_true_breakout(df, params): 
                continue
            if not gate_B_pullback_confirm(df, params):
                continue
            # Gate C：funding 简化用最近一次
            try:
                fr = bnz.funding_rate(sym, limit=1)
                funding_abs = float(fr[0]["fundingRate"]) if fr else 0.0
            except: funding_abs=0.0
            if not gate_C_crowded_check(funding_abs, params): 
                continue

            # 计划与 Gate D
            plan = make_plan(df, "LONG", params)
            price = float(df["close"].iloc[-1])
            spread_bps = 5.0  # 简化：真实可通过 order book 估算
            if not gate_D_executable(spread_bps, plan["room"], plan["costR"], params):
                continue

            passed.append((sym, plan, dict(**detail, total=total)))
            on_plan(sym, plan, dict(**detail, total=total))

            # 下单（默认 DRY / disabled）
            if allow_new_open(params):
                place_orders(bnz, sym, plan, maker_only=True, dry=s["dry"])
        except Exception as e:
            logger.exception(e)
            send_text(f"⚠️ {sym} 扫描异常：")

    send_text(f"📊 扫描完成：候选 {len(picks)} / 计划 {len(passed)}")
    runner_tick(bnz)

def main_loop():
    logger.add("reports/ats.log", rotation="10 MB", retention=5)
    send_text("🚀 ATS QF v1.0 启动（模拟模式默认）")
    heartbeat(BinanceFutures())
    while True:
        now=utcnow(); tgt=next_hour_plus_15s(now)
        sleep=max(1,int((tgt-now).total_seconds()))
        logger.info("sleep {}s until {}", sleep, tgt.isoformat())
        try:
            scan_once()
        except Exception as e:
            logger.exception(e); send_text(f"❌ 扫描异常：")

if __name__=="__main__":
    Path("reports").mkdir(parents=True, exist_ok=True)
    main_loop()
