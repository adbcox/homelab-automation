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
                self.page.wait_for_timeout(1500)
                title = self.page.title().lower()
                body = self.page.locator("body").inner_text(timeout=5000).lower()
                if "forbidden" not in title and "forbidden" not in body:
                    return
            except Exception:
                continue

        self.page.goto(base, wait_until="domcontentloaded", timeout=30000)

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
            "qnap_url": self.settings.qnap_url,
            "login_attempted": True,
            "login_ok": login_ok,
            "title": title,
            "before_screenshot": before,
            "after_screenshot": after,
            "body_excerpt": body_text,
            "current_url": self.page.url,
        }