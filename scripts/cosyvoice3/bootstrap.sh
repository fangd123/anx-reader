#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${COSYVOICE3_ROOT:-$HOME/models/cosyvoice3-local}"
PYTHON_VERSION="${COSYVOICE3_PYTHON_VERSION:-3.10}"
GITHUB_MIRROR_PREFIX="${GITHUB_MIRROR_PREFIX:-https://ghfast.top/https://github.com}"
COSYVOICE_REPO_URL="${COSYVOICE_REPO_URL:-$GITHUB_MIRROR_PREFIX/FunAudioLLM/CosyVoice.git}"
MATCHA_TTS_REPO_URL="${MATCHA_TTS_REPO_URL:-$GITHUB_MIRROR_PREFIX/shivammehta25/Matcha-TTS.git}"
SRC_DIR="$ROOT_DIR/src"
COSYVOICE_DIR="$SRC_DIR/CosyVoice"
MODEL_DIR="$ROOT_DIR/model/Fun-CosyVoice3-0.5B-2512"
TTSFRD_DIR="$ROOT_DIR/ttsfrd/CosyVoice-ttsfrd"
VOICES_DIR="$ROOT_DIR/voices"
VENV_DIR="$ROOT_DIR/.venv"
PRETRAINED_DIR="$COSYVOICE_DIR/pretrained_models"
VENV_PYTHON="$VENV_DIR/bin/python"
FILTERED_REQUIREMENTS="$ROOT_DIR/requirements.inference.txt"
MODEL_ALLOW_PATTERNS=(
  "campplus.onnx"
  "configuration.json"
  "cosyvoice3.yaml"
  "flow.decoder.estimator.fp32.onnx"
  "flow.pt"
  "hift.pt"
  "llm.pt"
  "speech_tokenizer_v3.onnx"
  "CosyVoice-BlankEN/config.json"
  "CosyVoice-BlankEN/generation_config.json"
  "CosyVoice-BlankEN/merges.txt"
  "CosyVoice-BlankEN/model.safetensors"
  "CosyVoice-BlankEN/tokenizer_config.json"
  "CosyVoice-BlankEN/vocab.json"
)
TTSFRD_ALLOW_PATTERNS=(
  "resource.tar"
  "ttsfrd_dependency-*.whl"
  "ttsfrd-*-cp310-*-linux_x86_64.whl"
)

log() {
  printf '[cosyvoice3-bootstrap] %s\n' "$*"
}

warn() {
  printf '[cosyvoice3-bootstrap] WARNING: %s\n' "$*" >&2
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '[cosyvoice3-bootstrap] ERROR: required command not found: %s\n' "$1" >&2
    exit 1
  fi
}

maybe_install_system_packages() {
  if ! command -v apt-get >/dev/null 2>&1; then
    warn "apt-get not found; please ensure sox, libsox-dev, ffmpeg, git, and build tools are installed manually."
    return
  fi

  local sudo_cmd=()
  if [ "$(id -u)" -eq 0 ]; then
    sudo_cmd=()
  elif command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo_cmd=(sudo)
  else
    warn "No passwordless sudo available; skipping apt-get install. Ensure sox, libsox-dev, ffmpeg, and git are present manually."
    return
  fi

  if dpkg -s sox libsox-dev ffmpeg git >/dev/null 2>&1; then
    log "System packages already present: sox libsox-dev ffmpeg git"
    return
  fi

  log "Installing system packages: sox libsox-dev ffmpeg git"
  "${sudo_cmd[@]}" apt-get update
  "${sudo_cmd[@]}" apt-get install -y sox libsox-dev ffmpeg git
}

show_gpu_warning() {
  if pgrep -af vllm >/dev/null 2>&1; then
    warn "Detected running vLLM processes. Stop them before serving CosyVoice3 to avoid GPU OOM."
    pgrep -af vllm || true
  fi
}

prepare_layout() {
  mkdir -p "$SRC_DIR" "$ROOT_DIR/model" "$ROOT_DIR/ttsfrd" "$VOICES_DIR"
}

