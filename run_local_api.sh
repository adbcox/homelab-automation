#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8010}"

if [ ! -f ".env" ]; then
  echo ".env not found"
  exit 1
fi

if [ ! -d ".venv" ]; then
  echo ".venv not found; run ./bootstrap.sh first"
  exit 1
fi

OLD_PID="$(lsof -ti tcp:${PORT} || true)"
if [ -n "${OLD_PID}" ]; then
  echo "Stopping existing process on port ${PORT}: ${OLD_PID}"
  kill "${OLD_PID}" || true
  sleep 1
fi

echo "Starting API on port ${PORT}..."
source .venv/bin/activate
exec uvicorn api_server:app --host 127.0.0.1 --port "${PORT}"