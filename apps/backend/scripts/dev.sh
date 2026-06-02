#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
uvicorn meeting_backend.main:app --reload --host 127.0.0.1 --port 8765
