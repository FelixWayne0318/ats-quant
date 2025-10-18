#!/usr/bin/env bash
set -Eeuo pipefail

STEP="${1:-}"
APP_DIR="/opt/ats-quant"
ENV_FILE="$APP_DIR/.env"
REPORT_DIR="$APP_DIR/reports"
TS="$(date -u +%Y-%m-%d_%H%M%S)"
REPORT="${REPORT_DIR}/selfcheck_${STEP}_${TS}.txt"

mkdir -p "$REPORT_DIR"
# 颜色
BOLD=$(printf '\033[1m'); CYAN=$(printf '\033[36m'); GREEN=$(printf '\033[32m'); YELLOW=$(printf '\033[33m'); RED=$(printf '\033[31m'); RESET=$(printf '\033[0m')
p(){ printf "%s\n" "$*" | tee -a "$REPORT" ; }
ok(){ printf "%b\n" "${GREEN}✔ PASS${RESET} $*" | tee -a "$REPORT" ; }
wr(){ printf "%b\n" "${YELLOW}⚠ WARN${RESET} $*" | tee -a "$REPORT" ; }
ng(){ printf "%b\n" "${RED}✖ FAIL${RESET} $*" | tee -a "$REPORT" ; }

[ -f "$ENV_FILE" ] && . "$ENV_FILE" || true
FAPI="${BINANCE_FAPI_BASE:-https://fapi.binance.com}"

# 发送器
. /opt/ats-quant/scripts/sc_send.sh

