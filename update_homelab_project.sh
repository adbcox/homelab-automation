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

cat > qnap_runner.py <<'EOF'
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv
from playwright.sync_api import Browser, BrowserContext, Page, Playwright, sync_playwright


ARTIFACTS_DIR = Path("artifacts")
AUTH_DIR = Path("playwright/.auth")


def _ensure_dirs() -> None:
    """Create runtime directories. Called at startup, not at import time."""
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    AUTH_DIR.mkdir(parents=True, exist_ok=True)


@dataclass
class Settings:
    qnap_url: str
    qnap_username: str
    qnap_password: str
    headless: bool
    ignore_https_errors: bool


def normalize_qnap_url(url: str) -> str:
    url = url.strip().rstrip("/")
    if not url:
        return url
    if url.startswith("http://"):
        url = "https://" + url[len("http://"):]
    if not url.startswith("https://"):
        url = "https://" + url
    return url


def load_settings() -> Settings:
    load_dotenv()
    return Settings(
        qnap_url=normalize_qnap_url(os.environ.get("QNAP_URL", "")),
        qnap_username=os.environ.get("QNAP_USERNAME", ""),
        qnap_password=os.environ.get("QNAP_PASSWORD", ""),
        headless=os.environ.get("HEADLESS", "false").lower() == "true",
        ignore_https_errors=os.environ.get("IGNORE_HTTPS_ERRORS", "true").lower() == "true",
    )


