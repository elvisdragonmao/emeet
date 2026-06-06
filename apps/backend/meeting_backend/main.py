from fastapi import FastAPI, WebSocket

from meeting_backend.assistant.api import router as assistant_router
from meeting_backend.config import get_settings
from meeting_backend.sessions import TranscriptionSession

app = FastAPI(title="emeet Backend", version="0.1.0")
app.include_router(assistant_router)


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
        "diarization_provider": settings.diarization_provider,
        "diarization_max_speakers": settings.diarization_max_speakers,
        "diarization_cluster_threshold": settings.diarization_cluster_threshold,
        "assistant_provider": settings.assistant_provider,
        "assistant_model": settings.assistant_model,
        "assistant_thinking": settings.assistant_thinking,
        "database_path": settings.database_path,
    }


@app.websocket("/v1/transcribe/ws")
async def transcribe_ws(websocket: WebSocket):
    settings = get_settings()
    session = TranscriptionSession(websocket, settings)
    await session.run()
