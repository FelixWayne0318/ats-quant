import os, hmac, hashlib, time, requests
from urllib.parse import urlencode
from loguru import logger
from tenacity import retry, stop_after_attempt, wait_exponential

BASE = os.getenv("BINANCE_FAPI_BASE", "https://fapi.binance.com")
KEY  = os.getenv("BINANCE_API_KEY", "")
SEC  = os.getenv("BINANCE_API_SECRET", "")

class BinanceFutures:
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

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=0.5, min=0.5, max=2))
    def _request(self, method: str, path: str, params=None, signed=False):
        params = params or {}
        url = self.base + path
        if signed:
            params["timestamp"] = int(time.time()*1000)
            qs = self._sign(params)
            if method == "GET":
                url = f"{url}?{qs}"
                params = None
            else:
                # POST/DELETE 用 query 放签名，body 为空或只放必要字段
                url = f"{url}?{qs}"
                params = None
        r = self.sess.request(method, url, params=params if method=="GET" else None,
                              data=None if method=="GET" else params, timeout=self.timeout)
        if r.status_code >= 400:
            logger.error("Binance error {}: {}", r.status_code, r.text)
        r.raise_for_status()
        if r.text:
            return r.json()
        return {}

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
    def funding_rate(self, symbol, limit=7):  # 最近几次 funding
        return self._request("GET", "/fapi/v1/fundingRate", params={"symbol": symbol, "limit": limit})

    # Orders
    def new_order(self, **kwargs):
        # 例：symbol, side, type, quantity, price, timeInForce=GTC, reduceOnly, newClientOrderId, ...
        return self._request("POST", "/fapi/v1/order", params=kwargs, signed=True)
    def cancel_all(self, symbol):
        return self._request("DELETE", "/fapi/v1/allOpenOrders", params={"symbol": symbol}, signed=True)
