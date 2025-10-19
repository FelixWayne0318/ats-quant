# ATS-Quant · QF v1.0（完整流程 · 模块化）

- 扫描节奏：整点 + 15s
- 选币：24hr tickers → 过滤 → Overlay（热点只增不减）
- 评分：趋势(40) / 结构(30) / 量能(30)，A+≥90 单块≥65
- 闸门：A 真突破 → B 回踩确认 → C 拥挤否决 → D 可执行性
- 计划：L1/L2/L3 限价（maker-only），SL/TP，权重
- 风控：R 体系、并发、冷却、黑窗
- Runner：成交后 BE→TP2，时间止损，异常自愈
- 通知：电报推送（计划/成交/Runner/异常/自检）
- 默认 `DRY_RUN=true`、`TRADING_ENABLED=false`（只模拟）

> `.env` 请只放服务器，不要入库。
