#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${COSYVOICE3_ROOT:-$HOME/models/cosyvoice3-local}"
HOST="${COSYVOICE3_HOST:-0.0.0.0}"
PORT="${COSYVOICE3_PORT:-5050}"
VENV_PYTHON="$ROOT_DIR/.venv/bin/python"

log() {
  printf '[cosyvoice3-run] %s\n' "$*"
}

if [ ! -x "$VENV_PYTHON" ]; then
  printf '[cosyvoice3-run] ERROR: missing virtualenv at %s\n' "$VENV_PYTHON" >&2
  printf '[cosyvoice3-run] Run bash scripts/cosyvoice3/bootstrap.sh first.\n' >&2
  exit 1
fi

if pgrep -af vllm >/dev/null 2>&1; then
  printf '[cosyvoice3-run] WARNING: detected running vLLM processes. Stop them if VRAM is tight.\n' >&2
  pgrep -af vllm || true
fi

log "Starting CosyVoice3 OpenAI-compatible TTS service on ${HOST}:${PORT}"
exec "$VENV_PYTHON" "$SCRIPT_DIR/server.py" --root-dir "$ROOT_DIR" --host "$HOST" --port "$PORT"