class QnapRunner:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._pw: Optional[Playwright] = None
        self._browser: Optional[Browser] = None
        self._context: Optional[BrowserContext] = None
        self._page: Optional[Page] = None

    def __enter__(self) -> "QnapRunner":
        _ensure_dirs()
        self._pw = sync_playwright().start()
        self._browser = self._pw.chromium.launch(headless=self.settings.headless)
        self._context = self._browser.new_context(ignore_https_errors=self.settings.ignore_https_errors)
        self._page = self._context.new_page()
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        if self._context:
            self._context.close()
        if self._browser:
            self._browser.close()
        if self._pw:
            self._pw.stop()

    @property
    def page(self) -> Page:
        if self._page is None:
            raise RuntimeError("Browser page not initialized")
        return self._page

    def screenshot(self, name: str) -> str:
        path = ARTIFACTS_DIR / name
        self.page.screenshot(path=str(path), full_page=True)
        return str(path)

    def goto_login(self) -> None:
        base = self.settings.qnap_url
        candidates = [
            base,
            f"{base}/cgi-bin/",
            f"{base}/cgi-bin/login.html",
            f"{base}/cgi-bin/index.cgi",
        ]

        for url in candidates:
            try:
                self.page.goto(url, wait_until="domcontentloaded", timeout=30000)
                self.page.wait_for_timeout(2000)
                title = self.page.title().lower()
                body = self.page.locator("body").inner_text(timeout=5000).lower()
                if "forbidden" not in title and "forbidden" not in body:
                    return
            except Exception:
                continue

        self.page.goto(base, wait_until="domcontentloaded", timeout=30000)

    def is_logged_in(self) -> bool:
        try:
            body = self.page.locator("body").inner_text(timeout=5000).lower()
        except Exception:
            return False

        dashboard_markers = [
            "storage & snapshots",
            "control panel",
            "resource monitor",
            "app center",
            "server2",
        ]
        return any(marker in body for marker in dashboard_markers)

    def try_login(self) -> bool:
        self.goto_login()
        if self.is_logged_in():
            return True

        user_selectors = [
            'input[name="username"]', 'input[id="username"]',
            'input[placeholder*="user" i]', 'input[type="text"]',
        ]
        pass_selectors = [
            'input[name="password"]', 'input[id="password"]',
            'input[id="pwd"]', 'input[placeholder*="password" i]',
            'input[type="password"]',
        ]
        button_selectors = [
            'button:has-text("Sign in")', 'button:has-text("Login")',
            'button:has-text("Log in")', 'input[type="submit"]',
            'button[type="submit"]',
        ]

        user_filled = False
        for sel in user_selectors:
            loc = self.page.locator(sel).first
            if loc.count() > 0:
                try:
                    if loc.is_visible(timeout=2000):
                        loc.fill(self.settings.qnap_username, timeout=5000)
                        user_filled = True
                        break
                except Exception:
                    continue

        pass_filled = False
        for sel in pass_selectors:
            loc = self.page.locator(sel).first
            if loc.count() > 0:
                try:
                    if loc.is_visible(timeout=2000):
                        loc.fill(self.settings.qnap_password, timeout=5000)
                        pass_filled = True
                        break
                except Exception:
                    continue

        if not (user_filled and pass_filled):
            return self.is_logged_in()

        clicked = False
        for sel in button_selectors:
            loc = self.page.locator(sel).first
            if loc.count() > 0:
                try:
                    if loc.is_visible(timeout=2000):
                        loc.click(timeout=5000)
                        clicked = True
                        break
                except Exception:
                    continue

        if clicked:
            self.page.wait_for_timeout(5000)
        return self.is_logged_in()

    def _click_first_working(self, selectors: list[str]) -> bool:
        for sel in selectors:
            try:
                loc = self.page.locator(sel).first
                if loc.count() > 0 and loc.is_visible(timeout=2000):
                    loc.scroll_into_view_if_needed(timeout=3000)
                    loc.click(timeout=5000)
                    self.page.wait_for_timeout(4000)
                    return True
            except Exception:
                continue
        return False

    def go_to_storage_snapshots(self) -> bool:
        selectors = [
            'text="Storage & Snapshots"', 'text="Storage"',
            '[title="Storage & Snapshots"]', '[aria-label="Storage & Snapshots"]',
            'a:has-text("Storage & Snapshots")', 'div:has-text("Storage & Snapshots")',
            'span:has-text("Storage & Snapshots")', 'li:has-text("Storage & Snapshots")',
            'a:has-text("Storage")', 'div:has-text("Storage")',
            'span:has-text("Storage")', 'li:has-text("Storage")',
        ]
        if self._click_first_working(selectors):
            return True
        try:
            all_candidates = self.page.locator("a, button, div, span, li")
            count = min(all_candidates.count(), 300)
            for i in range(count):
                el = all_candidates.nth(i)
                try:
                    text = el.inner_text(timeout=1000).strip()
                    visible = el.is_visible(timeout=1000)
                except Exception:
                    continue
                if not visible:
                    continue
                text_l = text.lower()
                if "storage & snapshots" in text_l or text_l == "storage":
                    try:
                        el.scroll_into_view_if_needed(timeout=3000)
                        el.click(timeout=5000)
                        self.page.wait_for_timeout(4000)
                        return True
                    except Exception:
                        continue
        except Exception:
            pass
        return False

    def extract_interesting_lines(self, body_text: str) -> list[str]:
        keywords = [
            "warning", "error", "degraded", "critical", "failed",
            "healthy", "good", "ok", "raid", "disk", "volume",
            "pool", "snapshot", "storage", "read/write", "abnormal",
        ]
        lines = [line.strip() for line in body_text.splitlines() if line.strip()]
        interesting: list[str] = []
        noise = {
            "good", "warning", "error", "ok", "storage & snapshots",
            "storage", "snapshot", "overview", "data protection",
        }
        for line in lines:
            low = line.lower()
            if low in noise:
                continue
            if any(word in low for word in keywords):
                interesting.append(line)
        deduped: list[str] = []
        seen = set()
        for line in interesting:
            if line not in seen:
                deduped.append(line)
                seen.add(line)
        return deduped[:30]

    def qnap_health_snapshot(self) -> dict:
        self.goto_login()
        login_ok = self.try_login()
        dashboard_shot = self.screenshot("qnap-dashboard.png")
        storage_clicked = False
        if login_ok:
            storage_clicked = self.go_to_storage_snapshots()
        self.page.wait_for_timeout(5000)
        storage_shot = self.screenshot("qnap-storage.png")
        title = self.page.title()
        body_text = self.page.locator("body").inner_text(timeout=10000)[:12000]
        interesting_lines = self.extract_interesting_lines(body_text)
        warning_signals = [
            line for line in interesting_lines
            if any(word in line.lower() for word in ["warning", "error", "degraded", "critical", "failed", "abnormal"])
        ]
        return {
            "qnap_url": self.settings.qnap_url,
            "login_ok": login_ok,
            "storage_clicked": storage_clicked,
            "title": title,
            "current_url": self.page.url,
            "dashboard_screenshot": dashboard_shot,
            "storage_screenshot": storage_shot,
            "warning_count": len(warning_signals),
            "warning_lines": warning_signals,
            "interesting_lines": interesting_lines,
        }
