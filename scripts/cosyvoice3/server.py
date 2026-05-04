#!/usr/bin/env python3
from __future__ import annotations

import argparse
import asyncio
import io
import json
import os
import re
import shutil
import subprocess
import sys
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import soundfile as sf
import torch
from fastapi import FastAPI, Header, HTTPException, Request
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, ConfigDict, Field
import uvicorn

DEFAULT_ROOT_DIR = Path.home() / "models" / "cosyvoice3-local"
DEFAULT_MODEL_DIR_NAME = "Fun-CosyVoice3-0.5B-2512"
DEFAULT_ZERO_SHOT_PROMPT_TEXT = (
    "You are a helpful assistant.<|endofprompt|>希望你以后能够做的比我还好呦。"
)
DEFAULT_CROSS_LINGUAL_PREFIX = "You are a helpful assistant.<|endofprompt|>"
OPENAI_VOICE_ALIASES = {
    "alloy",
    "ash",
    "ballad",
    "coral",
    "echo",
    "fable",
    "nova",
    "onyx",
    "sage",
    "shimmer",
    "verse",
}
SPEED_RE = re.compile(
    r"Please speak at a speed of\s+([0-9]+(?:\.[0-9]+)?)x\.",
    flags=re.IGNORECASE,
)
MIN_SPEED = 0.7
MAX_SPEED = 1.3

RUNTIME_ROOT_DIR = Path(os.environ.get("COSYVOICE3_ROOT", DEFAULT_ROOT_DIR)).expanduser()
RUNTIME_MODEL_DIR = RUNTIME_ROOT_DIR / "model" / DEFAULT_MODEL_DIR_NAME


@dataclass(frozen=True)
class VoicePreset:
    voice_id: str
    mode: str
    prompt_wav: Path
    prompt_text: str | None
    description: str
    recommended_for: str

    def to_public_dict(self) -> dict[str, Any]:
        return {
            "id": self.voice_id,
            "mode": self.mode,
            "description": self.description,
            "recommended_for": self.recommended_for,
            "prompt_wav": self.prompt_wav.name,
        }


class SpeechRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    model: str | None = None
    input: str = Field(..., min_length=1)
    voice: str | None = None
    instructions: str | None = None
    response_format: str | None = "mp3"


