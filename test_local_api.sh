#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8010}"

if [ ! -f ".env" ]; then
  echo ".env not found"
  exit 1
fi

TOKEN="$(grep '^API_TOKEN=' .env | cut -d= -f2- || true)"
if [ -z "${TOKEN}" ]; then
  echo "API_TOKEN missing in .env"
  exit 1
fi

echo "Testing /health"
curl "http://127.0.0.1:${PORT}/health"
echo
echo

echo "Testing /run/all-checks"
curl -X POST "http://127.0.0.1:${PORT}/run/all-checks" -H "X-API-Token: ${TOKEN}"
echo