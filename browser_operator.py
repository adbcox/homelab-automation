from __future__ import annotations

import os
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

from dotenv import load_dotenv
from playwright.async_api import (
    Browser,
    BrowserContext,
    Page,
    Playwright,
    async_playwright,
)

ARTIFACTS_DIR = Path("artifacts")
STATE_DIR = Path("playwright_state")


def _ensure_dirs() -> None:
    ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
    STATE_DIR.mkdir(parents=True, exist_ok=True)


@dataclass
class OperatorSettings:
    headless: bool
    ignore_https_errors: bool
    default_timeout_ms: int


def load_settings() -> OperatorSettings:
    load_dotenv()
    return OperatorSettings(
        headless=os.environ.get("HEADLESS", "true").lower() == "true",
        ignore_https_errors=os.environ.get("IGNORE_HTTPS_ERRORS", "true").lower() == "true",
        default_timeout_ms=int(os.environ.get("DEFAULT_TIMEOUT_MS", "15000")),
    )


class BrowserSession:
    def __init__(
        self,
        session_id: str,
        pw: Playwright,
        browser: Browser,
        context: BrowserContext,
        page: Page,
    ) -> None:
        self.session_id = session_id
        self._pw = pw
        self._browser = browser
        self._context = context
        self.page = page

    async def close(self) -> None:
        try:
            await self._context.close()
        except Exception:
            pass
        try:
            await self._browser.close()
        except Exception:
            pass
        try:
            await self._pw.stop()
        except Exception:
            pass


class BrowserOperator:
    def __init__(self, settings: OperatorSettings) -> None:
        self.settings = settings
        self.sessions: Dict[str, BrowserSession] = {}

    async def start_session(self) -> dict:
        _ensure_dirs()
        pw = await async_playwright().start()
        browser = await pw.chromium.launch(headless=self.settings.headless)
        context = await browser.new_context(
            ignore_https_errors=self.settings.ignore_https_errors
        )
        page = await context.new_page()
        page.set_default_timeout(self.settings.default_timeout_ms)
        session_id = str(uuid.uuid4())
        self.sessions[session_id] = BrowserSession(session_id, pw, browser, context, page)
        return {
            "session_id": session_id,
            "headless": self.settings.headless,
            "status": "started",
        }

    async def close_session(self, session_id: str) -> dict:
        session = self._get_session(session_id)
        await session.close()
        del self.sessions[session_id]
        return {"session_id": session_id, "status": "closed"}


    async def open_url(self, session_id: str, url: str) -> dict:
        page = self._get_page(session_id)
        response = await page.goto(url, wait_until="domcontentloaded")
        return {
            "session_id": session_id,
            "url": page.url,
            "status_code": response.status if response else None,
        }

    async def click(
        self,
        session_id: str,
        selector: Optional[str] = None,
        text: Optional[str] = None,
        index: Optional[int] = None,
    ) -> dict:
        page = self._get_page(session_id)
        if selector:
            await page.click(selector)
        elif text:
            await page.get_by_text(text, exact=False).first.click()
        elif index is not None:
            clickable = await self._collect_clickable(page)
            if index >= len(clickable):
                raise ValueError(f"Index {index} out of range (found {len(clickable)} elements)")
            el = clickable[index]
            await el.click()
        else:
            raise ValueError("Provide selector, text, or index")
        return {"session_id": session_id, "action": "click", "url": page.url}

    async def type_text(self, session_id: str, selector: str, text: str) -> dict:
        page = self._get_page(session_id)
        await page.fill(selector, text)
        return {"session_id": session_id, "action": "type", "selector": selector}

    async def press_key(self, session_id: str, key: str) -> dict:
        page = self._get_page(session_id)
        await page.keyboard.press(key)
        return {"session_id": session_id, "action": "press", "key": key}

    async def wait_ms(self, session_id: str, ms: int) -> dict:
        page = self._get_page(session_id)
        await page.wait_for_timeout(ms)
        return {"session_id": session_id, "action": "wait", "ms": ms}

    async def screenshot(self, session_id: str) -> dict:
        page = self._get_page(session_id)
        path = ARTIFACTS_DIR / f"{session_id}.png"
        await page.screenshot(path=str(path), full_page=True)
        return {
            "session_id": session_id,
            "screenshot_path": str(path),
            "url": page.url,
        }

    async def read_page(self, session_id: str) -> dict:
        page = self._get_page(session_id)
        text = await page.inner_text("body")
        title = await page.title()
        return {
            "session_id": session_id,
            "url": page.url,
            "title": title,
            "text": text[:8000],
        }

    async def list_clickable(self, session_id: str) -> dict:
        page = self._get_page(session_id)
        elements = await self._collect_clickable(page)
        items: List[dict] = []
        for i, el in enumerate(elements):
            tag = await el.evaluate("e => e.tagName.toLowerCase()")
            label = (await el.text_content() or "").strip()[:80]
            href = await el.get_attribute("href") if tag == "a" else None
            items.append({"index": i, "tag": tag, "label": label, "href": href})
        return {"session_id": session_id, "url": page.url, "elements": items}

    def _get_session(self, session_id: str) -> BrowserSession:
        if session_id not in self.sessions:
            raise KeyError(f"Session {session_id!r} not found")
        return self.sessions[session_id]

    def _get_page(self, session_id: str) -> Page:
        return self._get_session(session_id).page

    async def _collect_clickable(self, page: Page):
        return await page.query_selector_all("a, button, input[type=submit], [role=button]")
