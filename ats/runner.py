from loguru import logger
from .notifier import send_text

def on_plan(symbol: str, plan: dict, detail: dict):
    send_text(f"📝 计划 {symbol} A+={detail.get(total,0):.1f}\nL1={plan[l1]:.4f} L2={plan[l2]:.4f} L3={plan[l3]:.4f}\nSL={plan[sl]:.4f} TP1={plan[tp1]:.4f} TP2={plan[tp2]:.4f}\nR={plan[R]:.4f} room={plan[room]:.2f} costR={plan[costR]:.2f}")

def place_orders(binance, symbol: str, plan: dict, maker_only=True, dry=True):
    if dry:
        logger.info("[DRY] place maker orders {}", symbol); return True
    tif = "GTX" if maker_only else "GTC"  # LIMIT_MAKER=GTX 兼容处理
    try:
        # 示例：仅挂 L1，一旦成交可扩展 L2/L3 + 保护单
        binance.new_order(symbol=symbol, side="BUY", type="LIMIT", timeInForce=tif,
                          price=f"{plan[l1]:.8f}", quantity="0.001", reduceOnly="false")
        return True
    except Exception as e:
        logger.exception(e)
        send_text(f"❌ 下单失败 {symbol}: ")
        return False

def runner_tick(binance):
    # 占位：读取持仓/订单，触发 BE/TP2、时间止损等
    try:
        _ = binance.position_risk()
    except Exception as e:
        logger.exception(e)
