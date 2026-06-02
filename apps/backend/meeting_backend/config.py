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


def get_settings() -> Settings:
    return Settings(
        provider=os.getenv("MEETING_BACKEND_PROVIDER", "mock"),
        host=os.getenv("MEETING_BACKEND_HOST", "127.0.0.1"),
        port=int(os.getenv("MEETING_BACKEND_PORT", "8765")),
        default_sample_rate=int(os.getenv("MEETING_BACKEND_SAMPLE_RATE", "16000")),
        default_channels=int(os.getenv("MEETING_BACKEND_CHANNELS", "1")),
        partial_interval_ms=int(os.getenv("MEETING_BACKEND_PARTIAL_INTERVAL_MS", "800")),
        final_interval_ms=int(os.getenv("MEETING_BACKEND_FINAL_INTERVAL_MS", "2400")),
    )
