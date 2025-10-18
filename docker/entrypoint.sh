#!/usr/bin/env bash
set -e
cd /app
python -V
if [ -f requirements.txt ]; then
  python -m pip install --upgrade pip >/dev/null 2>&1 || true
  pip install --no-cache-dir -r requirements.txt
fi
exec python -u app.py
