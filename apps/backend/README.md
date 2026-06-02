# Meeting Assistant Backend

Local-first transcription backend for the macOS meeting assistant prototype.

This service exposes a WebSocket endpoint that accepts small PCM16 audio packets and returns transcript events. The first provider is a mock streaming transcriber so the transport and event model can be verified without downloading a model. The provider boundary is intentionally small so `faster-whisper` can be added as the next step.

## Run Locally

```bash
cd apps/backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e .
uvicorn meeting_backend.main:app --reload --host 127.0.0.1 --port 8765
```

In another terminal:

```bash
cd apps/backend
source .venv/bin/activate
python scripts/send_test_audio.py
```

## WebSocket Protocol

Connect to:

```text
ws://127.0.0.1:8765/v1/transcribe/ws
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
