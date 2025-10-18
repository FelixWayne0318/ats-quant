import os, requests
from loguru import logger

BOT = os.getenv("TELEGRAM_BOT_TOKEN", "")
CHAT = os.getenv("TELEGRAM_CHAT_ID_PRIMARY", "")

def send_text(text: str, parse_mode: str = "Markdown") -> bool:
    if not (BOT and CHAT):
        logger.warning("TELEGRAM env not set; skip notify.")
        return False
    url = f"https://api.telegram.org/bot{BOT}/sendMessage"
    payload = {"chat_id": CHAT, "text": text, "parse_mode": parse_mode}
    try:
        r = requests.post(url, data=payload, timeout=10)
        if r.ok:
            return True
        logger.error(f"telegram error: {r.status_code} {r.text}")
    except Exception as e:
        logger.exception(e)
    return False

def send_file(path: str, caption: str = "") -> bool:
    if not (BOT and CHAT):
        logger.warning("TELEGRAM env not set; skip file.")
        return False
    url = f"https://api.telegram.org/bot{BOT}/sendDocument"
    try:
        with open(path, "rb") as f:
            r = requests.post(url, data={"chat_id": CHAT, "caption": caption}, files={"document": f}, timeout=30)
        if r.ok:
            return True
        logger.error(f"telegram file error: {r.status_code} {r.text}")
    except Exception as e:
        logger.exception(e)
    return False
