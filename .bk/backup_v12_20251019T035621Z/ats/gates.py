from __future__ import annotations
import math, numpy as np
import pandas as pd

# ---------- 辅助 ----------
def _pct_rank(arr: np.ndarray, x: float) -> float:
    if arr.size == 0: return 0.0
    return 100.0 * (np.sum(arr <= x) / arr.size)

# ---------- Gate C：拥挤否决 ----------
def compute_c_metrics(df: pd.DataFrame, funding_rates: list[dict]) -> dict:
    """返回 funding_pctl(绝对值), speed_pctl(6h 绝对收益速度分位), z_abs(1h 绝对z)"""
    close = pd.to_numeric(df["close"], errors="coerce")
    ret = close.pct_change().dropna()
    # 6小时绝对速度(均值)
    speed_6h = ret.rolling(6).apply(lambda x: np.mean(np.abs(x)), raw=True)
    cur_speed = float(speed_6h.dropna().iloc[-1]) if len(speed_6h.dropna()) else 0.0
    speed_hist = speed_6h.dropna().values
    speed_pctl = _pct_rank(speed_hist, cur_speed)

    # 1h z-score
    if len(ret) >= 10 and ret.std() > 0:
        z_abs = float(abs((ret.iloc[-1] - ret.mean()) / (ret.std() + 1e-12)))
    else:
        z_abs = 0.0

    # 资金费率分位（绝对值）
    f_abs = np.array([abs(float(x.get("fundingRate", 0))) for x in funding_rates], dtype=float)
    f_last = float(f_abs[-1]) if f_abs.size else 0.0
    funding_pctl = _pct_rank(np.sort(f_abs), f_last)

    return {"funding_pctl": funding_pctl, "speed_pctl": speed_pctl, "z_abs": z_abs}

def gate_C_crowded_check_from_metrics(metrics: dict, params: dict) -> bool:
    thr = params["thresholds"]["C"]
    # 拒绝条件：任一超过阈值认为拥挤
    if metrics["funding_pctl"] >= float(thr["funding_pctl"]["small"]):  # 例如 >=95
        return False
    if metrics["speed_pctl"]   >= float(thr["speed_pctl"]):            # 例如 >=75
        return False
    z_lim_big  = float(thr["z_extreme"]["big"])
    z_lim_small= float(thr["z_extreme"]["small"])
    if metrics["z_abs"] >= min(z_lim_big, z_lim_small):
        return False
    return True

# 兼容旧签名（仅 funding_abs），默认放行
def gate_C_crowded_check(funding_abs: float, params: dict) -> bool:
    return True

# ---------- Gate D：可执行性 ----------
def estimate_orderbook_metrics(ob: dict, mid: float, notional_usdt: float = 200.0, topn: int = 20) -> dict:
    """从 depth 估计 spread(bps)/OBI/impact(bps)"""
    bids = [(float(p), float(q)) for p,q,*_ in ob.get("bids", [])[:topn]]
    asks = [(float(p), float(q)) for p,q,*_ in ob.get("asks", [])[:topn]]
    if not bids or not asks or mid <= 0: 
        return {"spread_bps": 1e9, "obi_abs": 1.0, "impact_bps": 1e9}

    best_bid, best_ask = bids[0][0], asks[0][0]
    spread_bps = (best_ask - best_bid) / mid * 1e4

    sum_bid = sum(q for _,q in bids)
    sum_ask = sum(q for _,q in asks)
    obi = (sum_bid - sum_ask) / max(1e-9, (sum_bid + sum_ask))
    obi_abs = abs(obi)

    # 市价吃单冲击
    need_qty = notional_usdt / mid
    remain = need_qty; cost = 0.0
    for p,q in asks:  # 模拟买单
        take = min(remain, q); cost += take * p; remain -= take
        if remain <= 1e-12: break
    if remain > 1e-12:  # 深度不够
        impact_bps = 1e9
    else:
        vwap = cost / need_qty
        impact_bps = (vwap - mid) / mid * 1e4

    return {"spread_bps": float(spread_bps), "obi_abs": float(obi_abs), "impact_bps": float(impact_bps)}

def gate_D_executable(spread_bps: float, room_atr: float, costR: float, params: dict,
                      impact_bps: float | None = None, obi_abs: float | None = None) -> bool:
    thr = params["thresholds"]["D"]
    if spread_bps > float(thr["spread_bps"]): return False
    if impact_bps is not None and impact_bps > float(thr["impact_bps"]): return False
    if obi_abs    is not None and obi_abs    > float(thr["obi_abs"]):     return False
    if room_atr   <  float(thr["room_atr_min"]): return False
    if costR      >  float(thr["cost_R_max"]):   return False
    return True
