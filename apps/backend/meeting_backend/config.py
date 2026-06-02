import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    provider: str = "mock"
    host: str = "127.0.0.1"
    port: int = 8765
    default_sample_rate: int = 16_000
    default_channels: int = 1
    partial_interval_ms: int = 800
    final_interval_ms: int = 2_400
    whisper_model: str = "tiny"
    whisper_device: str = "cpu"
    whisper_compute_type: str = "int8"
    whisper_language: str = ""


def get_settings() -> Settings:
    return Settings(
        provider=os.getenv("MEETING_BACKEND_PROVIDER", "mock"),
        host=os.getenv("MEETING_BACKEND_HOST", "127.0.0.1"),
        port=int(os.getenv("MEETING_BACKEND_PORT", "8765")),
        default_sample_rate=int(os.getenv("MEETING_BACKEND_SAMPLE_RATE", "16000")),
        default_channels=int(os.getenv("MEETING_BACKEND_CHANNELS", "1")),
        partial_interval_ms=int(os.getenv("MEETING_BACKEND_PARTIAL_INTERVAL_MS", "800")),
        final_interval_ms=int(os.getenv("MEETING_BACKEND_FINAL_INTERVAL_MS", "2400")),
        whisper_model=os.getenv("MEETING_BACKEND_WHISPER_MODEL", "tiny"),
        whisper_device=os.getenv("MEETING_BACKEND_WHISPER_DEVICE", "cpu"),
        whisper_compute_type=os.getenv("MEETING_BACKEND_WHISPER_COMPUTE_TYPE", "int8"),
        whisper_language=os.getenv("MEETING_BACKEND_WHISPER_LANGUAGE", ""),
    )
