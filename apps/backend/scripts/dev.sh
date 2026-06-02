#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

HOST="${MEETING_BACKEND_HOST:-127.0.0.1}"
PORT="${MEETING_BACKEND_PORT:-8765}"
UVICORN_BIN="${UVICORN_BIN:-uvicorn}"

if [[ -x ".venv/bin/uvicorn" ]]; then
    UVICORN_BIN=".venv/bin/uvicorn"
fi

exec "$UVICORN_BIN" meeting_backend.main:app --reload --host "$HOST" --port "$PORT"
