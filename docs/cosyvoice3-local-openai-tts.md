# CosyVoice3 Local OpenAI-Compatible TTS for `anx-reader`

This setup keeps the Flutter app unchanged and exposes a local OpenAI-compatible TTS endpoint that `anx-reader` can call directly.

## What Gets Added

- Runtime root: `~/models/cosyvoice3-local/`
- Service endpoint: `http://<LAN-IP>:5050/v1/audio/speech`
- Model: `FunAudioLLM/Fun-CosyVoice3-0.5B-2512`
- Voice aliases:
  - `book_cn_a`: zero-shot Chinese book narration
  - `book_cn_b`: cross-lingual official reference voice
- OpenAI preset names such as `alloy`, `nova`, `sage`, and unknown voice names all fall back to `book_cn_a`
- Request serialization: `asyncio.Semaphore(1)` keeps synthesis single-concurrency even if `anx-reader` prefetches multiple segments

## Before You Start

Stop any GPU-heavy `vLLM` service first. On an `RTX 4080 16GB`, leaving `vLLM` resident while `anx-reader` prefetches TTS can push CosyVoice3 into OOM.

Useful checks:

```bash
pgrep -af vllm
nvidia-smi
```

If needed:

```bash
pkill -f vllm
```

## Bootstrap

From the repository root:

```bash
bash scripts/cosyvoice3/bootstrap.sh
```

The bootstrap script does the following:

- Creates `~/models/cosyvoice3-local/.venv` with `uv venv --python 3.10`
- Clones upstream `CosyVoice` into `~/models/cosyvoice3-local/src/CosyVoice`
- Pulls `CosyVoice` from the default mainland mirror `https://ghfast.top/https://github.com/FunAudioLLM/CosyVoice.git`
- Pulls `third_party/Matcha-TTS` from the default mainland mirror `https://ghfast.top/https://github.com/shivammehta25/Matcha-TTS.git`
- Initializes the `third_party/Matcha-TTS` submodule
- Installs upstream `requirements.txt` through the Aliyun PyPI mirror
- Installs `sox`, `libsox-dev`, `ffmpeg`, and `git` through `apt-get` when available
- Downloads only the inference-required CosyVoice3 files from ModelScope, instead of the full training-oriented repository snapshot
- Downloads:
  - `FunAudioLLM/Fun-CosyVoice3-0.5B-2512`
  - `iic/CosyVoice-ttsfrd`
- Extracts `ttsfrd` resource files from `resource.tar`
- Attempts to install `ttsfrd` first; if that fails, it keeps going and CosyVoice falls back to `wetext`
- Copies the official `zero_shot_prompt.wav` and `cross_lingual_prompt.wav` into `~/models/cosyvoice3-local/voices/`
- Generates `~/models/cosyvoice3-local/voices/presets.json`

Environment overrides:

```bash
COSYVOICE3_ROOT=/data/cosyvoice3-local bash scripts/cosyvoice3/bootstrap.sh
COSYVOICE3_PYTHON_VERSION=3.10 bash scripts/cosyvoice3/bootstrap.sh
GITHUB_MIRROR_PREFIX=https://ghfast.top/https://github.com bash scripts/cosyvoice3/bootstrap.sh
COSYVOICE_REPO_URL=https://ghfast.top/https://github.com/FunAudioLLM/CosyVoice.git \
MATCHA_TTS_REPO_URL=https://ghfast.top/https://github.com/shivammehta25/Matcha-TTS.git \
bash scripts/cosyvoice3/bootstrap.sh
```

## Run The Service

```bash
bash scripts/cosyvoice3/run_server.sh
```

Defaults:

- Host: `0.0.0.0`
- Port: `5050`
- Auth: none on the server side

Environment overrides:

```bash
COSYVOICE3_HOST=0.0.0.0 COSYVOICE3_PORT=5050 bash scripts/cosyvoice3/run_server.sh
```

## HTTP Interface

### `POST /v1/audio/speech`

Request body:

