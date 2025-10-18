#!/usr/bin/env bash
set -euo pipefail
APP="/opt/ats-quant"; BK="$APP/backups"; mkdir -p "$BK"
cd "$APP"

# 1) 生成备份
STAMP=$(date -u +%Y%m%d_%H%M%S)
crontab -l > deploy/CRON.backup.${STAMP}.txt 2>/dev/null || true
docker compose config > deploy/compose.rendered.${STAMP}.yaml 2>/dev/null || true
docker ps -a > deploy/docker.ps.${STAMP}.txt 2>/dev/null || true
docker images > deploy/docker.images.${STAMP}.txt 2>/dev/null || true
TAR="$BK/ats_backup_${STAMP}.tar.gz"
sudo tar -czf "$TAR" .env docker-compose.yml docker/ scripts/ deploy/ logs/ \
  --exclude='**/__pycache__' --exclude='.git' --warning=no-file-changed
sudo chmod 644 "$TAR"
sha256sum "$TAR" | tee "$BK/ats_backup_${STAMP}.sha256"

# 2) 读取环境变量
while IFS='=' read -r k v; do
  [[ -z "$k" || "$k" =~ ^# ]] && continue
  v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"
  export "$k"="$v"
done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$APP/.env" || true)

# 3) 根据大小选择发送策略
SIZE=$(stat -c %s "$TAR")
MB=$(( (SIZE + 1048575) / 1048576 ))
echo "[INFO] Backup size: ${MB}MB"

send_file() {
  local f="$1"
  local cap="$2"
  # 常规
  RESP=$(curl -sS -4 -m 60 -F chat_id="$TELEGRAM_CHAT_ID_PRIMARY" -F caption="$cap" -F document=@"$f" \
         "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" || true)
  echo "sendDocument(normal) => $RESP"
  echo "$RESP" | grep -q '"ok":true' && return 0
  # 直连 IP 重试
  for IP in 149.154.167.220 149.154.167.233 149.154.167.198; do
    RESP=$(curl -sS -4 -m 60 --resolve api.telegram.org:443:$IP \
           -F chat_id="$TELEGRAM_CHAT_ID_PRIMARY" -F caption="$cap" -F document=@"$f" \
           "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" || true)
    echo "sendDocument($IP) => $RESP"
    echo "$RESP" | grep -q '"ok":true' && return 0
  done
  return 1
}

CAP="🗂️ ATS 备份包 $(basename "$TAR") — $(hostname)"
if [ "$MB" -le 45 ]; then
  # 直接发单文件
  if ! send_file "$TAR" "$CAP"; then
    echo "[WARN] 文件发送失败，尝试文本兜底（摘要+清单）"
    {
      echo "$CAP"
      echo "大小：${MB}MB  SHA256: $(cut -d' ' -f1 "$BK/ats_backup_${STAMP}.sha256")"
      echo "包含：.env docker-compose.yml docker/ scripts/ deploy/ logs/"
    } > "$BK/backup_note_${STAMP}.txt"
    curl -sS -4 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID_PRIMARY" --data-urlencode text@"$BK/backup_note_${STAMP}.txt" >/dev/null || true
  fi
else
  # 自动切分为 45MB 分卷并逐卷发送
  echo "[INFO] 分卷发送…"
  split -b 45m "$TAR" "$TAR.part."
  idx=1
  for f in "$TAR".part.*; do
    send_file "$f" "🗂️ 备份分卷 ${idx} — $(basename "$f") | $(hostname)" || true
    idx=$((idx+1))
  done
fi

echo "[OK] 备份流程结束：$TAR"