class CosyVoiceOpenAiAdapter:
    def __init__(self, root_dir: Path, model_dir: Path) -> None:
        self.root_dir = root_dir.expanduser()
        self.model_dir = model_dir.expanduser()
        self.source_dir = self.root_dir / "src" / "CosyVoice"
        self.matcha_dir = self.source_dir / "third_party" / "Matcha-TTS"
        self.voices_dir = self.root_dir / "voices"
        self.manifest_path = self.voices_dir / "presets.json"
        self.ffmpeg_available = shutil.which("ffmpeg") is not None
        self.gpu_available = torch.cuda.is_available()
        self.model: Any | None = None
        self.sample_rate = 24000
        self.startup_error: str | None = None
        self.voices: dict[str, VoicePreset] = {}

    @property
    def ready(self) -> bool:
        return self.startup_error is None and self.model is not None

    def load(self) -> None:
        try:
            self.voices = self._load_voice_presets()
            if not self.ffmpeg_available:
                raise RuntimeError("ffmpeg not found in PATH")
            if not self.gpu_available:
                raise RuntimeError("CUDA GPU not available")
            if not self.source_dir.exists():
                raise RuntimeError(
                    f"CosyVoice source tree not found at {self.source_dir}. "
                    "Run scripts/cosyvoice3/bootstrap.sh first."
                )
            if not self.matcha_dir.exists():
                raise RuntimeError(
                    f"Matcha-TTS submodule not found at {self.matcha_dir}. "
                    "Re-run scripts/cosyvoice3/bootstrap.sh."
                )
            if not self.model_dir.exists():
                raise RuntimeError(
                    f"CosyVoice3 model not found at {self.model_dir}. "
                    "Run scripts/cosyvoice3/bootstrap.sh first."
                )

            sys.path.insert(0, str(self.source_dir))
            sys.path.insert(0, str(self.matcha_dir))
            from cosyvoice.cli.cosyvoice import AutoModel

            self.model = AutoModel(model_dir=str(self.model_dir))
            self.sample_rate = int(getattr(self.model, "sample_rate", 24000))
            self.startup_error = None
        except Exception as exc:
            self.model = None
            self.startup_error = str(exc)

    def _load_voice_presets(self) -> dict[str, VoicePreset]:
        if not self.manifest_path.exists():
            raise RuntimeError(
                f"Voice preset manifest not found at {self.manifest_path}. "
                "Run scripts/cosyvoice3/bootstrap.sh first."
            )

        payload = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        presets: dict[str, VoicePreset] = {}
        for item in payload.get("voices", []):
            voice_id = item["id"]
            prompt_wav = self.voices_dir / item["prompt_wav"]
            if not prompt_wav.exists():
                raise RuntimeError(f"Voice prompt audio not found: {prompt_wav}")
            presets[voice_id] = VoicePreset(
                voice_id=voice_id,
                mode=item["mode"],
                prompt_wav=prompt_wav,
                prompt_text=item.get("prompt_text") or None,
                description=item.get("description", ""),
                recommended_for=item.get("recommended_for", ""),
            )

        if "book_cn_a" not in presets or "book_cn_b" not in presets:
            raise RuntimeError("Voice preset manifest must define book_cn_a and book_cn_b")
        return presets

    def resolve_voice(self, requested_voice: str | None) -> VoicePreset:
        if requested_voice is None:
            return self.voices["book_cn_a"]

        normalized = requested_voice.strip()
        if not normalized:
            return self.voices["book_cn_a"]
        if normalized in self.voices:
            return self.voices[normalized]
        if normalized in OPENAI_VOICE_ALIASES:
            return self.voices["book_cn_a"]
        return self.voices["book_cn_a"]

    def parse_speed(self, instructions: str | None) -> float:
        if not instructions:
            return 1.0

        matches = SPEED_RE.findall(instructions)
        if not matches:
            return 1.0

        speed = float(matches[-1])
        return max(MIN_SPEED, min(MAX_SPEED, speed))

    def synthesize(
        self,
        text: str,
        requested_voice: str | None,
        instructions: str | None,
        response_format: str,
        requested_model: str | None,
    ) -> tuple[bytes, str, dict[str, str]]:
        if not self.ready:
            raise RuntimeError(self.startup_error or "CosyVoice3 model is not ready")

        response_format = response_format.lower()
        if response_format not in {"mp3", "wav"}:
            raise ValueError("Only mp3 and wav response_format values are supported")
        if not torch.cuda.is_available():
            raise RuntimeError("CUDA GPU not available")

        voice = self.resolve_voice(requested_voice)
        speed = self.parse_speed(instructions)
        model_output = self._run_inference(text=text, voice=voice, speed=speed)
        wav_bytes = self._collect_wav_bytes(model_output)

        if response_format == "wav":
            payload = wav_bytes
            media_type = "audio/wav"
        else:
            payload = self._encode_mp3(wav_bytes)
            media_type = "audio/mpeg"

        headers = {
            "X-CosyVoice-Requested-Voice": requested_voice or "",
            "X-CosyVoice-Resolved-Voice": voice.voice_id,
            "X-CosyVoice-Voice-Mode": voice.mode,
            "X-CosyVoice-Speed": f"{speed:.2f}",
            "X-CosyVoice-Requested-Model": requested_model or "",
        }
        return payload, media_type, headers

    def _run_inference(self, text: str, voice: VoicePreset, speed: float):
        assert self.model is not None
        if voice.mode == "zero_shot":
            prompt_text = voice.prompt_text or DEFAULT_ZERO_SHOT_PROMPT_TEXT
            return self.model.inference_zero_shot(
                text,
                prompt_text,
                str(voice.prompt_wav),
                stream=False,
                speed=speed,
            )
        if voice.mode == "cross_lingual":
            # CosyVoice3 requires <|endofprompt|> to appear in the text path for
            # cross-lingual inference, so we add the minimal upstream-compatible
            # prefix when callers use a plain OpenAI-style input string.
            if "<|endofprompt|>" not in text:
                text = f"{DEFAULT_CROSS_LINGUAL_PREFIX}{text}"
            return self.model.inference_cross_lingual(
                text,
                str(voice.prompt_wav),
                stream=False,
                speed=speed,
            )
        raise RuntimeError(f"Unsupported voice mode: {voice.mode}")

    def _collect_wav_bytes(self, model_output: Any) -> bytes:
        chunks: list[np.ndarray] = []
        for item in model_output:
            speech = item["tts_speech"]
            if hasattr(speech, "detach"):
                array = speech.detach().cpu().numpy()
            else:
                array = np.asarray(speech)
            array = np.squeeze(array).astype(np.float32)
            if array.ndim != 1:
                raise RuntimeError("Unexpected CosyVoice audio tensor shape")
            chunks.append(array)

        if not chunks:
            raise RuntimeError("CosyVoice returned no audio")

        audio = np.concatenate(chunks)
        audio = np.clip(audio, -1.0, 1.0)
        buffer = io.BytesIO()
        sf.write(buffer, audio, self.sample_rate, format="WAV", subtype="PCM_16")
        return buffer.getvalue()

    def _encode_mp3(self, wav_bytes: bytes) -> bytes:
        command = [
            "ffmpeg",
            "-nostdin",
            "-hide_banner",
            "-loglevel",
            "error",
            "-f",
            "wav",
            "-i",
            "pipe:0",
            "-f",
            "mp3",
            "-codec:a",
            "libmp3lame",
            "-b:a",
            "128k",
            "pipe:1",
        ]
        result = subprocess.run(
            command,
            input=wav_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if result.returncode != 0:
            message = result.stderr.decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"ffmpeg mp3 encoding failed: {message}")
        return result.stdout

    def health_payload(self) -> dict[str, Any]:
        gpu_name = torch.cuda.get_device_name(0) if torch.cuda.is_available() else None
        return {
            "status": "ok" if self.ready else "degraded",
            "ready": self.ready,
            "model_loaded": self.model is not None,
            "gpu_available": self.gpu_available,
            "gpu_name": gpu_name,
            "ffmpeg_available": self.ffmpeg_available,
            "concurrency_limit": 1,
            "root_dir": str(self.root_dir),
            "model_dir": str(self.model_dir),
            "sample_rate": self.sample_rate,
            "voices": [voice.to_public_dict() for voice in self.voices.values()],
            "error": self.startup_error,
        }

    def voices_payload(self) -> dict[str, Any]:
        return {
            "object": "list",
            "fallback_voice": "book_cn_a",
            "openai_compatible_aliases": sorted(OPENAI_VOICE_ALIASES),
            "data": [voice.to_public_dict() for voice in self.voices.values()],
        }


