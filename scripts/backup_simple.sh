#!/usr/bin/env bash
set -euo pipefail
TS="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p backups
tar --exclude='db/*' --exclude='data/*' -czf "backups/ats-code-${TS}.tgz" \
  docker-compose.yml requirements.txt params.yml .env \
  ats scripts README.md .gitignore || true
echo "Saved to backups/ats-code-${TS}.tgz"
