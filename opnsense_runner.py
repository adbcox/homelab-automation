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
