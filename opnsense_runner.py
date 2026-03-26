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
        api_key=os.environ.get("OPNSENSE_API_KEY", ""),
        api_secret=os.environ.get("OPNSENSE_API_SECRET", ""),
        ignore_https_errors=os.environ.get("IGNORE_HTTPS_ERRORS", "true").lower() == "true",
    )


def fetch_json(session: requests.Session, url: str, verify: bool) -> dict:
    response = session.get(url, timeout=20, verify=verify)
    response.raise_for_status()
    return response.json()


def opnsense_health() -> dict:
    settings = load_settings()

    verify = not (
        settings.opnsense_url.startswith("https://")
        and settings.ignore_https_errors
    )

    session = requests.Session()
    session.auth = (settings.api_key, settings.api_secret)

    endpoints = {
        "system_info": f"{settings.opnsense_url}/api/diagnostics/system/systemInformation",
        "interfaces": f"{settings.opnsense_url}/api/interfaces/overview/export",
        "gateways": f"{settings.opnsense_url}/api/routes/gateway/status",
    }

    results: dict = {
        "base_url": settings.opnsense_url,
        "checked": {},
    }

    for name, url in endpoints.items():
        try:
            results["checked"][name] = fetch_json(session, url, verify=verify)
        except Exception as exc:
            results["checked"][name] = {"error": str(exc), "url": url}

    return results