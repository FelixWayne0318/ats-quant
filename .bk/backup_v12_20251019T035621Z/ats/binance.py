import os, hmac, hashlib, time, requests
from urllib.parse import urlencode
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential

BASE = os.getenv("BINANCE_FAPI_BASE", "https://fapi.binance.com")
KEY  = os.getenv("BINANCE_API_KEY", "")
SEC  = os.getenv("BINANCE_API_SECRET", "")

class BinanceFutures:
    def depth(self, symbol: str, limit: int = 50):
        """Orderbook depth snapshot (bids/asks). limit ∈ {5,10,20,50,100,500}."""
        return self._get("/fapi/v1/depth", params={"symbol": symbol, "limit": int(limit)})
    def __init__(self, base=BASE, key=KEY, secret=SEC, timeout=10):
        self.base = base.rstrip("/")
        self.key = key
        self.secret = secret.encode()
        self.timeout = timeout
        self.sess = requests.Session()
        if key:
            self.sess.headers.update({"X-MBX-APIKEY": key})

    def _sign(self, params: dict):
        q = urlencode(params, doseq=True)
        sig = hmac.new(self.secret, q.encode(), hashlib.sha256).hexdigest()
        return f"{q}&signature={sig}"

    @retry(stop=stop_after_attempt(5), wait=wait_exponential(multiplier=1, min=1, max=16), reraise=True)
    def _request(self, method: str, path: str, params=None, signed=False):
        params = params or {}
        url = self.base + path
        if signed:
            params["timestamp"] = int(time.time()*1000)
            qs = self._sign(params)
            url = f"{url}?{qs}"
            params = None

        # 轻微节流，避免瞬间触发 -1003
        time.sleep(0.2)

        r = self.sess.request(method, url, params=params if method=="GET" else None,
                              data=None if method=="GET" else params, timeout=self.timeout)

        # HTTP 层面的限流（418/429）
        if r.status_code in (418, 429):
            retry_after = r.headers.get("Retry-After")
            try:
                retry_after = int(retry_after) if retry_after else 2
            except:
                retry_after = 2
            logger.warning("Binance HTTP %s rate limit, sleep %ss then retry", r.status_code, retry_after)
            time.sleep(max(1, retry_after))
            r.raise_for_status()  # 触发 tenacity 重试

        if r.status_code >= 400:
            # 业务层错误
            try:
                j = r.json()
            except Exception:
                j = {}
            code = j.get("code")
            msg  = j.get("msg", "")
            if code == -1003:  # Way too many requests
                retry_after = r.headers.get("Retry-After")
                try:
                    retry_after = int(retry_after) if retry_after else 2
                except:
                    retry_after = 2
                logger.warning("Binance -1003 rate limit, sleep %ss then retry. msg=%s", retry_after, msg)
                time.sleep(max(1, retry_after))
                r.raise_for_status()
            logger.error("Binance error %s: %s", r.status_code, r.text)
            r.raise_for_status()

        if not r.text:
            return {}
        return r.json()

    # Public
    def ping(self):         return self._request("GET", "/fapi/v1/ping")
    def server_time(self):  return self._request("GET", "/fapi/v1/time")
    def exchange_info(self):return self._request("GET", "/fapi/v1/exchangeInfo")
    def tickers_24h(self):  return self._request("GET", "/fapi/v1/ticker/24hr")
    def klines(self, symbol="BTCUSDT", interval="1h", limit=200):
        return self._request("GET", "/fapi/v1/klines", params={"symbol": symbol, "interval": interval, "limit": limit})

    # Account (signed)
    def open_orders(self, symbol=None):
        p = {"symbol": symbol} if symbol else {}
        return self._request("GET", "/fapi/v1/openOrders", params=p, signed=True)
    def position_risk(self): return self._request("GET", "/fapi/v2/positionRisk", signed=True)
    def account(self):       return self._request("GET", "/fapi/v2/account", signed=True)
    def funding_rate(self, symbol, limit=7):
        return self._request("GET", "/fapi/v1/fundingRate", params={"symbol": symbol, "limit": limit})

# --- ensured patch: depth endpoint using _request ---
def depth(self, symbol: str, limit: int = 50):
    """
    Orderbook depth snapshot (bids/asks). limit ∈ {5,10,20,50,100,500}.
    """
    return self._request("GET", "/fapi/v1/depth",
                         params={"symbol": symbol, "limit": int(limit)})
