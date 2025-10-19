from __future__ import annotations
import pandas as pd, numpy as np

def _z24(item):
    try:
        p = float((item.get("priceChangePercent") or "0").replace("%",""))
        return abs(p)
    except: return 0.0

def build_base_pool_from_24h(t24: list, size: int, min_quote_vol: float):
    arr = []
    for it in t24:
        try:
            if not it.get("symbol","").endswith("USDT"): continue
            qv = float(it.get("quoteVolume") or 0.0)
            if qv < float(min_quote_vol): continue
            if _z24(it) < 1.0: continue
            arr.append((it["symbol"], qv, _z24(it)))
        except: continue
    # 先按 z_24，次序按成交额
    arr.sort(key=lambda x: (x[2], x[1]), reverse=True)
    return [a[0] for a in arr[:int(size)]]
