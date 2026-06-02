import unittest
from contextlib import contextmanager
import os

from meeting_backend.config import get_settings


class ConfigTest(unittest.TestCase):
    def test_defaults_to_largest_whisper_model(self) -> None:
        with patched_environ({}):
            settings = get_settings()

        self.assertEqual(settings.provider, "faster-whisper")
        self.assertEqual(settings.whisper_model, "large-v3")
        self.assertEqual(settings.host, "127.0.0.1")
        self.assertEqual(settings.port, 8765)
        self.assertEqual(settings.websocket_url, "ws://127.0.0.1:8765/v1/transcribe/ws")
        self.assertEqual(settings.segment_min_ms, 800)
        self.assertEqual(settings.segment_silence_ms, 700)
        self.assertEqual(settings.segment_max_ms, 8000)
        self.assertEqual(settings.assistant_provider, "ollama")
        self.assertEqual(settings.assistant_model, "fast")
        self.assertEqual(settings.assistant_thinking, "medium")
        self.assertEqual(settings.database_path, "data/meeting-assistant.sqlite3")

    def test_supports_short_model_alias_and_port(self) -> None:
        with patched_environ(
            {
                "MEETING_BACKEND_MODEL": "medium",
                "MEETING_BACKEND_HOST": "0.0.0.0",
                "MEETING_BACKEND_PORT": "9000",
                "MEETING_BACKEND_ASSISTANT_PROVIDER": "ollama",
                "MEETING_BACKEND_ASSISTANT_MODEL": "llama3.2",
                "MEETING_BACKEND_ASSISTANT_THINKING": "high",
                "MEETING_BACKEND_DATABASE_PATH": "/tmp/meeting-test.sqlite3",
            },
        ):
            settings = get_settings()

        self.assertEqual(settings.whisper_model, "medium")
        self.assertEqual(settings.websocket_url, "ws://0.0.0.0:9000/v1/transcribe/ws")
        self.assertEqual(settings.assistant_provider, "ollama")
        self.assertEqual(settings.assistant_model, "llama3.2")
        self.assertEqual(settings.assistant_thinking, "high")
        self.assertEqual(settings.database_path, "/tmp/meeting-test.sqlite3")

    def test_supports_explicit_websocket_url(self) -> None:
        with patched_environ(
            {"MEETING_BACKEND_WS_URL": "ws://localhost:9999/custom"},
        ):
            settings = get_settings()

        self.assertEqual(settings.websocket_url, "ws://localhost:9999/custom")

    def test_supports_segmentation_environment(self) -> None:
        with patched_environ(
            {
                "MEETING_BACKEND_SEGMENT_MIN_MS": "600",
                "MEETING_BACKEND_SEGMENT_SILENCE_MS": "500",
                "MEETING_BACKEND_SEGMENT_MAX_MS": "9000",
                "MEETING_BACKEND_VAD_RMS_THRESHOLD": "0.02",
            },
        ):
            settings = get_settings()

        self.assertEqual(settings.segment_min_ms, 600)
        self.assertEqual(settings.segment_silence_ms, 500)
        self.assertEqual(settings.segment_max_ms, 9000)
        self.assertEqual(settings.vad_rms_threshold, 0.02)


@contextmanager
def patched_environ(values):
    previous = os.environ.copy()
    os.environ.clear()
    os.environ.update(values)
    try:
        yield
    finally:
        os.environ.clear()
        os.environ.update(previous)


if __name__ == "__main__":
    unittest.main()
