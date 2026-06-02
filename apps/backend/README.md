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
MEETING_BACKEND_ASSISTANT_PROVIDER=mock
MEETING_BACKEND_ASSISTANT_MODEL=mock-conversation
MEETING_BACKEND_ASSISTANT_THINKING=medium
MEETING_BACKEND_ASSISTANT_OLLAMA_BASE_URL=http://127.0.0.1:11434
MEETING_BACKEND_ASSISTANT_OPENAI_BASE_URL=http://127.0.0.1:1234/v1
MEETING_BACKEND_ASSISTANT_API_KEY=
MEETING_BACKEND_ASSISTANT_TIMEOUT_MS=20000
MEETING_BACKEND_ASSISTANT_MAX_TOKENS=700
MEETING_BACKEND_ASSISTANT_TEMPERATURE=0.2
MEETING_BACKEND_PARTIAL_INTERVAL_MS=800
MEETING_BACKEND_FINAL_INTERVAL_MS=2400
MEETING_BACKEND_SEGMENT_MIN_MS=800
MEETING_BACKEND_SEGMENT_SILENCE_MS=700
MEETING_BACKEND_SEGMENT_MAX_MS=12000
MEETING_BACKEND_VAD_RMS_THRESHOLD=0.012
MEETING_BACKEND_DATABASE_PATH=data/meeting-assistant.sqlite3
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

For assistant responses, the macOS app can override provider, model, and thinking per request. Backend defaults are set through environment variables:

```bash
MEETING_BACKEND_ASSISTANT_PROVIDER=ollama \
MEETING_BACKEND_ASSISTANT_MODEL=llama3.2 \
MEETING_BACKEND_ASSISTANT_THINKING=medium \
./scripts/dev.sh
```

For LM Studio, vLLM, llama.cpp, or an OpenAI-compatible endpoint:

```bash
MEETING_BACKEND_ASSISTANT_PROVIDER=openai-compatible \
MEETING_BACKEND_ASSISTANT_OPENAI_BASE_URL=http://127.0.0.1:1234/v1 \
MEETING_BACKEND_ASSISTANT_MODEL=local-model \
./scripts/dev.sh
```

For the OpenAI API, use the same OpenAI-compatible adapter and keep the key in the backend environment:

```bash
MEETING_BACKEND_ASSISTANT_PROVIDER=openai-compatible \
MEETING_BACKEND_ASSISTANT_OPENAI_BASE_URL=https://api.openai.com/v1 \
MEETING_BACKEND_ASSISTANT_MODEL=gpt-5.4-mini \
MEETING_BACKEND_ASSISTANT_THINKING=low \
OPENAI_API_KEY=... \
./scripts/dev.sh
```

CLI providers are also listed when installed:

```text
codex-cli
github-copilot-cli
```

These run official local CLIs only. The backend does not read provider config files, keychains, browser sessions, or hidden credentials.

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

Clients can also measure backend websocket round-trip time with an app-level heartbeat:

```json
{
  "type": "client.ping",
  "ping_id": "ping-1",
  "client_sent_at_ms": 1717315200000
}
```

The server replies on the same websocket:

```json
{
  "type": "server.pong",
  "ping_id": "ping-1",
  "client_sent_at_ms": 1717315200000,
  "server_sent_at_ms": 1717315200042
}
```

Assistant provider discovery:

```http
GET /v1/assistant/providers
```

Assistant response generation:

```json
{
  "action": "what_should_i_say",
  "provider": "ollama",
  "model": "llama3.2",
  "thinking": "medium",
  "transcript": [
    {
      "source": "system",
      "source_label": "Other",
      "speaker_hint": "other",
      "start_ms": 0,
      "end_ms": 1800,
      "text": "Can we finish the demo by Friday?",
      "is_final": true
    }
  ]
}
```

## Assistant Prompts and Schema

Assistant prompts are split by action in `meeting_backend/assistant/prompts.py`:

- `what_should_i_say`
- `follow_up_questions`
- `meeting_notes`
- `chat`

Provider output is parsed as JSON and validated by `meeting_backend/assistant/schema.py`. The validated response contract is:

```json
{
  "drafts": [{ "title": "...", "detail": "...", "badge": "...", "icon_name": "..." }],
  "notes": [{ "title": "...", "detail": "..." }],
  "actions": [{ "title": "...", "owner": "...", "state": "..." }]
}
```

If a provider returns incomplete JSON, the backend normalizes what it can, then validates the normalized payload before sending it to the macOS app.

## SQLite Storage

The backend creates a SQLite database at `MEETING_BACKEND_DATABASE_PATH`. It stores:

- `sessions`: STT websocket sessions and source metadata.
- `transcript_segments`: partial/final transcript events.
- `assistant_runs`: assistant request metadata.
- `assistant_suggestions`: reply drafts and follow-up suggestions.
- `notes`: meeting notes generated by the assistant.
- `actions`: next actions generated by the assistant.

The current storage layer is append-first and local. Query/export APIs can be added on top of these tables later.

## Tests

```bash
cd apps/backend
python -m unittest discover -s tests
```