case "$STEP" in
  telegram)
    p "${BOLD}STEP: Telegram 连通${RESET}"
    getent hosts api.telegram.org >/dev/null 2>&1 && ok "DNS 解析 api.telegram.org 正常" || wr "DNS 解析失败"
    send_msg "🧪 Telegram 自检开始 ${TS} UTC | $(hostname)"
    if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID_PRIMARY:-}" ]; then
      curl -sS -m 10 "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID_PRIMARY}" \
        --data-urlencode "text=✅ Telegram sendMessage OK ${TS} UTC | $(hostname)" \
        -d "disable_web_page_preview=true" >/dev/null && ok "sendMessage 成功" || ng "sendMessage 失败"
    else
      ng "缺少 TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID_PRIMARY"
    fi
    ;;

  github)
    p "${BOLD}STEP: GitHub 读写分离${RESET}"
    KEY_RD="$HOME/.ssh/id_ed25519_github_deploy"
    KEY_WR="$HOME/.ssh/id_ed25519_github_push"
    [ -f "$KEY_RD" ] && ok "只读 key 存在: $KEY_RD" || wr "未见只读 key: $KEY_RD"
    [ -f "$KEY_WR" ] && ok "写入 key 存在: $KEY_WR" || wr "未见写入 key: $KEY_WR"
    ssh -T github-read  -o StrictHostKeyChecking=no 2>&1 | grep -qi "successfully authenticated" && ok "读通道认证成功" || ng "读通道认证失败"
    ssh -T github-write -o StrictHostKeyChecking=no 2>&1 | grep -qi "successfully authenticated" && ok "写通道认证成功(需 Allow write access)" || ng "写通道认证失败"

    if git -C "$APP_DIR" rev-parse >/dev/null 2>&1; then
      RMT="$(git -C "$APP_DIR" remote -v)"; p "$RMT"
      echo "$RMT" | grep -q "fetch.*github-read"  && ok "fetch→github-read" || wr "fetch 未指向 github-read"
      echo "$RMT" | grep -q "push.*github-write" && ok "push→github-write" || wr "push 未指向 github-write"
      git -C "$APP_DIR" fetch --all -q && ok "git fetch 正常" || wr "git fetch 失败"
      BR=$(git -C "$APP_DIR" rev-parse --abbrev-ref HEAD); SH=$(git -C "$APP_DIR" rev-parse --short HEAD)
      ok "分支：$BR；commit：$SH"
    else
      wr "未检测到 Git 仓库：$APP_DIR"
    fi
    ;;

  binance)
    p "${BOLD}STEP: Binance 连通性${RESET}"
    curl -sS -m 8 "$FAPI/fapi/v1/ping" >/dev/null && ok "GET /ping 正常" || ng "/ping 失败"
    curl -sS -m 8 "$FAPI/fapi/v1/time" >/dev/null && ok "GET /time 正常" || ng "/time 失败"
    if [ -n "${BINANCE_API_KEY:-}" ] && [ -n "${BINANCE_API_SECRET:-}" ]; then
      ts_ms=$(($(date +%s%3N))); query="timestamp=${ts_ms}"
      sig=$(printf "%s" "$query" | openssl dgst -sha256 -hmac "$BINANCE_API_SECRET" | awk '{print $2}')
      code=$(curl -sS -m 12 -w "%{http_code}" -o /tmp/bal.json -H "X-MBX-APIKEY: ${BINANCE_API_KEY}" "$FAPI/fapi/v2/balance?${query}&signature=${sig}")
      if [ "$code" = "200" ] && grep -q '"balance"' /tmp/bal.json; then ok "签名接口通过：API 有效 & IP 白名单 OK"; else ng "签名接口失败(HTTP $code)"; fi
    else
      wr "未配置 BINANCE_API_*，跳过签名接口"
    fi
    ;;

  docker)
    p "${BOLD}STEP: Docker / Compose / 容器${RESET}"
    docker --version >/dev/null 2>&1 && ok "$(docker --version)" || ng "docker 不可用"
    docker compose version >/dev/null 2>&1 && ok "$(docker compose version)" || wr "docker compose 不可用"
    [ -S /var/run/docker.sock ] && ok "docker.sock 存在: $(ls -l /var/run/docker.sock)" || ng "docker.sock 不存在"
    if [ -f "$APP_DIR/docker-compose.yml" ]; then
      OUT=$(docker compose -f "$APP_DIR/docker-compose.yml" ps 2>&1 || true); echo "$OUT" | tee -a "$REPORT"
      echo "$OUT" | grep -q "ats-quant" && ok "发现容器：ats-quant" || wr "未发现容器（到 $APP_DIR 执行 up -d --build）"
      LOGS=$(docker logs --tail 120 ats-quant 2>&1 || true)
      echo "$LOGS" | grep -Eqi "ATS minimal app|scan tick|Starting ATS" && ok "容器日志关键字命中" || wr "容器日志未见关键字"
    else
      wr "未找到 docker-compose.yml"
    fi
    ;;

  cron)
    p "${BOLD}STEP: Cron 定时与回推脚本${RESET}"
    if crontab -l >/dev/null 2>&1; then crontab -l | tee -a "$REPORT"; ok "读取 crontab 成功"; else wr "没有 crontab"; fi
    if [ -x "$APP_DIR/scripts/push_artifacts.sh" ]; then
      ok "发现 push_artifacts.sh（白名单回推脚本）"
      bash "$APP_DIR/scripts/push_artifacts.sh" >>"$REPORT" 2>&1 && ok "尝试回推 GitHub 成功/或无变更" || wr "回推失败（检查写 Key/URL）"
    else
      wr "未发现 push_artifacts.sh（可选）"
    fi
    ;;

  system)
    p "${BOLD}STEP: 系统健康 / 网络${RESET}"
    { df -h; free -m; timedatectl 2>/dev/null; } | tee -a "$REPORT" >/dev/null
    OUTIP=$(curl -sS -m 8 https://api.ipify.org || echo "?"); p "出网 IP：$OUTIP"
    if command -v ufw >/dev/null 2>&1; then ufw status | tee -a "$REPORT" >/dev/null; else wr "UFW 未安装"; fi
    ;;

  *)
    echo "用法：$0 {telegram|github|binance|docker|cron|system}"
    exit 1
    ;;
esac

# 每步都各自推送“文件报告”
. /opt/ats-quant/scripts/sc_send.sh
send_file "📎 ${STEP} 自检报告 ${TS} UTC | $(hostname)" "$REPORT"
