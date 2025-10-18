from typing import Dict, Tuple
import pandas as pd
from .indicators import ema, atr, chop, vboost, slope_r2, tib_abs

# 评分：趋势(40) 结构(30) 量能(30)
def score_symbol(df: pd.DataFrame, params: dict) -> Tuple[float, dict]:
    th = params.get("thresholds", {})
    trend_th = th.get("trend", {})
    struct_th = th.get("struct", {})
    vol_th = th.get("volume", {})

    close = df["close"]
    vol = df["volume"]

    # 趋势：EMA30 斜率与R²标准化
    ema30 = ema(close, 30)
    m, r2 = slope_r2(ema30, 30)
    trend_score = 100.0 * max(0.0, (m / max(abs(ema30.iloc[-1]) * 0.001, 1e-8))) * (r2)
    trend_pass = (m >= trend_th.get("ema30_slope_min", 0.25)) and (r2 >= trend_th.get("r2_min", 0.45))
    trend_score = max(0.0, min(40.0, trend_score))  # 映射到0~40

    # 结构：CHOP 越低越好 + ZigZag/ATR 粗略用 ATR/波动率代理
    a = atr(df, 14).iloc[-1]
    ch = chop(df, 14).iloc[-1]
    struct_base = max(0.0, 100.0 - ch)  # 越趋势化分越高
    struct_score = min(30.0, struct_base * 0.3)
    struct_pass = struct_score >= struct_th.get("zigzag_min_atr", {}).get("base", 0.4)  # 以阈名借位

    # 量能：vboost + TIB
    vb = vboost(vol, 30)
    ti = tib_abs(df, 14)
    vol_score = min(30.0, (vb - 1.0) * 15.0 + ti * 10.0)
    vol_pass = (vb >= vol_th.get("vboost_min", {}).get("base", 1.8)) and (ti >= vol_th.get("tib_abs_min", {}).get("base", 0.20))

    total = trend_score + struct_score + vol_score
    detail = dict(trend={"m": m, "r2": r2, "score": trend_score, "pass": trend_pass},
                  struct={"chop": ch, "atr": a, "score": struct_score, "pass": struct_pass},
                  volume={"vboost": vb, "tib": ti, "score": vol_score, "pass": vol_pass},
                  total=total)
    return total, detail

def aplus_pass(detail: dict, params: dict) -> bool:
    ap = params.get("thresholds", {}).get("aplus", {})
    total_ok = detail.get("total", 0) >= ap.get("min_total", 90)
    blocks = [detail["trend"]["score"], detail["struct"]["score"], detail["volume"]["score"]]
    block_ok = all(x >= ap.get("block_min", 65) for x in blocks)
    return bool(total_ok and block_ok)
