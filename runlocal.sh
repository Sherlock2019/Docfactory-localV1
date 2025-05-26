#!/usr/bin/env bash
set -e

# If venv doesn’t exist, create & install
if [ ! -d venv ]; then
  echo "🐍 Creating virtualenv…"
  python3 -m venv venv
  source venv/bin/activate
  pip install --upgrade pip
  pip install -r requirements.txt
else
  source venv/bin/activate
fi

if [ "$1" = "prod" ]; then
  echo "▶️  Starting Gunicorn…"
  exec gunicorn app:app \
    --bind 0.0.0.0:8000 \
    --workers 4 \
    --timeout 120
else
  echo "▶️  Starting Flask dev server…"
  exec flask run --host=0.0.0.0 --port=5000
fi
