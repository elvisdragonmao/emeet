import os
from dataclasses import dataclass

DEFAULT_PROVIDER = "faster-whisper"
DEFAULT_WHISPER_MODEL = "large-v3-turbo"
DEFAULT_ASSISTANT_PROVIDER = "codex-cli"
DEFAULT_ASSISTANT_MODEL = "gpt-5.5"
DEFAULT_ASSISTANT_THINKING = "medium"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
DEFAULT_WS_PATH = "/v1/transcribe/ws"
DEFAULT_DATABASE_PATH = "data/emeet.sqlite3"


@dataclass(frozen=True)
class Settings:
    provider: str = DEFAULT_PROVIDER
    host: str = DEFAULT_HOST
    port: int = DEFAULT_PORT
    default_sample_rate: int = 16_000
    default_channels: int = 1
    partial_interval_ms: int = 800
    final_interval_ms: int = 2_400
    segment_min_ms: int = 800
    segment_silence_ms: int = 700
    segment_max_ms: int = 8_000
    vad_rms_threshold: float = 0.012
    whisper_model: str = DEFAULT_WHISPER_MODEL
    whisper_device: str = "cpu"
    whisper_compute_type: str = "int8"
    whisper_language: str = ""
    websocket_url_override: str = ""
    assistant_provider: str = DEFAULT_ASSISTANT_PROVIDER
    assistant_model: str = DEFAULT_ASSISTANT_MODEL
    assistant_thinking: str = DEFAULT_ASSISTANT_THINKING
    assistant_ollama_base_url: str = "http://127.0.0.1:11434"
    assistant_openai_base_url: str = "http://127.0.0.1:1234/v1"
    assistant_api_key: str = ""
    assistant_timeout_ms: int = 20_000
    assistant_max_tokens: int = 700
    assistant_temperature: float = 0.2
    database_path: str = DEFAULT_DATABASE_PATH

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
        segment_min_ms=int(os.getenv("MEETING_BACKEND_SEGMENT_MIN_MS", "800")),
        segment_silence_ms=int(os.getenv("MEETING_BACKEND_SEGMENT_SILENCE_MS", "700")),
        segment_max_ms=int(
            env_first(
                "MEETING_BACKEND_SEGMENT_MAX_MS",
                "MEETING_BACKEND_FINAL_INTERVAL_MS",
                default="8000",
            )
        ),
        vad_rms_threshold=float(os.getenv("MEETING_BACKEND_VAD_RMS_THRESHOLD", "0.012")),
        whisper_model=env_first(
            "MEETING_BACKEND_MODEL",
            "MEETING_BACKEND_WHISPER_MODEL",
            default=DEFAULT_WHISPER_MODEL,
        ),
        whisper_device=os.getenv("MEETING_BACKEND_WHISPER_DEVICE", "cpu"),
        whisper_compute_type=os.getenv("MEETING_BACKEND_WHISPER_COMPUTE_TYPE", "int8"),
        whisper_language=os.getenv("MEETING_BACKEND_WHISPER_LANGUAGE", ""),
        websocket_url_override=env_first("MEETING_BACKEND_WS_URL"),
        assistant_provider=env_first(
            "MEETING_BACKEND_ASSISTANT_PROVIDER",
            default=DEFAULT_ASSISTANT_PROVIDER,
        ),
        assistant_model=env_first(
            "MEETING_BACKEND_ASSISTANT_MODEL",
            default=DEFAULT_ASSISTANT_MODEL,
        ),
        assistant_thinking=env_first(
            "MEETING_BACKEND_ASSISTANT_THINKING",
            default=DEFAULT_ASSISTANT_THINKING,
        ),
        assistant_ollama_base_url=env_first(
            "MEETING_BACKEND_ASSISTANT_OLLAMA_BASE_URL",
            default="http://127.0.0.1:11434",
        ),
        assistant_openai_base_url=env_first(
            "MEETING_BACKEND_ASSISTANT_OPENAI_BASE_URL",
            default="http://127.0.0.1:1234/v1",
        ),
        assistant_api_key=env_first(
            "MEETING_BACKEND_ASSISTANT_API_KEY",
            "OPENAI_API_KEY",
        ),
        assistant_timeout_ms=int(os.getenv("MEETING_BACKEND_ASSISTANT_TIMEOUT_MS", "20000")),
        assistant_max_tokens=int(os.getenv("MEETING_BACKEND_ASSISTANT_MAX_TOKENS", "700")),
        assistant_temperature=float(os.getenv("MEETING_BACKEND_ASSISTANT_TEMPERATURE", "0.2")),
        database_path=env_first("MEETING_BACKEND_DATABASE_PATH", default=DEFAULT_DATABASE_PATH),
    )


def env_first(*names: str, default: str = "") -> str:
    for name in names:
        value = os.getenv(name)
        if value:
            return value
    return default
