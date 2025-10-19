from loguru import logger

def _to_float(x, default):
    try:
        return float(x)
    except Exception:
        try:
            return float(str(x).strip())
        except Exception:
            return float(default)

def build_base_pool_from_24h(tickers: list, max_symbols, min_quote_vol):
    # 强制类型安全
    try:
        max_symbols = int(max_symbols)
    except Exception:
        max_symbols = 60
    min_qv = _to_float(min_quote_vol, 2e7)

    rows = []
    for x in tickers:
        s = x.get("symbol","")
        if not s.endswith("USDT"):
            continue
        if "PERP" in s:
            continue
        qv_raw = x.get("quoteVolume", 0)
        try:
            qv = float(qv_raw or 0.0)
        except Exception:
            try:
                qv = float(str(qv_raw).strip())
            except Exception:
                qv = 0.0
        if qv < min_qv:
            continue
        rows.append((s, qv))

    rows.sort(key=lambda t: t[1], reverse=True)
    picks = [s for s,_ in rows[:max_symbols]]
    logger.info("Base pool size={} (min_quote_vol={})", len(picks), min_qv)
    return picks
