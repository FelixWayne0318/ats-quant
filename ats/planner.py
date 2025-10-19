from __future__ import annotations
import numpy as np, pandas as pd
from .indicators import atr

def make_plan(df: pd.DataFrame, side: str, params: dict):
    a = float(atr(df,14).iloc[-1] or 0.0)
    px = float(df["close"].iloc[-1])
    weights = params.get("planner",{}).get("weights",{}).get("default",[0.6,0.3,0.1])
    l1 = px; l2 = px - 0.5*a; l3 = px - 1.0*a
    sl = px - 1.5*a; tp1 = px + 1.0*a; tp2 = px + 2.0*a
    costR = (px*0.0005)/max(a,1e-6); room = (tp2-px)/max(a,1e-6)
    return dict(l1=l1,l2=l2,l3=l3,w1=weights[0],w2=weights[1],w3=weights[2],sl=sl,tp1=tp1,tp2=tp2,costR=costR,room=room)
