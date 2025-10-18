import os, time, datetime as dt, requests
from dateutil.tz import tzutc
BOT=os.getenv("TELEGRAM_BOT_TOKEN"); CHAT=os.getenv("TELEGRAM_CHAT_ID_PRIMARY")

def tg(text:str):
    if not (BOT and CHAT): return
    try:
        requests.post(f"https://api.telegram.org/bot{BOT}/sendMessage",
                      data={"chat_id":CHAT,"text":text,"disable_web_page_preview":True}, timeout=10)
    except Exception as e:
        print("TG error:", e, flush=True)

def in_black_window(now: dt.datetime, span=5)->bool:
    # 币安资金费 00/08/16 UTC；黑窗±span 分钟
    if now.hour in (0,8,16):
        return min(now.minute, 60-now.minute) <= span
    return False

from ats.scan import run_scan_once
from ats.notifier import format_scan_to_md

if __name__ == "__main__":
    now = dt.datetime.now(tzutc())
    tg(f"🟢 ATS Phase-1 调度启动 {now:%F %T} UTC | host={os.uname().nodename}")
    while True:
        now = dt.datetime.now(tzutc())
        if in_black_window(now):
            time.sleep(20); continue
        if now.minute==0 and 15<=now.second<25:
            try:
                res = run_scan_once(now)
                tg(format_scan_to_md(res))
            except Exception as e:
                tg(f"🔴 扫描异常：{e!r}")
            time.sleep(65)   # 防抖，跨过本分钟
        else:
            time.sleep(1)