from loguru import logger

def build_base_pool_from_24h(tickers: list, max_symbols: int, min_quote_vol: float):
    # 从 24hr 排行选主力 USDT 本位合约
    rows = []
    for x in tickers:
        s = x.get("symbol","")
        if not s.endswith("USDT"): continue
        if "PERP" in s: continue  # 交割合约可能带特殊后缀，简化：只留标准 USDT
        qv = float(x.get("quoteVolume", 0) or 0.0)
        if qv < min_quote_vol: continue
        rows.append((s, qv))
    rows.sort(key=lambda t: t[1], reverse=True)
    picks = [s for s,_ in rows[:max_symbols]]
    logger.info("Base pool size={} (min_quote_vol={})", len(picks), min_quote_vol)
    return picks
