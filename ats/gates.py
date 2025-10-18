from typing import Dict
import pandas as pd
from .indicators import ema, atr

def gate_A_true_breakout(df: pd.DataFrame, params: dict) -> bool:
    g = params["thresholds"]["gates"]["A"]
    look = g.get("lookback",72)
    pad = g.get("breakout_pad",0.002)
    close_out = g.get("close_outside",0.003)
    body_atr_max = g.get("body_atr_max",{}).get("default",1.2)

    high = df["high"].iloc[-look-1:-1].max()
    low  = df["low"].iloc[-look-1:-1].min()
    a = atr(df,14).iloc[-1]
    o, c = df["open"].iloc[-1], df["close"].iloc[-1]
    body = abs(c-o)

    # LONG 方向：突破 lookback 高点并收在其上，且实体不过大
    cond = (c >= high*(1+pad)) and ((c - high)/max(high,1e-9) >= close_out) and (body / max(a,1e-9) <= body_atr_max)
    return bool(cond)

def gate_B_pullback_confirm(df: pd.DataFrame, params: dict) -> bool:
    # 简化：EMA10 上方回踩不破，实体占比≥阈值
    b = params["thresholds"]["gates"]["B"]
    ema10 = ema(df["close"],10).iloc[-1]
    c, o, l = df["close"].iloc[-1], df["open"].iloc[-1], df["low"].iloc[-1]
    body_pct_min = b["confirm"]["body_pct_min"]
    tib_abs = b["confirm"]["tib_abs"]
    a = atr(df,14).iloc[-1]
    body = abs(c-o) / max(a,1e-9)
    near = l <= ema10*(1+ b["anchors"]["L2_ema10_atr"])  # 近均线
    return bool((c>ema10) and near and (body>=body_pct_min) and (body>=tib_abs))

def gate_C_crowded_check(funding_abs: float, params: dict) -> bool:
    # 简化：绝对 funding 不超过上限
    c = params["thresholds"]["gates"]["C"]
    return bool(abs(funding_abs) <= c.get("funding_abs_max", 0.02))

def gate_D_executable(spread_bps: float, room_atr: float, costR: float, params: dict) -> bool:
    d = params["thresholds"]["gates"]["D"]
    return bool((spread_bps <= d["spread_bps"]) and (room_atr >= d["room_atr_min"]) and (costR <= d["cost_R_max"]))
