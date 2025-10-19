from __future__ import annotations
import pandas as pd
from .indicators import ema_slope_r2, atr, chop, zigzag, cvd_proxy, tib_abs, vboost

def score_trend(df, params):
    slope, r2 = ema_slope_r2(df["close"], n=30, win=30)
    s = 0
    th = params["thresholds"]["trend"]
    if slope >= float(th["ema30_slope_min"]): s += 60
    s += max(0, min(40, r2*40))
    return s, {"ema30_slope":slope,"r2":r2}

def score_structure(df, params):
    zz = zigzag(df, atr_mult=float(params["thresholds"]["struct"]["zigzag_min_atr"]["base"]))
    ch = chop(df).iloc[-1]
    piv = (zz.tail(40)==1).sum() - (zz.tail(40)==-1).sum()
    s = 30 - min(15, abs(ch-50)/50*15) + min(15, max(0,piv)/10*15)
    return max(0,s), {"chop":float(ch), "piv_bias":int(piv)}

def score_volume(df, params):
    cvd = cvd_proxy(df).iloc[-1]
    tib = tib_abs(df).iloc[-1]
    vb = vboost(df).iloc[-1]
    th = params["thresholds"]["volume"]
    s = 0
    if vb >= float(th["vboost_min"]["base"]): s += 12
    if abs(cvd) >= float(df["volume"].rolling(20).mean().iloc[-1])*float(abs(th["cvd_mix_pct"]["long"])): s += 9
    if tib >= float(th["tib_abs_min"]["base"]): s += 9
    return s, {"cvd":float(cvd), "tib":float(tib), "vboost":float(vb)}

def score_symbol(df: pd.DataFrame, params: dict):
    t, td = score_trend(df, params)
    s, sd = score_structure(df, params)
    v, vd = score_volume(df, params)
    total = int(round(t*0.4 + s*0.3 + v*0.3))
    detail = {**td, **sd, **vd}
    return total, detail

def aplus_pass(ctx: dict, params: dict):
    th = params["thresholds"]["aplus"]
    total = ctx["total"]
    if total < int(th["min_total"]): return False
    blocks = [("trend", ctx.get("ema30_slope",0), 60),
              ("structure", ctx.get("piv_bias",0), 30),
              ("volume", ctx.get("vboost",0), 30)]
    # 简化：只校验总分门槛
    return True
