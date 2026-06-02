import os
from dataclasses import dataclass

DEFAULT_PROVIDER = "faster-whisper"
DEFAULT_WHISPER_MODEL = "large-v3"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
DEFAULT_WS_PATH = "/v1/transcribe/ws"


@dataclass(frozen=True)
class Settings:
    provider: str = DEFAULT_PROVIDER
    host: str = DEFAULT_HOST
    port: int = DEFAULT_PORT
    default_sample_rate: int = 16_000
    default_channels: int = 1
    partial_interval_ms: int = 800
    final_interval_ms: int = 2_400
    whisper_model: str = DEFAULT_WHISPER_MODEL
    whisper_device: str = "cpu"
    whisper_compute_type: str = "int8"
    whisper_language: str = ""
    websocket_url_override: str = ""

    @property
    def websocket_url(self) -> str:
        if self.websocket_url_override:
            return self.websocket_url_override

        return "ws://{}:{}{}".format(self.host, self.port, DEFAULT_WS_PATH)


def get_settings() -> Settings:
    return Settings(
        provider=env_first("MEETING_BACKEND_PROVIDER", default=DEFAULT_PROVIDER),
        host=env_first("MEETING_BACKEND_HOST", default=DEFAULT_HOST),
        port=int(env_first("MEETING_BACKEND_PORT", default=str(DEFAULT_PORT))),
        default_sample_rate=int(os.getenv("MEETING_BACKEND_SAMPLE_RATE", "16000")),
        default_channels=int(os.getenv("MEETING_BACKEND_CHANNELS", "1")),
        partial_interval_ms=int(os.getenv("MEETING_BACKEND_PARTIAL_INTERVAL_MS", "800")),
        final_interval_ms=int(os.getenv("MEETING_BACKEND_FINAL_INTERVAL_MS", "2400")),
        whisper_model=env_first(
            "MEETING_BACKEND_MODEL",
            "MEETING_BACKEND_WHISPER_MODEL",
            default=DEFAULT_WHISPER_MODEL,
        ),
        whisper_device=os.getenv("MEETING_BACKEND_WHISPER_DEVICE", "cpu"),
        whisper_compute_type=os.getenv("MEETING_BACKEND_WHISPER_COMPUTE_TYPE", "int8"),
        whisper_language=os.getenv("MEETING_BACKEND_WHISPER_LANGUAGE", ""),
        websocket_url_override=env_first("MEETING_BACKEND_WS_URL"),
    )


def env_first(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    return default