EOF

cat > opnsense_runner.py <<'EOF'
from __future__ import annotations

import os
from dataclasses import dataclass

import requests
from dotenv import load_dotenv


@dataclass
class Settings:
    opnsense_url: str
    api_key: str
    api_secret: str
    ignore_https_errors: bool


def normalize_url(url: str) -> str:
    url = url.strip().rstrip("/")
    if not url:
        return url
    if url.startswith("http://") or url.startswith("https://"):
        return url
    return "http://" + url


def load_settings() -> Settings:
    load_dotenv()
    return Settings(
        opnsense_url=normalize_url(os.environ.get("OPNSENSE_URL", "")),
        api_key=os.environ.get("OPNSENSE_API_KEY", "").strip(),
        api_secret=os.environ.get("OPNSENSE_API_SECRET", "").strip(),
        ignore_https_errors=os.environ.get("IGNORE_HTTPS_ERRORS", "true").lower() == "true",
    )


def fetch_json(session: requests.Session, url: str, verify: bool):
    response = session.get(url, timeout=20, verify=verify)
    response.raise_for_status()
    return response.json()


def summarize_interfaces(data) -> list[dict]:
    results: list[dict] = []
    if not isinstance(data, list):
        return results
    for item in data:
        if not isinstance(item, dict):
            continue
        results.append({
            "identifier": item.get("identifier") or item.get("device"),
            "description": item.get("description"),
            "device": item.get("device"),
            "status": item.get("status"),
            "addr4": item.get("addr4"),
            "addr6": item.get("addr6"),
            "enabled": item.get("enabled"),
            "routes": item.get("routes", []),
            "gateways": item.get("gateways", []),
        })
    return results


def summarize_gateways(data) -> list[dict]:
    items = []
    if isinstance(data, dict):
        items = data.get("items", [])
    results: list[dict] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        results.append({
            "name": item.get("name"),
            "address": item.get("address"),
            "status": item.get("status_translated") or item.get("status"),
            "loss": item.get("loss"),
            "delay": item.get("delay"),
            "stddev": item.get("stddev"),
        })
    return results


def summarize_system_info(data) -> dict:
    if not isinstance(data, dict):
        return {}
    return {
        "name": data.get("name"),
        "versions": data.get("versions", []),
        "updates": data.get("updates"),
    }


def opnsense_health() -> dict:
    settings = load_settings()
    verify = not (settings.opnsense_url.startswith("https://") and settings.ignore_https_errors)
    session = requests.Session()
    session.auth = (settings.api_key, settings.api_secret)

    system_info_url = f"{settings.opnsense_url}/api/diagnostics/system/systemInformation"
    interfaces_url = f"{settings.opnsense_url}/api/interfaces/overview/export"
    gateways_url = f"{settings.opnsense_url}/api/routes/gateway/status"

    result: dict = {
        "base_url": settings.opnsense_url,
        "api_key_present": bool(settings.api_key),
        "api_secret_present": bool(settings.api_secret),
        "system_info": None,
        "interfaces": [],
        "gateways": [],
        "errors": [],
    }

    try:
        result["system_info"] = summarize_system_info(fetch_json(session, system_info_url, verify=verify))
    except Exception as exc:
        result["errors"].append({"section": "system_info", "url": system_info_url, "error": str(exc)})

    try:
        result["interfaces"] = summarize_interfaces(fetch_json(session, interfaces_url, verify=verify))
    except Exception as exc:
        result["errors"].append({"section": "interfaces", "url": interfaces_url, "error": str(exc)})

    try:
        result["gateways"] = summarize_gateways(fetch_json(session, gateways_url, verify=verify))
    except Exception as exc:
        result["errors"].append({"section": "gateways", "url": gateways_url, "error": str(exc)})

    return result
