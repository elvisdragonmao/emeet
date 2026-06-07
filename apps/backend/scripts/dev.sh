#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

HOST="${MEETING_BACKEND_HOST:-127.0.0.1}"
PORT="${MEETING_BACKEND_PORT:-8765}"
PROVIDER="${MEETING_BACKEND_PROVIDER:-faster-whisper}"

UV_ARGS=()

case "$PROVIDER" in
    faster-whisper)
        UV_ARGS+=(--extra faster-whisper)
        ;;
    mlx-whisper)
        UV_ARGS+=(--extra mlx-whisper)
        ;;
esac

if [[ -n "${MEETING_BACKEND_UV_EXTRA:-}" ]]; then
    IFS="," read -ra EXTRA_NAMES <<< "$MEETING_BACKEND_UV_EXTRA"
    for extra_name in "${EXTRA_NAMES[@]}"; do
        if [[ -n "$extra_name" ]]; then
            UV_ARGS+=(--extra "$extra_name")
        fi
    done
fi

exec uv run "${UV_ARGS[@]}" uvicorn meeting_backend.main:app --reload --host "$HOST" --port "$PORT"
