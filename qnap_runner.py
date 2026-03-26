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
            'input[name="username"]',
            'input[id="username"]',
            'input[placeholder*="user" i]',
            'input[type="text"]',
        ]
        pass_selectors = [
            'input[name="password"]',
            'input[id="password"]',
            'input[id="pwd"]',
            'input[placeholder*="password" i]',
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
            'text="Storage & Snapshots"',
            'text="Storage"',
            '[title="Storage & Snapshots"]',
            '[aria-label="Storage & Snapshots"]',
            'a:has-text("Storage & Snapshots")',
            'div:has-text("Storage & Snapshots")',
            'span:has-text("Storage & Snapshots")',
            'li:has-text("Storage & Snapshots")',
            'a:has-text("Storage")',
            'div:has-text("Storage")',
            'span:has-text("Storage")',
            'li:has-text("Storage")',
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
