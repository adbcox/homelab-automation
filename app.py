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
