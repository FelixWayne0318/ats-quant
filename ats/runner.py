from __future__ import annotations
from loguru import logger

def on_plan(symbol: str, plan: dict, ctx: dict):
    logger.info("on_plan {} {}", symbol, plan)

def place_orders(bnz, symbol: str, plan: dict, maker_only=True, dry=True):
    logger.info("place_orders {} (dry={})", symbol, dry)

def runner_tick(bnz):
    pass
