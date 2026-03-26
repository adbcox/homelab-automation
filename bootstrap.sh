#!/usr/bin/env bash
set -euo pipefail

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
python -m playwright install chromium

mkdir -p artifacts playwright/.auth
cp -n .env.example .env || true

echo
echo "Done."
echo "Next:"
echo "  1) Edit .env"
echo "  2) source .venv/bin/activate"
echo "  3) python app.py qnap-check"
echo "  4) python app.py opnsense-health"
