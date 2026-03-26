#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts playwright/.auth

cat > requirements.txt <<'EOF'
playwright==1.52.0
python-dotenv==1.0.1
requests==2.32.3
fastapi==0.115.12
uvicorn==0.34.0
EOF

cat > .env.example <<'EOF'
QNAP_URL=http://192.168.10.114/
QNAP_USERNAME=admin
QNAP_PASSWORD=change-me

OPNSENSE_URL=http://192.168.10.1
OPNSENSE_API_KEY=change-me
OPNSENSE_API_SECRET=change-me

HEADLESS=false
IGNORE_HTTPS_ERRORS=true
API_TOKEN=change-me-long-random-string
EOF

cat > .gitignore <<'EOF'
.env
.venv/
__pycache__/
playwright/.auth/
artifacts/
*.pyc
EOF

cat > bootstrap.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
python -m playwright install chromium

mkdir -p artifacts playwright/.auth
cp -n .env.example .env || true
chmod +x start_api.sh run_local_api.sh test_local_api.sh || true

echo
echo "Done."
echo "Run checks with:"
echo "  source .venv/bin/activate"
echo "  python app.py all-checks"
echo
echo "Start API with:"
echo "  PORT=8010 ./start_api.sh"
echo
echo "Then test:"
echo "  curl http://127.0.0.1:8010/health"
echo "  curl -X POST http://127.0.0.1:8010/run/all-checks -H 'X-API-Token: YOUR_TOKEN'"
EOF

cat > start_api.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

source .venv/bin/activate
PORT="${PORT:-8010}"
uvicorn api_server:app --host 0.0.0.0 --port "$PORT"
EOF

cat > api_server.py <<'EOF'
from __future__ import annotations

import os
from typing import Optional

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

from app import run_all_checks, run_opnsense_health, run_qnap_check

load_dotenv()

app = FastAPI(title="Homelab Automation API", version="1.1.1")


def require_token(x_api_token: Optional[str]) -> None:
    expected = os.environ.get("API_TOKEN", "").strip()
    if not expected:
        raise HTTPException(status_code=500, detail="API token is not configured")
    if not x_api_token or x_api_token.strip() != expected:
        raise HTTPException(status_code=401, detail="Unauthorized")


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "service": "homelab-automation",
        "auth": "token-required-for-run-endpoints",
    }


@app.post("/run/qnap-check")
def api_qnap_check(x_api_token: Optional[str] = Header(default=None)):
    require_token(x_api_token)
    try:
        result = run_qnap_check()
        return JSONResponse(content=result)
    except Exception as exc:
        return JSONResponse(
            status_code=500,
            content={"ok": False, "error": str(exc), "section": "qnap"},
        )


@app.post("/run/opnsense-health")
def api_opnsense_health(x_api_token: Optional[str] = Header(default=None)):
    require_token(x_api_token)
    try:
        result = run_opnsense_health()
        return JSONResponse(content=result)
    except Exception as exc:
        return JSONResponse(
            status_code=500,
            content={"ok": False, "error": str(exc), "section": "opnsense"},
        )


@app.post("/run/all-checks")
def api_all_checks(x_api_token: Optional[str] = Header(default=None)):
    require_token(x_api_token)
    try:
        result = run_all_checks()
        return JSONResponse(content=result)
    except Exception as exc:
        return JSONResponse(
            status_code=500,
            content={"ok": False, "error": str(exc), "section": "all-checks"},
        )
EOF

chmod +x bootstrap.sh start_api.sh

echo
echo "All files created or updated."
echo
echo "Next steps:"
echo "  1) cp -n .env.example .env"
echo "  2) edit .env with real values"
echo "  3) ./bootstrap.sh"
echo "  4) source .venv/bin/activate"
echo "  5) python app.py all-checks"
echo "  6) PORT=8010 ./start_api.sh"
echo
echo "Test commands:"
echo "  curl http://127.0.0.1:8010/health"
echo "  curl -X POST http://127.0.0.1:8010/run/all-checks -H 'X-API-Token: YOUR_TOKEN'"