```json
{
  "model": "Fun-CosyVoice3-0.5B-2512",
  "input": "这是一个测试。",
  "voice": "book_cn_a",
  "instructions": "Please speak at a speed of 0.80x.",
  "response_format": "mp3"
}
```

Behavior:

- `input` is required
- `response_format` supports only `mp3` and `wav`
- `instructions` parses `Please speak at a speed of {n}x.` and clamps to `0.7` through `1.3`
- `Please use a pitch of {n}x.` is accepted and ignored
- `Authorization` is ignored by the server, but the app still needs a non-empty API key field

Useful response headers for debugging:

- `X-CosyVoice-Resolved-Voice`
- `X-CosyVoice-Voice-Mode`
- `X-CosyVoice-Speed`

### `GET /healthz`

Returns readiness, GPU visibility, model path, sample rate, loaded voices, and `concurrency_limit=1`.

### `GET /v1/audio/voices`

Returns the current preset aliases and the OpenAI-compatible names that fall back to `book_cn_a`.

## Smoke Test

After the server is up:

```bash
bash scripts/cosyvoice3/smoke_test.sh
```

The smoke test checks:

- `GET /healthz`
- `GET /v1/audio/voices`
- `voice=alloy` falls back to `book_cn_a`
- `voice=book_cn_b` returns audio
- unknown voices fall back to `book_cn_a`
- `Please speak at a speed of 0.80x.` is parsed
- unsupported `response_format` returns `400`

## Manual `curl` Checks

MP3 fallback from OpenAI default voice:

```bash
curl -sS \
  -H 'Authorization: Bearer local-noauth' \
  -H 'Content-Type: application/json' \
  --data '{"model":"Fun-CosyVoice3-0.5B-2512","voice":"alloy","input":"这是一个测试。","response_format":"mp3"}' \
  http://127.0.0.1:5050/v1/audio/speech \
  > /tmp/cosyvoice-alloy.mp3
```

Cross-lingual preset:

```bash
curl -sS \
  -H 'Authorization: Bearer local-noauth' \
  -H 'Content-Type: application/json' \
  --data '{"model":"Fun-CosyVoice3-0.5B-2512","voice":"book_cn_b","input":"Testing book cn b output.","response_format":"wav"}' \
  http://127.0.0.1:5050/v1/audio/speech \
  > /tmp/cosyvoice-book-cn-b.wav
```

Speed instruction:

```bash
curl -sS -D /tmp/cosyvoice-speed.headers \
  -H 'Authorization: Bearer local-noauth' \
  -H 'Content-Type: application/json' \
  --data '{"model":"Fun-CosyVoice3-0.5B-2512","voice":"book_cn_a","input":"这是一个语速测试。","instructions":"Please speak at a speed of 0.80x.\nPlease use a pitch of 1.10x.","response_format":"mp3"}' \
  http://127.0.0.1:5050/v1/audio/speech \
  > /tmp/cosyvoice-speed.mp3
```

## `anx-reader` Configuration

In `anx-reader`, use:

- TTS service: `OpenAI`
- URL: `http://<LAN-IP>:5050/v1/audio/speech`
- API Key: `local-noauth`
- Model: `Fun-CosyVoice3-0.5B-2512`
- Voice: `book_cn_a` or `book_cn_b`

To find your LAN IP:

```bash
hostname -I | awk '{print $1}'
```

Because the app's OpenAI-compatible TTS provider requires a non-empty API key, `local-noauth` should be filled in even though the local service does not validate bearer tokens.

## Replacing The Reference Voices Later

Keep the alias names stable and swap the files under:

- `~/models/cosyvoice3-local/voices/zero_shot_prompt.wav`
- `~/models/cosyvoice3-local/voices/cross_lingual_prompt.wav`

If you also need to change descriptions or prompt text, edit:

- `~/models/cosyvoice3-local/voices/presets.json`

`book_cn_a` should remain `mode=zero_shot` and `book_cn_b` should remain `mode=cross_lingual` if you want the current service contract to stay compatible.
