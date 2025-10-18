from pathlib import Path
import sqlite3
from loguru import logger

DB_DIR = Path("db")
DATA_DIR = Path("data")
DB_PATH = DB_DIR / "state.db"

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

def ensure_dirs():
    DB_DIR.mkdir(exist_ok=True, parents=True)
    DATA_DIR.mkdir(exist_ok=True, parents=True)

def connect():
    ensure_dirs()
    return sqlite3.connect(DB_PATH)

def ensure_schema():
    conn = connect()
    with conn:
        conn.executescript(DDL)
    conn.close()
    logger.info("SQLite schema ensured at {}", DB_PATH)
