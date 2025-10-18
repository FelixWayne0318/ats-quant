import datetime as dt
from dataclasses import dataclass, asdict

@dataclass
class Candidate:
    symbol: str
    score_trend: float
    score_struct: float
    score_flow: float
    score_total: float
    gateA: bool; gateB: bool; gateC: bool; gateD: bool

def _toy_score(symbol:str, i:int)->Candidate:
    t=70+(i*3)%25; s=68+(i*7)%20; f=65+(i*5)%22
    tot=round(0.4*t+0.3*s+0.3*f,2)
    return Candidate(symbol,t,s,f,tot,t>72,s>70,True,True)

def run_scan_once(now_utc: dt.datetime):
    syms=["BTCUSDT","ETHUSDT","BNBUSDT","SOLUSDT"]
    cands=sorted((_toy_score(s,i) for i,s in enumerate(syms)),
                 key=lambda x:x.score_total, reverse=True)
    a_plus=[c for c in cands if c.score_total>=90 and all([c.gateA,c.gateB,c.gateC,c.gateD])]
    return {"ts":now_utc.strftime("%F %T UTC"),
            "pool_size":len(syms),
            "top":[asdict(c) for c in cands[:5]],
            "a_plus":[asdict(c) for c in a_plus]}