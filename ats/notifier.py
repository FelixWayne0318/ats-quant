import os, requests
from loguru import logger

BOT = os.getenv("TELEGRAM_BOT_TOKEN")
CHAT = os.getenv("TELEGRAM_CHAT_ID_PRIMARY")

def _post(path, **data):
    if not BOT or not CHAT:
        logger.warning("TELEGRAM env not set; skip notify.")
        return
    try:
        requests.post(f"https://api.telegram.org/bot{BOT}{path}",
                      data=dict(chat_id=CHAT, **data), timeout=10)
    except Exception as e:
        logger.warning(f"telegram send failed: {e}")

def send_text(text: str):
    _post("/sendMessage", text=text, parse_mode="Markdown")

def send_text_plain(text: str):
    _post("/sendMessage", text=text)
