import numpy as np
import pandas as pd

def ema(series: pd.Series, span: int) -> pd.Series:
    return series.ewm(span=span, adjust=False).mean()

def atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    high, low, close = df['high'], df['low'], df['close']
    prev_close = close.shift(1)
    tr = pd.concat([
        (high - low).abs(),
        (high - prev_close).abs(),
        (low - prev_close).abs()
    ], axis=1).max(axis=1)
    return tr.rolling(period).mean()

def chop(df: pd.DataFrame, period: int = 14) -> pd.Series:
    high, low, close = df['high'], df['low'], df['close']
    tr = atr(df, period) * period
    ch = (high.rolling(period).max() - low.rolling(period).min()).replace(0, np.nan)
    ci = 100 * np.log10(tr / ch) / np.log10(period)
    return ci.fillna(method="bfill").clip(0,100)

def zigzag_pivots(df: pd.DataFrame, atr_mult: float = 0.5, period: int = 14):
    # 简化版：基于 ATR 的上下翻转
    a = atr(df, period)
    close = df['close']
    piv = pd.Series(index=df.index, dtype=float)
    direction = 0  # 1 up, -1 down
    last_pivot = close.iloc[0]
    piv.iloc[0] = last_pivot
    for i in range(1, len(close)):
        th = a.iloc[i] * atr_mult
        if direction >= 0 and close.iloc[i] <= last_pivot - th:
            direction = -1
            last_pivot = close.iloc[i]
            piv.iloc[i] = last_pivot
        elif direction <= 0 and close.iloc[i] >= last_pivot + th:
            direction = 1
            last_pivot = close.iloc[i]
            piv.iloc[i] = last_pivot
    return piv

def vboost(vol: pd.Series, lookback: int = 30) -> float:
    base = vol.tail(lookback).median() + 1e-9
    return float(vol.iloc[-1] / base)

def slope_r2(series: pd.Series, lookback: int = 30):
    y = series.tail(lookback).values
    x = np.arange(len(y))
    if len(y) < 2:
        return 0.0, 0.0
    A = np.vstack([x, np.ones(len(x))]).T
    m, c = np.linalg.lstsq(A, y, rcond=None)[0]
    y_pred = m * x + c
    ss_res = np.sum((y - y_pred)**2)
    ss_tot = np.sum((y - y.mean())**2) + 1e-9
    r2 = 1 - ss_res/ss_tot
    return float(m), float(r2)

def tib_abs(df: pd.DataFrame, period:int=14) -> float:
    body = (df['close'] - df['open']).abs()
    a = atr(df, period)
    return float((body / (a + 1e-9)).iloc[-1])
