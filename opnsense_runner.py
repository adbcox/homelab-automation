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

        results.append(
            {
                "identifier": item.get("identifier") or item.get("device"),
                "description": item.get("description"),
                "device": item.get("device"),
                "status": item.get("status"),
                "addr4": item.get("addr4"),
                "addr6": item.get("addr6"),
                "enabled": item.get("enabled"),
                "routes": item.get("routes", []),
                "gateways": item.get("gateways", []),
            }
        )

    return results


def summarize_gateways(data) -> list[dict]:
    items = []
    if isinstance(data, dict):
        items = data.get("items", [])

    results: list[dict] = []
    for item in items:
        if not isinstance(item, dict):
            continue
        results.append(
            {
                "name": item.get("name"),
                "address": item.get("address"),
                "status": item.get("status_translated") or item.get("status"),
                "loss": item.get("loss"),
                "delay": item.get("delay"),
                "stddev": item.get("stddev"),
            }
        )
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

    verify = not (
        settings.opnsense_url.startswith("https://")
        and settings.ignore_https_errors
    )

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
        system_info = fetch_json(session, system_info_url, verify=verify)
        result["system_info"] = summarize_system_info(system_info)
    except Exception as exc:
        result["errors"].append(
            {
                "section": "system_info",
                "url": system_info_url,
                "error": str(exc),
            }
        )

    try:
        interfaces = fetch_json(session, interfaces_url, verify=verify)
        result["interfaces"] = summarize_interfaces(interfaces)
    except Exception as exc:
        result["errors"].append(
            {
                "section": "interfaces",
                "url": interfaces_url,
                "error": str(exc),
            }
        )

    try:
        gateways = fetch_json(session, gateways_url, verify=verify)
        result["gateways"] = summarize_gateways(gateways)
    except Exception as exc:
        result["errors"].append(
            {
                "section": "gateways",
                "url": gateways_url,
                "error": str(exc),
            }
        )

    return result
