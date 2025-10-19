from typing import Dict, List
import math
import pandas as pd
from .indicators import atr

def plan_long(df: pd.DataFrame, params: dict) -> dict:
    a = float(atr(df,14).iloc[-1])
    c = float(df["close"].iloc[-1])
    mult = params["planner"]["atr_mult"]
    l1 = c * (1 - mult["entry"][0]*a/c)
    l2 = c * (1 - mult["entry"][1]*a/c)
    l3 = c * (1 - mult["entry"][2]*a/c)
    sl = c * (1 - mult["sl"]*a/c)
    tp1 = c * (1 + mult["tp1"]*a/c)
    tp2 = c * (1 + mult["tp2"]*a/c)
    w1,w2,w3 = params["planner"]["weights"]["default"]
    # 预估costR（点差/滑点）极简：以 0.05R 估算
    R = max( (c - sl), 1e-8 )
    costR = 0.05
    room_atr = (tp1 - l1)/max(a,1e-9)
    return dict(l1=l1,l2=l2,l3=l3, w1=w1,w2=w2,w3=w3, sl=sl,tp1=tp1,tp2=tp2, R=R, costR=costR, room=room_atr)

def make_plan(df: pd.DataFrame, side: str, params: dict) -> dict:
    if side in ("LONG","LONG_ONLY"):
        return plan_long(df, params)
    # 如需做空，可补充 plan_short
    return {}
