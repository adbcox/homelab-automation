#!/usr/bin/env bash
set -euo pipefail

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
python -m playwright install chromium

mkdir -p artifacts playwright/.auth
cp -n .env.example .env || true
chmod +x start_api.sh || true

echo
echo "Done."
echo "Run checks with:"
echo "  source .venv/bin/activate"
echo "  python app.py all-checks"
echo
echo "Start API with:"
echo "  PORT=8001 ./start_api.sh"
echo
echo "Then test:"
echo "  curl http://127.0.0.1:8001/health"
echo "  curl -X POST http://127.0.0.1:8001/run/all-checks -H 'X-API-Token: YOUR_TOKEN'"
