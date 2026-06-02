from dataclasses import dataclass
from typing import Any, Dict, Optional


@dataclass(frozen=True)
class SessionStart:
    session_id: str
    source: str
    sample_rate: int
    channels: int
    sample_width: int


def parse_session_start(payload: Dict[str, Any]) -> SessionStart:
    if payload.get("type") != "session.start":
        raise ValueError("first message must be session.start")

    session_id = str(payload.get("session_id") or "local-session")
    source = str(payload.get("source") or "microphone")
    sample_rate = int(payload.get("sample_rate") or 16_000)
    channels = int(payload.get("channels") or 1)
    sample_width = int(payload.get("sample_width") or 2)

    if sample_rate <= 0:
        raise ValueError("sample_rate must be positive")
    if channels != 1:
        raise ValueError("only mono audio is supported in this prototype")
    if sample_width != 2:
        raise ValueError("only PCM16 sample_width=2 is supported")

    return SessionStart(
        session_id=session_id,
        source=source,
        sample_rate=sample_rate,
        channels=channels,
        sample_width=sample_width,
    )


def speaker_hint_for_source(source: str) -> str:
    if source == "microphone":
        return "self"
    if source == "system":
        return "other"
    return "unknown"


def transcript_event(
    *,
    event_type: str,
    session: SessionStart,
    segment_index: int,
    start_ms: int,
    end_ms: int,
    text: str,
    revision: int,
    is_final: bool,
    provider: str,
    confidence: Optional[float] = None,
) -> Dict[str, Any]:
    return {
        "type": event_type,
        "segment_id": "seg_{}_{}".format(session.session_id, str(segment_index).zfill(4)),
        "source": session.source,
        "speaker_hint": speaker_hint_for_source(session.source),
        "start_ms": start_ms,
        "end_ms": end_ms,
        "text": text,
        "revision": revision,
        "is_final": is_final,
        "confidence": 0.0 if confidence is None else confidence,
        "provider": provider,
    }


def status_event(message: str, *, provider: str) -> Dict[str, Any]:
    return {
        "type": "session.status",
        "message": message,
        "provider": provider,
    }


def error_event(message: str) -> Dict[str, Any]:
    return {
        "type": "session.error",
        "message": message,
    }
