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