EOF

cat > app.py <<'EOF'
from __future__ import annotations

import json
import sys
from pathlib import Path

from qnap_runner import QnapRunner, load_settings as load_qnap_settings
from opnsense_runner import opnsense_health


def write_json(path: str, data: dict) -> None:
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def summarize_qnap(result: dict) -> dict:
    return {
        "reachable": bool(result.get("title")),
        "login_ok": result.get("login_ok", False),
        "dashboard_ok": result.get("login_ok", False),
        "storage_deep_check_ok": result.get("storage_clicked", False),
        "warning_count": result.get("warning_count", 0),
        "warning_lines": result.get("warning_lines", []),
        "interesting_lines": result.get("interesting_lines", []),
        "current_url": result.get("current_url"),
        "dashboard_screenshot": result.get("dashboard_screenshot"),
        "storage_screenshot": result.get("storage_screenshot"),
    }


def summarize_opnsense(result: dict) -> dict:
    wan = None
    lan = None
    for iface in result.get("interfaces", []):
        if iface.get("identifier") == "wan":
            wan = iface
        if iface.get("identifier") == "lan":
            lan = iface
    return {
        "system_info": result.get("system_info"),
        "lan": lan,
        "wan": wan,
        "gateways": result.get("gateways", []),
        "errors": result.get("errors", []),
    }


def run_qnap_check() -> dict:
    settings = load_qnap_settings()
    with QnapRunner(settings) as runner:
        result = runner.qnap_health_snapshot()
    write_json("artifacts/qnap-result.json", result)
    return result


def run_opnsense_health() -> dict:
    result = opnsense_health()
    write_json("artifacts/opnsense-result.json", result)
    return result


def run_all_checks() -> dict:
    qnap_raw = run_qnap_check()
    opnsense_raw = run_opnsense_health()
    combined = {
        "summary": {
            "qnap": summarize_qnap(qnap_raw),
            "opnsense": summarize_opnsense(opnsense_raw),
        },
        "raw": {
            "qnap": qnap_raw,
            "opnsense": opnsense_raw,
        },
    }
    write_json("artifacts/all-checks.json", combined)
    return combined


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python app.py [qnap-check|opnsense-health|all-checks]")
        return 1
    command = sys.argv[1].strip().lower()
    if command == "qnap-check":
        print(json.dumps(run_qnap_check(), indent=2))
        return 0
    if command == "opnsense-health":
        print(json.dumps(run_opnsense_health(), indent=2))
        return 0
    if command == "all-checks":
        print(json.dumps(run_all_checks(), indent=2))
        return 0
    print(f"Unknown command: {command}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
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
        return JSONResponse(status_code=500, content={"ok": False, "error": str(exc), "section": "qnap"})


@app.post("/run/opnsense-health")
def api_opnsense_health(x_api_token: Optional[str] = Header(default=None)):
    require_token(x_api_token)
    try:
        result = run_opnsense_health()
        return JSONResponse(content=result)
    except Exception as exc:
        return JSONResponse(status_code=500, content={"ok": False, "error": str(exc), "section": "opnsense"})


@app.post("/run/all-checks")
def api_all_checks(x_api_token: Optional[str] = Header(default=None)):
    require_token(x_api_token)
    try:
        result = run_all_checks()
        return JSONResponse(content=result)
    except Exception as exc:
        return JSONResponse(status_code=500, content={"ok": False, "error": str(exc), "section": "all-checks"})
EOF

chmod +x bootstrap.sh start_api.sh

echo
echo "Project files updated."
echo
echo "Next:"
echo "  1) cp -n .env.example .env"
echo "  2) edit .env with real passwords, API keys, and API_TOKEN"
echo "  3) ./bootstrap.sh"
echo "  4) PORT=8010 ./start_api.sh"
echo
echo "Tests:"
echo "  curl http://127.0.0.1:8010/health"
echo "  curl -X POST http://127.0.0.1:8010/run/all-checks -H 'X-API-Token: YOUR_REAL_TOKEN'"
