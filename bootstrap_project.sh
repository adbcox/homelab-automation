#!/usr/bin/env bash
set -euo pipefail

mkdir -p artifacts playwright/.auth

cat > requirements.txt <<'EOF'
playwright==1.52.0
python-dotenv==1.0.1
requests==2.32.3
EOF

cat > .env.example <<'EOF'
QNAP_URL=http://192.168.10.10
QNAP_USERNAME=admin
QNAP_PASSWORD=change-me

OPNSENSE_URL=https://192.168.10.1
OPNSENSE_API_KEY=change-me
OPNSENSE_API_SECRET=change-me

HEADLESS=false
IGNORE_HTTPS_ERRORS=true
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

echo
echo "Done."
echo "Next:"
echo "  1) Edit .env"
echo "  2) source .venv/bin/activate"
echo "  3) python app.py qnap-check"
echo "  4) python app.py opnsense-health"
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
ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
AUTH_DIR.mkdir(parents=True, exist_ok=True)


@dataclass
class Settings:
    qnap_url: str
    qnap_username: str
    qnap_password: str
    headless: bool
    ignore_https_errors: bool


def load_settings() -> Settings:
    load_dotenv()
    return Settings(
        qnap_url=os.environ.get("QNAP_URL", "").rstrip("/"),
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
        self.page.goto(self.settings.qnap_url, wait_until="domcontentloaded", timeout=30000)

    def try_login(self) -> bool:
        self.goto_login()

        user_selectors = [
            'input[name="username"]',
            'input[id="username"]',
            'input[placeholder*="user" i]',
            'input[type="text"]',
        ]
        pass_selectors = [
            'input[name="password"]',
            'input[id="password"]',
            'input[type="password"]',
        ]
        button_selectors = [
            'button:has-text("Sign in")',
            'button:has-text("Login")',
            'button:has-text("Log in")',
            'input[type="submit"]',
            'button[type="submit"]',
        ]

        user_filled = False
        for sel in user_selectors:
            loc = self.page.locator(sel).first
            if loc.count() > 0:
                loc.fill(self.settings.qnap_username)
                user_filled = True
                break

        pass_filled = False
        for sel in pass_selectors:
            loc = self.page.locator(sel).first
            if loc.count() > 0:
                loc.fill(self.settings.qnap_password)
                pass_filled = True
                break

        if not (user_filled and pass_filled):
            return False

        clicked = False
        for sel in button_selectors:
            loc = self.page.locator(sel).first
            if loc.count() > 0:
                loc.click()
                clicked = True
                break

        if not clicked:
            return False

        self.page.wait_for_timeout(4000)
        return True

    def qnap_health_snapshot(self) -> dict:
        self.goto_login()
        before = self.screenshot("qnap-login.png")

        login_ok = self.try_login()
        after = self.screenshot("qnap-after-login.png")

        title = self.page.title()
        body_text = self.page.locator("body").inner_text(timeout=10000)[:4000]

        return {
            "login_attempted": True,
            "login_ok": login_ok,
            "title": title,
            "before_screenshot": before,
            "after_screenshot": after,
            "body_excerpt": body_text,
            "current_url": self.page.url,
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


def load_settings() -> Settings:
    load_dotenv()
    return Settings(
        opnsense_url=os.environ.get("OPNSENSE_URL", "").rstrip("/"),
        api_key=os.environ.get("OPNSENSE_API_KEY", ""),
        api_secret=os.environ.get("OPNSENSE_API_SECRET", ""),
        ignore_https_errors=os.environ.get("IGNORE_HTTPS_ERRORS", "true").lower() == "true",
    )


def fetch_json(session: requests.Session, url: str) -> dict:
    response = session.get(url, timeout=20, verify=False)
    response.raise_for_status()
    return response.json()


def opnsense_health() -> dict:
    settings = load_settings()

    session = requests.Session()
    session.auth = (settings.api_key, settings.api_secret)

    endpoints = {
        "system_info": f"{settings.opnsense_url}/api/diagnostics/system/systemInformation",
        "interfaces": f"{settings.opnsense_url}/api/interfaces/overview/export",
        "gateways": f"{settings.opnsense_url}/api/routes/gateway/status",
    }

    results: dict = {"checked": {}}

    for name, url in endpoints.items():
        try:
            results["checked"][name] = fetch_json(session, url)
        except Exception as exc:
            results["checked"][name] = {"error": str(exc), "url": url}

    return results
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


def run_qnap_check() -> None:
    settings = load_qnap_settings()
    with QnapRunner(settings) as runner:
        result = runner.qnap_health_snapshot()
    write_json("artifacts/qnap-result.json", result)
    print(json.dumps(result, indent=2))


def run_opnsense_health() -> None:
    result = opnsense_health()
    write_json("artifacts/opnsense-result.json", result)
    print(json.dumps(result, indent=2))


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python app.py [qnap-check|opnsense-health]")
        return 1

    command = sys.argv[1].strip().lower()

    if command == "qnap-check":
        run_qnap_check()
        return 0

    if command == "opnsense-health":
        run_opnsense_health()
        return 0

    print(f"Unknown command: {command}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
EOF

chmod +x bootstrap.sh

echo "Project files created."
echo "Now run:"
echo "  ./bootstrap.sh"
echo "Then:"
echo "  cp .env.example .env"
echo "  nano .env"
echo "  source .venv/bin/activate"
echo "  python app.py qnap-check"
echo "  python app.py opnsense-health"