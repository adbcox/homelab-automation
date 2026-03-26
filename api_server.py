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
