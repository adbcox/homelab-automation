#!/bin/sh
set -eu
BASE_URL="${BASE_URL:-http://127.0.0.1:8010}"
ENV_FILE="${ENV_FILE:-/share/CACHEDEV1_DATA/homelab-automation/.env}"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing env file: $ENV_FILE"
  exit 1
fi
TOKEN="$(grep '^API_TOKEN=' "$ENV_FILE" | cut -d= -f2- || true)"
if [ -z "$TOKEN" ]; then
  echo "API_TOKEN missing in $ENV_FILE"
  exit 1
fi
cmd="${1:-}"
shift || true
case "$cmd" in
  health)
    curl -s "$BASE_URL/health"
    ;;
  start)
    curl -s -X POST "$BASE_URL/session/start" -H "X-API-Token: $TOKEN"
    ;;
  close)
    SESSION_ID="${1:?session_id required}"
    curl -s -X POST "$BASE_URL/session/close" \
      -H "Content-Type: application/json" \
      -H "X-API-Token: $TOKEN" \
      -d "{\"session_id\":\"$SESSION_ID\"}"
    ;;
  open)
    SESSION_ID="${1:?session_id required}"
    URL="${2:?url required}"
    curl -s -X POST "$BASE_URL/session/open" \
      -H "Content-Type: application/json" \
      -H "X-API-Token: $TOKEN" \
      -d "{\"session_id\":\"$SESSION_ID\",\"url\":\"$URL\"}"
    ;;
  read)
    SESSION_ID="${1:?session_id required}"
    curl -s -X POST "$BASE_URL/session/read" \
      -H "Content-Type: application/json" \
      -H "X-API-Token: $TOKEN" \
      -d "{\"session_id\":\"$SESSION_ID\"}"
    ;;
  click-text)
    SESSION_ID="${1:?session_id required}"
    TEXT="${2:?text required}"
    curl -s -X POST "$BASE_URL/session/click" \
      -H "Content-Type: application/json" \
      -H "X-API-Token: $TOKEN" \
      -d "{\"session_id\":\"$SESSION_ID\",\"text\":\"$TEXT\"}"
    ;;
  click-selector)
    SESSION_ID="${1:?session_id required}"
    SELECTOR="${2:?selector required}"
    curl -s -X POST "$BASE_URL/session/click" \
      -H "Content-Type: application/json" \
      -H "X-API-Token: $TOKEN" \
      -d "{\"session_id\":\"$SESSION_ID\",\"selector\":\"$SELECTOR\"}"
    ;;
  type)
    SESSION_ID="${1:?session_id required}"
    SELECTOR="${2:?selector required}"
    TEXT="${3:?text required}"
    curl -s -X POST "$BASE_URL/session/type" \
      -H "Content-Type: application/json" \
      -H "X-API-Token: $TOKEN" \
      -d "{\"session_id\":\"$SESSION_ID\",\"selector\":\"$SELECTOR\",\"text\":\"$TEXT\"}"
    ;;
  press)
    SESSION_ID="${1:?session_id required}"
    KEY="${2:?key required}"
    curl -s -X POST "$BASE_URL/session/press" \
      -H "Content-Type: application/json" \
      -H "X-API-Token: $TOKEN" \
      -d "{\"session_id\":\"$SESSION_ID\",\"key\":\"$KEY\"}"
    ;;
  wait)
    SESSION_ID="${1:?session_id required}"
    MS="${2:?ms required}"
    curl -s -X POST "$BASE_URL/session/wait" \
      -H "Content-Type: application/json" \
      -H "X-API-Token: $TOKEN" \
      -d "{\"session_id\":\"$SESSION_ID\",\"ms\":$MS}"
    ;;
  screenshot)
    SESSION_ID="${1:?session_id required}"
    NAME="${2:-shot.png}"
    curl -s -X POST "$BASE_URL/session/screenshot" \
      -H "Content-Type: application/json" \
      -H "X-API-Token: $TOKEN" \
      -d "{\"session_id\":\"$SESSION_ID\",\"name\":\"$NAME\"}"
    ;;
  list)
    SESSION_ID="${1:?session_id required}"
    curl -s -X POST "$BASE_URL/session/list-clickable" \
      -H "Content-Type: application/json" \
      -H "X-API-Token: $TOKEN" \
      -d "{\"session_id\":\"$SESSION_ID\"}"
    ;;
  *)
    echo "Usage:"
    echo "  bop health"
    echo "  bop start"
    echo "  bop close <session_id>"
    echo "  bop open <session_id> <url>"
    echo "  bop read <session_id>"
    echo "  bop click-text <session_id> <text>"
    echo "  bop click-selector <session_id> <selector>"
    echo "  bop type <session_id> <selector> <text>"
    echo "  bop press <session_id> <key>"
    echo "  bop wait <session_id> <ms>"
    echo "  bop screenshot <session_id> [name]"
    echo "  bop list <session_id>"
    exit 1
    ;;
esac
echo ""
