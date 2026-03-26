#!/usr/bin/env bash
set -euo pipefail

source .venv/bin/activate
PORT="${PORT:-8010}"
uvicorn api_server:app --host 0.0.0.0 --port "$PORT"
