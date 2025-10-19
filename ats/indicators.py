from __future__ import annotations
import numpy as np, pandas as pd

def ema(s: pd.Series, n: int) -> pd.Series:
    return s.ewm(span=n, adjust=False, min_periods=n).mean()

def atr(df: pd.DataFrame, n: int = 14) -> pd.Series:
    h,l,c = df["high"], df["low"], df["close"]
    tr = np.maximum(h-l, np.maximum(abs(h-c.shift(1)), abs(l-c.shift(1))))
    return tr.rolling(n).mean()

def chop(df: pd.DataFrame, n: int = 14) -> pd.Series:
    h,l,c = df["high"], df["low"], df["close"]
    tr = np.maximum(h-l, np.maximum(abs(h-c.shift(1)), abs(l-c.shift(1))))
    num = np.log10((h.rolling(n).max()-l.rolling(n).min()) / tr.rolling(n).sum().replace(0,np.nan))
    return 100*num.replace([np.inf,-np.inf],np.nan)

def zigzag(df: pd.DataFrame, atr_mult: float = 0.5) -> pd.Series:
    a = atr(df,14)
    piv = np.zeros(len(df), dtype=int)
    last_p, last_dir = df["close"].iloc[0], 0
    for i,(c,tr) in enumerate(zip(df["close"], a.fillna(method="bfill"))):
        if last_dir<=0 and c > last_p + atr_mult*tr: last_dir=1; piv[i]=1; last_p=c
        elif last_dir>=0 and c < last_p - atr_mult*tr: last_dir=-1; piv[i]=-1; last_p=c
    return pd.Series(piv, index=df.index)

def ema_slope_r2(s: pd.Series, n=30, win=30):
    e = ema(s, n)
    x = np.arange(win)
    y = e.tail(win).values
    if len(y)<win: return 0.0, 0.0
    A = np.vstack([x, np.ones_like(x)]).T
    m, b = np.linalg.lstsq(A, y, rcond=None)[0]
    ss_res = ((y-(m*x+b))**2).sum()
    ss_tot = ((y-y.mean())**2).sum() + 1e-12
    r2 = 1 - ss_res/ss_tot
    return float(m/(np.mean(y)+1e-9)), float(r2)

def cvd_proxy(df: pd.DataFrame, n=50):
    ret = df["close"].pct_change().fillna(0.0)
    sign = np.sign(ret)
    return (sign * df["volume"]).rolling(n).sum()

def tib_abs(df: pd.DataFrame, n=20):
    body = (df["close"]-df["open"]).abs()
    return (body / (atr(df,14)+1e-12)).rolling(n).mean()

def vboost(df: pd.DataFrame, n=20):
    vol = df["volume"]; ma = vol.rolling(n).mean()
    return (vol / (ma+1e-9))
