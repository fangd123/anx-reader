#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${COSYVOICE3_BASE_URL:-http://127.0.0.1:5050}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log() {
  printf '[cosyvoice3-smoke] %s\n' "$*"
}

post_json() {
  local body="$1"
  local headers_file="$2"
  local output_file="$3"
  curl -sS \
    -D "$headers_file" \
    -o "$output_file" \
    -H 'Authorization: Bearer local-noauth' \
    -H 'Content-Type: application/json' \
    --data "$body" \
    "$BASE_URL/v1/audio/speech"
}

assert_header() {
  local file="$1"
  local pattern="$2"
  if ! grep -Eiq "$pattern" "$file"; then
    printf '[cosyvoice3-smoke] ERROR: expected header pattern not found: %s\n' "$pattern" >&2
    exit 1
  fi
}

assert_nonempty_file() {
  local file="$1"
  if [ ! -s "$file" ]; then
    printf '[cosyvoice3-smoke] ERROR: expected non-empty file: %s\n' "$file" >&2
    exit 1
  fi
}

log "Checking health endpoint"
curl -fsS "$BASE_URL/healthz" >"$TMP_DIR/healthz.json"
python3 - "$TMP_DIR/healthz.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
assert payload["ready"] is True, payload
assert payload["concurrency_limit"] == 1, payload
PY

log "Checking voice manifest endpoint"
curl -fsS "$BASE_URL/v1/audio/voices" >"$TMP_DIR/voices.json"
python3 - "$TMP_DIR/voices.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], "r", encoding="utf-8"))
voice_ids = {voice["id"] for voice in payload["data"]}
assert {"book_cn_a", "book_cn_b"} <= voice_ids, payload
PY

log "Testing OpenAI default voice fallback with mp3 output"
post_json \
  '{"model":"Fun-CosyVoice3-0.5B-2512","voice":"alloy","input":"这是一个 MP3 回退测试。","response_format":"mp3"}' \
  "$TMP_DIR/alloy.headers" \
  "$TMP_DIR/alloy.mp3"
assert_nonempty_file "$TMP_DIR/alloy.mp3"
assert_header "$TMP_DIR/alloy.headers" '^x-cosyvoice-resolved-voice:\s*book_cn_a'
assert_header "$TMP_DIR/alloy.headers" '^content-type:\s*audio/mpeg'

log "Testing cross-lingual preset"
post_json \
  '{"model":"Fun-CosyVoice3-0.5B-2512","voice":"book_cn_b","input":"Testing book cn b output.","response_format":"wav"}' \
  "$TMP_DIR/book_cn_b.headers" \
  "$TMP_DIR/book_cn_b.wav"
assert_nonempty_file "$TMP_DIR/book_cn_b.wav"
assert_header "$TMP_DIR/book_cn_b.headers" '^x-cosyvoice-resolved-voice:\s*book_cn_b'
assert_header "$TMP_DIR/book_cn_b.headers" '^content-type:\s*audio/wav'

log "Testing unknown voice fallback and speed parsing"
post_json \
  '{"model":"Fun-CosyVoice3-0.5B-2512","voice":"mystery_voice","input":"这是一个语速控制测试。","instructions":"Please speak at a speed of 0.80x.\nPlease use a pitch of 1.25x.","response_format":"mp3"}' \
  "$TMP_DIR/speed.headers" \
  "$TMP_DIR/speed.mp3"
assert_nonempty_file "$TMP_DIR/speed.mp3"
assert_header "$TMP_DIR/speed.headers" '^x-cosyvoice-resolved-voice:\s*book_cn_a'
assert_header "$TMP_DIR/speed.headers" '^x-cosyvoice-speed:\s*0.80'

log "Testing unsupported response format"
status_code="$(
  curl -sS \
    -o "$TMP_DIR/invalid.txt" \
    -w '%{http_code}' \
    -H 'Authorization: Bearer local-noauth' \
    -H 'Content-Type: application/json' \
    --data '{"model":"Fun-CosyVoice3-0.5B-2512","voice":"alloy","input":"bad format","response_format":"flac"}' \
    "$BASE_URL/v1/audio/speech"
)"
if [ "$status_code" != "400" ]; then
  printf '[cosyvoice3-smoke] ERROR: expected 400 for unsupported response_format, got %s\n' "$status_code" >&2
  exit 1
fi

log "Smoke test passed"
