#!/usr/bin/env bash
# 说明：本脚本不会因单项失败退出；所有检查只记录 PASS/WARN/FAIL。
# 适配：Ubuntu + Docker，既支持 `docker compose` 也兼容 `docker-compose`。
# 日志：仅标准输出，适合直接在 Termius 里运行。

# ---------- 基础配置（可按需改） ----------
APP_DIR="${APP_DIR:-/opt/ats-quant}"
ENV_FILE="${ENV_FILE:-$APP_DIR/.env}"
SERVICE_NAME="${SERVICE_NAME:-ats-quant}"        # docker-compose.yml 里的 container_name
EXPECTED_ORIGIN="${EXPECTED_ORIGIN:-git@github.com:FelixWayne0318/ats-quant.git}"

# ---------- UI ----------
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; BOLD="\033[1m"; RESET="\033[0m"
ok(){   printf "${GREEN}✔ PASS${RESET}  %s\n" "$*"; }
warn(){ printf "${YELLOW}⚠ WARN${RESET}  %s\n" "$*"; }
fail(){ printf "${RED}✖ FAIL${RESET}  %s\n" "$*"; }
ttl(){  printf "\n${BOLD}${CYAN}%s${RESET}\n" "$*"; }
mask(){ local s="$1"; local n=${#s}; ((n<=10)) && { echo "***"; return; }; echo "${s:0:6}***${s:n-4:4}"; }

# ---------- 工具函数 ----------
have(){ command -v "$1" >/dev/null 2>&1; }
read_env(){
  # 只读取 .env 中的 KEY=VALUE；忽略注释与空行
  [ -f "$ENV_FILE" ] || return 1
  while IFS='=' read -r k v; do
    [[ -z "$k" ]] && continue
    [[ "$k" =~ ^# ]] && continue
    # 去掉可能的引号
    v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
    export "$k"="$v"
  done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE" || true)
  return 0
}
compose_cmd(){
  if have docker && docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif have docker-compose; then
    echo "docker-compose"
  else
    echo ""
  fi
}
send_tg(){
  local text="$1"
  [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID_PRIMARY" ]] || return 1
  curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID_PRIMARY" -d text="$text" \
    -d disable_web_page_preview=true >/dev/null
}
hmac_sha256(){
  # 用 openssl 生成 HMAC-SHA256 十六进制摘要
  printf "%s" "$1" | openssl dgst -sha256 -hmac "$2" 2>/dev/null | awk '{print $2}'
}

# ---------- 开始 ----------
printf "${BOLD}ATS 全面自检启动：%s (UTC)${RESET}\n" "$(date -u '+%F %T')"
echo "APP_DIR=$APP_DIR"
echo "ENV_FILE=$ENV_FILE"

# 0) 基础命令
ttl "0) 基础命令检查"
for c in git curl openssl docker; do
  if have "$c"; then ok "找到命令：$c"; else fail "未安装命令：$c"; fi
done
CCMD="$(compose_cmd)"
if [ -n "$CCMD" ]; then ok "Compose 可用：$CCMD"; else warn "未检测到 docker compose / docker-compose"; fi

# 1) GitHub / 仓库
ttl "1) GitHub 与仓库"
if ssh -T git@github.com -o BatchMode=yes 2>&1 | grep -qi "successfully authenticated"; then
  ok "SSH 连接 github.com 认证成功（Deploy Key 正常）"
else
  warn "SSH 连接 github.com 未确认成功（可能仍然可用，继续检查 origin）"
fi
if [ -d "$APP_DIR/.git" ]; then
  cd "$APP_DIR" || true
  origin=$(git remote get-url origin 2>/dev/null || echo "")
  if [ "$origin" = "$EXPECTED_ORIGIN" ]; then ok "origin 正确：$origin"; else warn "origin 非预期：$origin（预期：$EXPECTED_ORIGIN）"; fi
  if git fetch origin >/dev/null 2>&1; then ok "git fetch 正常"; else fail "git fetch 失败（检查 Deploy Key / 网络）"; fi
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  commit=$(git rev-parse --short HEAD 2>/dev/null || echo "?")
  ok "当前分支：$branch；commit：$commit"
else
  warn "未发现 $APP_DIR/.git；如需：mkdir -p $APP_DIR && git clone $EXPECTED_ORIGIN $APP_DIR"
fi

# 2) .env
ttl "2) .env 参数（脱敏展示）"
if read_env; then
  [[ -n "$TELEGRAM_BOT_TOKEN"      ]] && ok "TELEGRAM_BOT_TOKEN: $(mask "$TELEGRAM_BOT_TOKEN")" || fail "缺少 TELEGRAM_BOT_TOKEN"
  [[ -n "$TELEGRAM_CHAT_ID_PRIMARY" ]] && ok "TELEGRAM_CHAT_ID_PRIMARY: $TELEGRAM_CHAT_ID_PRIMARY" || fail "缺少 TELEGRAM_CHAT_ID_PRIMARY"
  [[ -n "$BINANCE_API_KEY"         ]] && ok "BINANCE_API_KEY: $(mask "$BINANCE_API_KEY")" || fail "缺少 BINANCE_API_KEY"
  [[ -n "$BINANCE_API_SECRET"      ]] && ok "BINANCE_API_SECRET: $(mask "$BINANCE_API_SECRET")" || fail "缺少 BINANCE_API_SECRET"
  [[ -n "$BINANCE_FAPI_BASE"       ]] || export BINANCE_FAPI_BASE="https://fapi.binance.com"
else
  fail "未找到 .env：$ENV_FILE"
fi

# 3) Telegram
ttl "3) Telegram 推送测试"
if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID_PRIMARY" ]]; then
  if send_tg "🧪 ATS 自检开始 $(date -u '+%F %T UTC') on $(hostname)"; then
    ok "Telegram sendMessage 成功（请在群内确认已收到）"
  else
    fail "Telegram sendMessage 失败（检查 bot 是否在群且有权限 / Token 是否正确）"
  fi
else
  warn "跳过 Telegram 测试（未配置 Token 或 ChatID）"
fi

# 4) Binance
ttl "4) Binance USDT-M 连通性"
if [[ -n "$BINANCE_API_KEY" && -n "$BINANCE_API_SECRET" ]]; then
  if curl -fsS "${BINANCE_FAPI_BASE}/fapi/v1/ping" >/dev/null; then ok "GET /fapi/v1/ping 正常"; else fail "/fapi/v1/ping 失败"; fi
  if curl -fsS "${BINANCE_FAPI_BASE}/fapi/v1/time" >/dev/null; then ok "GET /fapi/v1/time 正常"; else fail "/fapi/v1/time 失败"; fi
  TS=$(($(date +%s%3N)))
  Q="timestamp=${TS}"
  SIG="$(hmac_sha256 "$Q" "$BINANCE_API_SECRET")"
  if curl -fsS -H "X-MBX-APIKEY: ${BINANCE_API_KEY}" \
        "${BINANCE_FAPI_BASE}/fapi/v2/balance?${Q}&signature=${SIG}" >/dev/null; then
    ok "GET /fapi/v2/balance（签名）成功：API Key 有效 & 允许本机 IP"
  else
    fail "/fapi/v2/balance（签名）失败：检查 API 权限 / 受信任 IP / 服务器时间同步"
  fi
else
  warn "跳过 Binance 测试（未配置 API Key/Secret）"
fi

# 5) Docker / 服务
ttl "5) Docker / 服务状态"
if have docker; then
  ok "Docker 已安装：$(docker -v 2>/dev/null)"
else
  fail "Docker 未安装"
fi
if [ -n "$CCMD" ]; then
  ok "Compose：$($CCMD version 2>/dev/null | head -n1)"
else
  warn "未安装 compose；若需启动服务，请先安装 docker compose 插件"
fi

# 容器检查：按名称或模糊匹配
FOUND=""
if docker ps --format '{{.Names}}' | grep -q "^${SERVICE_NAME}$"; then
  FOUND="$SERVICE_NAME"
else
  FOUND="$(docker ps --format '{{.Names}}' | grep -i 'ats' | head -n1)"
fi

if [ -n "$FOUND" ]; then
  state=$(docker inspect -f '{{.State.Status}}' "$FOUND" 2>/dev/null || echo "?")
  if [ "$state" = "running" ]; then
    ok "容器运行中：$FOUND"
    if docker logs --tail 200 "$FOUND" 2>/dev/null | grep -E "部署启动|Binance USDT-M|自检|ATS" >/dev/null; then
      ok "容器日志包含关键启动/自检信息"
    else
      warn "容器日志未见关键字；建议查看：docker logs --tail 200 $FOUND"
    fi
  else
    warn "容器存在但状态=$state；可尝试：$CCMD up -d --build"
  fi
else
  warn "未找到名为 '${SERVICE_NAME}' 的容器；如需运行：在 $APP_DIR 执行  $CCMD up -d --build"
fi

# 6) 自动更新（cron）
ttl "6) 自动更新（cron）"
if crontab -l >/dev/null 2>&1; then
  if crontab -l | grep -q "pull_and_restart.sh"; then
    ok "已配置 cron 自动更新（包含 pull_and_restart.sh）"
  else
    warn "未发现自动更新任务；可添加：*/5 * * * * /opt/ats-quant/deploy/pull_and_restart.sh"
  fi
else
  warn "当前用户无 crontab；如需自动更新：crontab -e"
fi

# 7) 系统健康 / 网络
ttl "7) 系统健康 / 网络"
df -h / | awk 'NR==1{print;next}{printf "磁盘 %s 已用 %s/%s（%s）\n",$NF,$3,$2,$5}'
free -h | awk '/Mem:/ {printf "内存 总:%s 已用:%s 空闲:%s\n",$2,$3,$4}'
if have timedatectl; then
  timedatectl | awk -F': ' '/Time zone|System clock synchronized/{print}'
fi
EGRESS=$(curl -fsS https://api.ipify.org 2>/dev/null || echo "?")
echo "出网 IP：$EGRESS"
if have ufw; then echo "UFW 防火墙：$(ufw status 2>/dev/null | head -n1)"; fi

# 8) SSH 部署密钥
ttl "8) SSH 部署密钥"
if [ -f "$HOME/.ssh/id_ed25519_github_deploy" ] && [ -f "$HOME/.ssh/id_ed25519_github_deploy.pub" ]; then
  p1=$(stat -c '%a' "$HOME/.ssh/id_ed25519_github_deploy" 2>/dev/null || echo "?")
  p2=$(stat -c '%a' "$HOME/.ssh/id_ed25519_github_deploy.pub" 2>/dev/null || echo "?")
  ok "找到 Deploy Key（权限 私钥:$p1 公钥:$p2）"
else
  warn "未找到 Deploy Key：~/.ssh/id_ed25519_github_deploy(.pub)"
fi

# 收尾 Telegram
if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID_PRIMARY" ]]; then
  send_tg "✅ ATS 自检完成 $(date -u '+%F %T UTC') | $(hostname)" >/dev/null 2>&1 || true
fi

printf "\n${BOLD}自检结束。若有 FAIL/WARN，按提示修复即可。${RESET}\n"
