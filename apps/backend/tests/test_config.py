import unittest
from unittest.mock import patch

from meeting_backend.config import get_settings


class ConfigTest(unittest.TestCase):
    def test_defaults_to_largest_whisper_model(self) -> None:
        with patch.dict("os.environ", {}, clear=True):
            settings = get_settings()

        self.assertEqual(settings.provider, "faster-whisper")
        self.assertEqual(settings.whisper_model, "large-v3")
        self.assertEqual(settings.host, "127.0.0.1")
        self.assertEqual(settings.port, 8765)
        self.assertEqual(settings.websocket_url, "ws://127.0.0.1:8765/v1/transcribe/ws")

    def test_supports_short_model_alias_and_port(self) -> None:
        with patch.dict(
            "os.environ",
            {
                "MEETING_BACKEND_MODEL": "medium",
                "MEETING_BACKEND_HOST": "0.0.0.0",
                "MEETING_BACKEND_PORT": "9000",
            },
            clear=True,
        ):
            settings = get_settings()

        self.assertEqual(settings.whisper_model, "medium")
        self.assertEqual(settings.websocket_url, "ws://0.0.0.0:9000/v1/transcribe/ws")

    def test_supports_explicit_websocket_url(self) -> None:
        with patch.dict(
            "os.environ",
            {"MEETING_BACKEND_WS_URL": "ws://localhost:9999/custom"},
            clear=True,
        ):
            settings = get_settings()

        self.assertEqual(settings.websocket_url, "ws://localhost:9999/custom")


if __name__ == "__main__":
    unittest.main()