clone_or_update_cosyvoice() {
  if [ ! -d "$COSYVOICE_DIR/.git" ]; then
    log "Cloning CosyVoice into $COSYVOICE_DIR"
    git clone --depth 1 --single-branch "$COSYVOICE_REPO_URL" "$COSYVOICE_DIR"
  else
    log "Refreshing existing CosyVoice checkout"
    git -C "$COSYVOICE_DIR" remote set-url origin "$COSYVOICE_REPO_URL"
    git -C "$COSYVOICE_DIR" fetch --depth 1 origin
    git -C "$COSYVOICE_DIR" pull --ff-only
  fi

  log "Rewriting Matcha-TTS submodule URL to mirror"
  git -C "$COSYVOICE_DIR" submodule set-url third_party/Matcha-TTS "$MATCHA_TTS_REPO_URL"
  log "Initializing CosyVoice submodules"
  git -C "$COSYVOICE_DIR" submodule update --init --depth 1 --recursive

  if [ -d "$COSYVOICE_DIR/third_party/Matcha-TTS/.git" ]; then
    git -C "$COSYVOICE_DIR/third_party/Matcha-TTS" remote set-url origin "$MATCHA_TTS_REPO_URL" || true
  fi
}

create_virtualenv() {
  log "Ensuring Python $PYTHON_VERSION is available through uv"
  uv python install "$PYTHON_VERSION"

  if [ ! -x "$VENV_PYTHON" ]; then
    log "Creating virtualenv at $VENV_DIR"
    uv venv --python "$PYTHON_VERSION" "$VENV_DIR"
  else
    log "Reusing virtualenv at $VENV_DIR"
  fi
}

install_python_dependencies() {
  export UV_INDEX_URL="${UV_INDEX_URL:-https://mirrors.aliyun.com/pypi/simple/}"
  export PIP_INDEX_URL="${PIP_INDEX_URL:-https://mirrors.aliyun.com/pypi/simple/}"

  log "Preparing inference-only requirements file"
  awk '
    /^deepspeed==/ { next }
    /^tensorrt-cu12==/ { next }
    /^tensorrt-cu12-bindings==/ { next }
    /^tensorrt-cu12-libs==/ { next }
    /^openai-whisper==/ { next }
    { print }
  ' "$COSYVOICE_DIR/requirements.txt" > "$FILTERED_REQUIREMENTS"

  log "Installing CosyVoice Python dependencies through Aliyun PyPI mirror"
  uv pip install --python "$VENV_PYTHON" --index-strategy unsafe-best-match -r "$FILTERED_REQUIREMENTS"

  log "Installing build helpers for packages with broken build isolation metadata"
  uv pip install --python "$VENV_PYTHON" --index-strategy unsafe-best-match 'setuptools<81' wheel

  log "Installing openai-whisper without build isolation"
  uv pip install --python "$VENV_PYTHON" --index-strategy unsafe-best-match --no-build-isolation openai-whisper==20231117
}

download_models() {
  log "Downloading CosyVoice3 model and ttsfrd assets from ModelScope"
  "$VENV_PYTHON" - <<PY
from modelscope import snapshot_download

snapshot_download(
    "FunAudioLLM/Fun-CosyVoice3-0.5B-2512",
    local_dir=r"$MODEL_DIR",
    allow_patterns=[
        "campplus.onnx",
        "configuration.json",
        "cosyvoice3.yaml",
        "flow.decoder.estimator.fp32.onnx",
        "flow.pt",
        "hift.pt",
        "llm.pt",
        "speech_tokenizer_v3.onnx",
        "CosyVoice-BlankEN/config.json",
        "CosyVoice-BlankEN/generation_config.json",
        "CosyVoice-BlankEN/merges.txt",
        "CosyVoice-BlankEN/model.safetensors",
        "CosyVoice-BlankEN/tokenizer_config.json",
        "CosyVoice-BlankEN/vocab.json",
    ],
)
snapshot_download(
    "iic/CosyVoice-ttsfrd",
    local_dir=r"$TTSFRD_DIR",
    allow_patterns=[
        "resource.tar",
        "ttsfrd_dependency-*.whl",
        "ttsfrd-*-cp310-*-linux_x86_64.whl",
    ],
)
PY
}

