from fastapi import FastAPI, WebSocket

from meeting_backend.config import get_settings
from meeting_backend.sessions import TranscriptionSession

app = FastAPI(title="Meeting Assistant Backend", version="0.1.0")


@app.get("/health")
async def health():
    settings = get_settings()
    return {
        "status": "ok",
        "provider": settings.provider,
        "model": settings.whisper_model,
        "host": settings.host,
        "port": settings.port,
        "websocket_url": settings.websocket_url,
        "segment_min_ms": settings.segment_min_ms,
        "segment_silence_ms": settings.segment_silence_ms,
        "segment_max_ms": settings.segment_max_ms,
    }


@app.websocket("/v1/transcribe/ws")
async def transcribe_ws(websocket: WebSocket):
    settings = get_settings()
    session = TranscriptionSession(websocket, settings)
    await session.run()
