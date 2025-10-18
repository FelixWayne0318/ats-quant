import os, time
from datetime import timedelta
from loguru import logger
from .utils import is_funding_black_window, utcnow

def switches():
    return dict(
        enabled = os.getenv("TRADING_ENABLED","false").lower()=="true",
        dry     = os.getenv("DRY_RUN","true").lower()=="true",
        black_m = int(os.getenv("BLACK_WINDOW_MINUTES","5"))
    )

def allow_new_open(params: dict) -> bool:
    s = switches()
    if not s["enabled"] or s["dry"]:
        logger.info("Switch off: enabled={} dry={}", s["enabled"], s["dry"])
        return False
    # 黑窗禁新开
    bk = params.get("trade",{}).get("black_window_minutes",5)
    if is_funding_black_window(utcnow(), minutes=bk):
        logger.info("Funding black window; skip open")
        return False
    return True