def create_app() -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        adapter = CosyVoiceOpenAiAdapter(RUNTIME_ROOT_DIR, RUNTIME_MODEL_DIR)
        await asyncio.to_thread(adapter.load)
        app.state.adapter = adapter
        app.state.semaphore = asyncio.Semaphore(1)
        yield

    app = FastAPI(lifespan=lifespan)

    @app.get("/healthz")
    async def healthz(request: Request):
        adapter: CosyVoiceOpenAiAdapter = request.app.state.adapter
        payload = adapter.health_payload()
        status_code = 200 if adapter.ready else 503
        return JSONResponse(payload, status_code=status_code)

    @app.get("/v1/audio/voices")
    async def list_voices(request: Request):
        adapter: CosyVoiceOpenAiAdapter = request.app.state.adapter
        return adapter.voices_payload()

    @app.post("/v1/audio/speech")
    async def audio_speech(
        body: SpeechRequest,
        request: Request,
        authorization: str | None = Header(default=None),
    ):
        del authorization

        adapter: CosyVoiceOpenAiAdapter = request.app.state.adapter
        response_format = (body.response_format or "mp3").lower()
        if response_format not in {"mp3", "wav"}:
            raise HTTPException(
                status_code=400,
                detail="Only mp3 and wav response_format values are supported",
            )

        async with request.app.state.semaphore:
            try:
                payload, media_type, headers = await asyncio.to_thread(
                    adapter.synthesize,
                    body.input,
                    body.voice,
                    body.instructions,
                    response_format,
                    body.model,
                )
            except ValueError as exc:
                raise HTTPException(status_code=400, detail=str(exc)) from exc
            except RuntimeError as exc:
                raise HTTPException(status_code=503, detail=str(exc)) from exc

        return Response(content=payload, media_type=media_type, headers=headers)

    return app


app = create_app()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="CosyVoice3 OpenAI-compatible TTS adapter for anx-reader"
    )
    parser.add_argument(
        "--root-dir",
        default=str(DEFAULT_ROOT_DIR),
        help="Runtime root directory. Default: %(default)s",
    )
    parser.add_argument(
        "--model-dir",
        default="",
        help="Override model directory. Default: <root-dir>/model/Fun-CosyVoice3-0.5B-2512",
    )
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=5050)
    return parser.parse_args()


def main() -> None:
    global RUNTIME_MODEL_DIR
    global RUNTIME_ROOT_DIR

    args = parse_args()
    RUNTIME_ROOT_DIR = Path(args.root_dir).expanduser()
    if args.model_dir:
        RUNTIME_MODEL_DIR = Path(args.model_dir).expanduser()
    else:
        RUNTIME_MODEL_DIR = RUNTIME_ROOT_DIR / "model" / DEFAULT_MODEL_DIR_NAME

    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
