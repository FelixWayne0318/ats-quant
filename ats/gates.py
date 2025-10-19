from __future__ import annotations
import numpy as np, pandas as pd

def gate_A_true_breakout(df: pd.DataFrame, params: dict) -> bool:
    look = int(params["thresholds"]["gates"]["A"]["lookback"])
    pad  = float(params["thresholds"]["gates"]["A"]["breakout_pad"])
    c = df["close"].iloc[-1]; hh = df["high"].tail(look).max()
    return c > hh*(1+pad)

def gate_B_pullback_confirm(df: pd.DataFrame, params: dict) -> bool:
    # 简化版：实体>最小比例 + 收盘接近区间上沿
    th = params["thresholds"]["gates"]["B"]["confirm"]
    body = abs(df["close"].iloc[-1]-df["open"].iloc[-1])
    rng  = (df["high"].iloc[-1]-df["low"].iloc[-1]+1e-12)
    body_pct = body/rng
    close_zone = (df["close"].iloc[-1]-df["low"].iloc[-1])/rng
    return body_pct >= float(th["body_pct_min"]) and close_zone >= float(th["close_zone"])

# ----- Gate C 拥挤度：资金费率分位 / 速度分位 / z 极值 -----
def _pct_rank(arr: np.ndarray, x: float) -> float:
    if arr.size==0: return 0.0
    return 100.0 * (np.sum(arr<=x)/arr.size)

def compute_c_metrics(df: pd.DataFrame, funding_rates: list[dict]) -> dict:
    close = pd.to_numeric(df["close"], errors="coerce")
    ret = close.pct_change().dropna()
    sp6 = ret.rolling(6).apply(lambda x: np.mean(np.abs(x)), raw=True).dropna()
    cur_speed = float(sp6.iloc[-1]) if len(sp6) else 0.0
    speed_pctl = _pct_rank(sp6.values, cur_speed)
    if len(ret)>=10 and ret.std()>0:
        z_abs = float(abs((ret.iloc[-1]-ret.mean())/(ret.std()+1e-12)))
    else:
        z_abs = 0.0
    f_abs = np.array([abs(float(x.get("fundingRate",0))) for x in funding_rates], dtype=float)
    f_last= float(f_abs[-1]) if f_abs.size else 0.0
    funding_pctl = _pct_rank(np.sort(f_abs), f_last)
    return {"funding_pctl":funding_pctl, "speed_pctl":speed_pctl, "z_abs":z_abs}

def gate_C_crowded_check_from_metrics(metrics: dict, params: dict) -> bool:
    thr = params["thresholds"]["C"]
    if metrics["funding_pctl"] >= float(thr["funding_pctl"]["small"]): return False
    if metrics["speed_pctl"]   >= float(thr["speed_pctl"]): return False
    if metrics["z_abs"]        >= float(min(thr["z_extreme"]["big"], thr["z_extreme"]["small"])): return False
    return True

def gate_C_crowded_check(funding_abs: float, params: dict) -> bool:
    return True  # 兼容旧调用

# ----- Gate D 可执行性：spread/impact/OBI/room/costR -----
def estimate_orderbook_metrics(ob: dict, mid: float, notional_usdt: float = 200.0, topn: int = 20) -> dict:
    bids = [(float(p), float(q)) for p,q,*_ in ob.get("bids", [])[:topn]]
    asks = [(float(p), float(q)) for p,q,*_ in ob.get("asks", [])[:topn]]
    if not bids or not asks or mid<=0:
        return {"spread_bps":1e9,"obi_abs":1.0,"impact_bps":1e9}
    best_bid, best_ask = bids[0][0], asks[0][0]
    spread_bps = (best_ask-best_bid)/mid*1e4
    sum_bid = sum(q for _,q in bids); sum_ask=sum(q for _,q in asks)
    obi_abs = abs((sum_bid-sum_ask)/max(1e-9,(sum_bid+sum_ask)))
    need = notional_usdt/mid; rem=need; cost=0.0
    for p,q in asks:
        take=min(rem,q); cost+=take*p; rem-=take
        if rem<=1e-12: break
    impact_bps = 1e9 if rem>1e-12 else (cost/need-mid)/mid*1e4
    return {"spread_bps":float(spread_bps), "obi_abs":float(obi_abs), "impact_bps":float(impact_bps)}

def gate_D_executable(spread_bps: float, room_atr: float, costR: float, params: dict,
                      impact_bps: float | None = None, obi_abs: float | None = None) -> bool:
    thr = params["thresholds"]["D"]
    if spread_bps > float(thr["spread_bps"]): return False
    if impact_bps is not None and impact_bps > float(thr["impact_bps"]): return False
    if obi_abs    is not None and obi_abs    > float(thr["obi_abs"]):     return False
    if room_atr   <  float(thr["room_atr_min"]): return False
    if costR      >  float(thr["cost_R_max"]):   return False
    return True
