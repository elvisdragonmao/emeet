# Meeting Assistant Backend

Local-first transcription backend for the macOS meeting assistant prototype.

This service exposes a WebSocket endpoint that accepts small PCM16 audio packets and returns transcript events. It has two providers:

- `mock`: verifies transport and event shape without downloading a model.
- `faster-whisper`: self-hosted open-source STT provider for local/VPS use.

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
MEETING_BACKEND_WHISPER_MODEL=tiny \
MEETING_BACKEND_WHISPER_DEVICE=cpu \
MEETING_BACKEND_WHISPER_COMPUTE_TYPE=int8 \
uvicorn meeting_backend.main:app --host 127.0.0.1 --port 8765
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
