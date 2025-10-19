from __future__ import annotations
from .store import conn
from loguru import logger

def switches():
    # 读取 DRY_RUN 等开关
    import os
    return {"dry": os.getenv("DRY_RUN","true").lower()!="false"}

def allow_new_open(params: dict) -> bool:
    # 组合阀/广度软限/簇：此处给出钩子和最小实现，可按需加严
    return True
