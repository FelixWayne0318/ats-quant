from __future__ import annotations
import os, time, requests
from loguru import logger

BASE = os.getenv("BINANCE_FAPI_BASE","https://fapi.binance.com")
BASE_DELAY = int(os.getenv("BINANCE_BASE_DELAY_MS","400") or 400)

class BinanceFutures:
    def __init__(self, base=BASE):
        self.base = base

    def _request(self, method, path, **kw):
        url = self.base + path
        backoff = BASE_DELAY/1000.0
        for i in range(6):
            try:
                r = requests.request(method, url, timeout=10, **kw)
                if r.status_code in (418,429):
                    time.sleep(backoff); backoff *= 1.6; continue
                if r.status_code == 200:
                    return r.json()
                if r.status_code == 451:  # location restricted
                    raise RuntimeError("451 restricted")
                if r.status_code == 418:
                    raise RuntimeError("418 rate limit")
                if r.status_code == 429:
                    raise RuntimeError("429 rate limit")
                j = r.json() if r.headers.get("content-type","").startswith("application/json") else {}
                code = j.get("code")
                if code in (-1003,):
                    time.sleep(backoff); backoff *= 1.6; continue
                r.raise_for_status()
            except Exception as e:
                logger.warning("binance req err: {}", e)
                time.sleep(backoff); backoff *= 1.6
        raise RuntimeError(f"request failed {method} {path}")

    def server_time(self): return self._request("GET","/fapi/v1/time")
    def klines(self, symbol, interval="1h", limit=200):
        return self._request("GET","/fapi/v1/klines", params={"symbol":symbol,"interval":interval,"limit":int(limit)})
    def funding_rate(self, symbol, limit=30):
        return self._request("GET","/fapi/v1/fundingRate", params={"symbol":symbol,"limit":int(limit)})
    def tickers_24h(self):
        return self._request("GET","/fapi/v1/ticker/24hr")
    def depth(self, symbol, limit=50):
        return self._request("GET","/fapi/v1/depth", params={"symbol":symbol,"limit":int(limit)})
