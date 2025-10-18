from datetime import datetime, timezone, timedelta

def utcnow():
    return datetime.now(timezone.utc)

def next_hour_plus_15s(now=None):
    now = now or utcnow()
    target = now.replace(minute=0, second=15, microsecond=0)
    if now >= target:
        target += timedelta(hours=1)
    return target

def is_funding_black_window(now=None, minutes=5):
    """Binance funding at 00:00/08:00/16:00 UTC，±minutes 禁新开"""
    now = now or utcnow()
    if now.minute >= 60 - minutes or now.minute <= minutes:
        return now.hour in (0, 8, 16)
    return False

def pct(a, b, eps=1e-9):
    return (a - b) / max(abs(b), eps)