prepare_ttsfrd_resource() {
  local resource_dir="$TTSFRD_DIR/resource"
  local resource_tar="$TTSFRD_DIR/resource.tar"

  if [ -d "$resource_dir" ]; then
    log "ttsfrd resource already extracted"
    return
  fi

  if [ ! -f "$resource_tar" ]; then
    warn "ttsfrd resource.tar not found; CosyVoice3 will fall back to wetext text frontend."
    return
  fi

  log "Extracting ttsfrd resource archive"
  mkdir -p "$resource_dir"
  tar -xf "$resource_tar" -C "$resource_dir" --strip-components=1
}

install_ttsfrd() {
  local dep_whl
  local main_whl

  dep_whl="$(find "$TTSFRD_DIR" -maxdepth 1 -type f -name 'ttsfrd_dependency-*.whl' | head -n 1 || true)"
  main_whl="$(find "$TTSFRD_DIR" -maxdepth 1 -type f -name 'ttsfrd-*-cp310-*-linux_x86_64.whl' | head -n 1 || true)"

  if [ -z "$dep_whl" ] || [ -z "$main_whl" ]; then
    warn "Could not find ttsfrd wheel files for Python 3.10. Falling back to wetext text frontend."
    return
  fi

  log "Installing ttsfrd wheels"
  if uv pip install --python "$VENV_PYTHON" "$dep_whl" "$main_whl"; then
    log "ttsfrd installed successfully"
  else
    warn "ttsfrd installation failed. CosyVoice3 will fall back to wetext for text normalization."
  fi
}

link_pretrained_assets() {
  mkdir -p "$PRETRAINED_DIR"
  ln -sfn "$TTSFRD_DIR" "$PRETRAINED_DIR/CosyVoice-ttsfrd"
  ln -sfn "$MODEL_DIR" "$PRETRAINED_DIR/Fun-CosyVoice3-0.5B-2512"
  ln -sfn "$MODEL_DIR" "$PRETRAINED_DIR/Fun-CosyVoice3-0.5B"
}

install_reference_voices() {
  log "Copying official reference prompt audio"
  cp -f "$COSYVOICE_DIR/asset/zero_shot_prompt.wav" "$VOICES_DIR/zero_shot_prompt.wav"
  cp -f "$COSYVOICE_DIR/asset/cross_lingual_prompt.wav" "$VOICES_DIR/cross_lingual_prompt.wav"

  log "Generating voice preset manifest"
  "$VENV_PYTHON" - <<PY
import json
from pathlib import Path

voices_dir = Path(r"$VOICES_DIR")
manifest = {
    "generated_by": "scripts/cosyvoice3/bootstrap.sh",
    "voices": [
        {
            "id": "book_cn_a",
            "mode": "zero_shot",
            "prompt_wav": "zero_shot_prompt.wav",
            "prompt_text": "You are a helpful assistant.<|endofprompt|>希望你以后能够做的比我还好呦。",
            "description": "Default Chinese book voice. Also used as the fallback for OpenAI preset voice names and unknown voices.",
            "recommended_for": "General long-form Chinese narration",
        },
        {
            "id": "book_cn_b",
            "mode": "cross_lingual",
            "prompt_wav": "cross_lingual_prompt.wav",
            "description": "Official cross-lingual reference voice.",
            "recommended_for": "Cross-lingual or mixed-language narration",
        },
    ],
}

(voices_dir / "presets.json").write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

print_summary() {
  log "Bootstrap complete"
  log "Root dir: $ROOT_DIR"
  log "Virtualenv: $VENV_DIR"
  log "Model dir: $MODEL_DIR"
  log "Voice manifest: $VOICES_DIR/presets.json"
  log "Next step: bash scripts/cosyvoice3/run_server.sh"
}

main() {
  require_command git
  require_command uv
  require_command python3

  show_gpu_warning
  maybe_install_system_packages
  prepare_layout
  clone_or_update_cosyvoice
  create_virtualenv
  install_python_dependencies
  download_models
  prepare_ttsfrd_resource
  install_ttsfrd
  link_pretrained_assets
  install_reference_voices
  print_summary
}

main "$@"
