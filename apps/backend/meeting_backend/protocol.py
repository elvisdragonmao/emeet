import time
from dataclasses import dataclass
from typing import Any, Dict, Optional


@dataclass(frozen=True)
class SessionStart:
    session_id: str
    source: str
    sample_rate: int
    channels: int
    sample_width: int
    stt_provider: str = ""
    stt_model: str = ""
    stt_language: str = ""


def parse_session_start(payload: Dict[str, Any]) -> SessionStart:
    if payload.get("type") != "session.start":
        raise ValueError("first message must be session.start")

    session_id = str(payload.get("session_id") or "local-session")
    source = str(payload.get("source") or "microphone")
    sample_rate = int(payload.get("sample_rate") or 16_000)
    channels = int(payload.get("channels") or 1)
    sample_width = int(payload.get("sample_width") or 2)
    stt_provider = str(payload.get("stt_provider") or "")
    stt_model = str(payload.get("stt_model") or "")
    stt_language = str(payload.get("stt_language") or "")

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
        stt_provider=stt_provider,
        stt_model=stt_model,
        stt_language=stt_language,
    )


def speaker_hint_for_source(source: str) -> str:
    if source == "microphone":
        return "self"
    if source == "system":
        return "other"
    return "unknown"


def default_speaker_label(speaker_hint: str, source: str) -> str:
    if speaker_hint == "self":
        return "Self"
    if speaker_hint == "other":
        return "Other"
    return source.capitalize() if source else "Unknown"


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
    speaker_id: Optional[str] = None,
    speaker_label: Optional[str] = None,
    speaker_hint: Optional[str] = None,
) -> Dict[str, Any]:
    resolved_speaker_hint = speaker_hint or speaker_hint_for_source(session.source)
    return {
        "type": event_type,
        "segment_id": "seg_{}_{}".format(session.session_id, str(segment_index).zfill(4)),
        "source": session.source,
        "speaker_hint": resolved_speaker_hint,
        "speaker_id": speaker_id or resolved_speaker_hint or "unknown",
        "speaker_label": speaker_label or default_speaker_label(resolved_speaker_hint, session.source),
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


def pong_event(
    *,
    ping_id: Any,
    client_sent_at_ms: Any = None,
    server_sent_at_ms: Optional[int] = None,
) -> Dict[str, Any]:
    return {
        "type": "server.pong",
        "ping_id": str(ping_id or ""),
        "client_sent_at_ms": client_sent_at_ms,
        "server_sent_at_ms": int(time.time() * 1000) if server_sent_at_ms is None else server_sent_at_ms,
    }


def error_event(message: str) -> Dict[str, Any]:
    return {
        "type": "session.error",
        "message": message,
    }
