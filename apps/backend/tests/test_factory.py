import unittest
from unittest.mock import patch

from meeting_backend.config import Settings
from meeting_backend.transcription import create_transcriber


class FactoryTest(unittest.TestCase):
    def test_creates_mock_provider(self) -> None:
        transcriber = create_transcriber(Settings(provider="mock"))
        self.assertEqual(transcriber.provider_name, "mock")

    def test_creates_mlx_provider(self) -> None:
        with patch("meeting_backend.transcription.factory.MlxWhisperStreamingTranscriber") as transcriber:
            create_transcriber(Settings(provider="mlx-whisper"))

        transcriber.assert_called_once()

    def test_rejects_unknown_provider(self) -> None:
        with self.assertRaises(ValueError):
            create_transcriber(Settings(provider="missing"))


if __name__ == "__main__":
    unittest.main()
