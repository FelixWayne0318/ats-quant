#!/usr/bin/env bash
set -euo pipefail
cd /opt/ats-quant
git fetch --all -p
git checkout main || true
git pull --rebase origin main
docker compose up -d --build
docker logs --tail=50 ats-quant
