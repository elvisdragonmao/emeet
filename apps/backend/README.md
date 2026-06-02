# Meeting Assistant Backend

Local-first transcription backend for the macOS meeting assistant prototype.

This service exposes a WebSocket endpoint that accepts small PCM16 audio packets and returns transcript events. It has three providers:

- `faster-whisper`: self-hosted open-source STT provider for local/VPS use. This is the default.
- `mlx-whisper`: Apple Silicon optimized STT provider for local macOS development and demos.
- `mock`: verifies transport and event shape without downloading a model.

## Run Locally

```bash
cd apps/backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e ".[stt]"
./scripts/dev.sh
```

In another terminal:

```bash
cd apps/backend
source .venv/bin/activate
python scripts/send_test_audio.py
```

## Run With Faster Whisper

Install the optional STT dependencies:

```bash
cd apps/backend
source .venv/bin/activate
python -m pip install -e ".[stt]"
```

Start the backend with the model provider:

```bash
MEETING_BACKEND_PROVIDER=faster-whisper \
MEETING_BACKEND_MODEL=large-v3 \
MEETING_BACKEND_WHISPER_DEVICE=cpu \
MEETING_BACKEND_WHISPER_COMPUTE_TYPE=int8 \
./scripts/dev.sh
```

Use `mock` for a fast transport-only smoke test:

```bash
MEETING_BACKEND_PROVIDER=mock ./scripts/dev.sh
```

## Run With MLX Whisper

On Apple Silicon Macs, install the MLX optional dependency:

```bash
cd apps/backend
source .venv/bin/activate
python -m pip install -e ".[mlx-whisper]"
```

Start the backend with the MLX provider:

```bash
MEETING_BACKEND_PROVIDER=mlx-whisper \
MEETING_BACKEND_MODEL=large-v3 \
./scripts/dev.sh
```

The MLX provider maps standard Whisper aliases to MLX Hugging Face repos. For example:

```text
large-v3 -> mlx-community/whisper-large-v3-mlx
large-v3-turbo -> mlx-community/whisper-large-v3-turbo
```

You can also pass an explicit MLX model repo:

```bash
MEETING_BACKEND_PROVIDER=mlx-whisper \
MEETING_BACKEND_MODEL=mlx-community/whisper-large-v3-turbo \
./scripts/dev.sh
```

For a quick local speech test on macOS:

```bash
say -o /tmp/meeting-assistant-test.aiff "Hello, this is a local transcription test."
ffmpeg -y -i /tmp/meeting-assistant-test.aiff -ac 1 -ar 16000 -sample_fmt s16 /tmp/meeting-assistant-test.wav
python scripts/send_wav_audio.py /tmp/meeting-assistant-test.wav
```

## WebSocket Protocol

Connect to:

```text
ws://127.0.0.1:8765/v1/transcribe/ws
```

## Environment

The backend reads these environment variables:

```text
MEETING_BACKEND_PROVIDER=faster-whisper
MEETING_BACKEND_MODEL=large-v3
MEETING_BACKEND_HOST=127.0.0.1
MEETING_BACKEND_PORT=8765
MEETING_BACKEND_WS_URL=
MEETING_BACKEND_WHISPER_DEVICE=cpu
MEETING_BACKEND_WHISPER_COMPUTE_TYPE=int8
MEETING_BACKEND_WHISPER_LANGUAGE=
MEETING_BACKEND_PARTIAL_INTERVAL_MS=800
MEETING_BACKEND_FINAL_INTERVAL_MS=2400
MEETING_BACKEND_SEGMENT_MIN_MS=800
MEETING_BACKEND_SEGMENT_SILENCE_MS=700
MEETING_BACKEND_SEGMENT_MAX_MS=12000
MEETING_BACKEND_VAD_RMS_THRESHOLD=0.012
```

`MEETING_BACKEND_MODEL` is the preferred short alias. `MEETING_BACKEND_WHISPER_MODEL` is still supported for compatibility. The default model is `large-v3`, the largest standard Whisper model supported by faster-whisper. On macOS CPU this can be slow; use `large-v3-turbo`, `medium`, or `small` when latency matters more than maximum accuracy.

Whisper providers use speech windows instead of a fixed timer:

- `MEETING_BACKEND_SEGMENT_MIN_MS`: minimum speech window before silence can finalize it.
- `MEETING_BACKEND_SEGMENT_SILENCE_MS`: trailing silence needed to finalize a segment.
- `MEETING_BACKEND_SEGMENT_MAX_MS`: forced split for very long utterances.
- `MEETING_BACKEND_VAD_RMS_THRESHOLD`: simple RMS threshold for speech detection.

`MEETING_BACKEND_FINAL_INTERVAL_MS` is still accepted as a compatibility alias for `MEETING_BACKEND_SEGMENT_MAX_MS` when `MEETING_BACKEND_SEGMENT_MAX_MS` is not set.

For local macOS demo speed, prefer:

```bash
MEETING_BACKEND_PROVIDER=mlx-whisper
MEETING_BACKEND_MODEL=large-v3-turbo
```

For Linux VPS or NVIDIA GPU deployments, prefer:

```bash
MEETING_BACKEND_PROVIDER=faster-whisper
MEETING_BACKEND_WHISPER_DEVICE=cuda
MEETING_BACKEND_WHISPER_COMPUTE_TYPE=float16
```

The test clients also read:

```text
MEETING_BACKEND_CLIENT_TIMEOUT=10
```

First send a JSON text message:

```json
{
  "type": "session.start",
  "session_id": "local-demo",
  "source": "microphone",
  "sample_rate": 16000,
  "channels": 1,
  "sample_width": 2
}
```

Then send raw binary PCM16 little-endian audio frames. The client should send roughly 100 ms per frame. The server returns JSON events:

```json
{
  "type": "transcript.partial",
  "segment_id": "seg_local-demo_0001",
  "source": "microphone",
  "speaker_hint": "self",
  "start_ms": 0,
  "end_ms": 800,
  "text": "[mock microphone audio 0.8s rms=0.0707]",
  "revision": 1,
  "is_final": false,
  "confidence": 0.0,
  "provider": "mock"
}
```

## Tests

```bash
cd apps/backend
python -m unittest discover -s tests
```
