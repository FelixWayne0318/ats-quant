import sqlite3, os
from loguru import logger
os.makedirs("db", exist_ok=True)
DB_PATH = "db/state.db"

DDL = """
CREATE TABLE IF NOT EXISTS cooldowns(
  symbol TEXT, side TEXT, until_utc INTEGER, reason TEXT,
  PRIMARY KEY(symbol, side)
);
CREATE TABLE IF NOT EXISTS clusters(
  date TEXT, symbol TEXT, cluster_id INTEGER,
  PRIMARY KEY(date, symbol)
);
CREATE TABLE IF NOT EXISTS risk_budget(
  ts INTEGER, hourly_used REAL, portfolio_R REAL
);
CREATE TABLE IF NOT EXISTS overlay_queue(
  ts INTEGER, symbol TEXT, heat REAL, last_touch_ts INTEGER,
  PRIMARY KEY(symbol)
);
CREATE TABLE IF NOT EXISTS plans(
  ts INTEGER, symbol TEXT, side TEXT,
  l1 REAL, l2 REAL, l3 REAL, w1 REAL, w2 REAL, w3 REAL,
  sl REAL, tp1 REAL, tp2 REAL, R REAL, costR REAL, room REAL,
  gates TEXT, mode TEXT
);
"""

def conn(): return sqlite3.connect(DB_PATH)

def ensure_schema():
    with conn() as c:
        c.executescript(DDL)
        c.commit()
    logger.info("SQLite schema ensured at {}", DB_PATH)
