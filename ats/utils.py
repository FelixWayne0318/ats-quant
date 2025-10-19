from __future__ import annotations
from datetime import datetime, timezone, timedelta

def utcnow(): return datetime.now(timezone.utc)

def next_hour_plus_15s(now=None):
    now = now or utcnow()
    nxt = (now.replace(minute=0, second=15, microsecond=0) + timedelta(hours=1))
    if (nxt - now).total_seconds() < 5:
        nxt = nxt + timedelta(hours=1)
    return nxt
