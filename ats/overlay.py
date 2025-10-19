from __future__ import annotations
import sqlite3, time, math
from typing import Iterable, List

DB = "db/state.db"
def _now(): return int(time.time())
def _conn(): return sqlite3.connect(DB)

def decay(half_life_hours: float = 2.0) -> None:
    now = _now()
    hl = max(0.1, float(half_life_hours)) * 3600.0
    with _conn() as c:
        for sym,heat,ts in c.execute("SELECT symbol,heat,ts FROM overlay_queue"):
            dt = max(0, now - int(ts or now))
            factor = math.pow(0.5, dt/hl)
            new_heat = float(heat or 0.0)*factor
            c.execute("UPDATE overlay_queue SET heat=?, ts=? WHERE symbol=?",(new_heat, now, sym))
        c.commit()

def bump(symbols: Iterable[str], weight: float = 1.0) -> None:
    now = _now()
    syms = [s for s in symbols if s and s.endswith("USDT")]
    if not syms: return
    with _conn() as c:
        for s in syms:
            c.execute("""
            INSERT INTO overlay_queue(symbol, ts, heat, last_touch_ts)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(symbol) DO UPDATE SET
              heat = overlay_queue.heat + excluded.heat,
              last_touch_ts = excluded.last_touch_ts
            """,(s, now, float(weight), now))
        c.commit()

def top(limit: int = 18, min_heat: float = 0.01) -> List[str]:
    with _conn() as c:
        cur = c.execute("SELECT symbol FROM overlay_queue WHERE heat>? ORDER BY heat DESC LIMIT ?",(float(min_heat), int(limit)))
        return [r[0] for r in cur.fetchall()]

def update_from_t24(t24: list, k: int = 30) -> None:
    try:
        sorted_items = sorted(t24, key=lambda x: abs(float((x.get("priceChangePercent") or "0").replace("%",""))), reverse=True)[: int(k)]
        syms = [it.get("symbol") for it in sorted_items if it.get("symbol","").endswith("USDT")]
        bump(syms, weight=1.0)
    except Exception:
        pass
