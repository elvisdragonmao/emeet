import unittest

from meeting_backend.config import Settings
from meeting_backend.transcription.options import transcription_options


class TranscriptionOptionsTest(unittest.TestCase):
    def test_lists_breeze_asr_25_for_mlx_provider(self) -> None:
        options = transcription_options(Settings(provider="mlx-whisper", whisper_model="breeze-asr-25"))
        mlx = next(provider for provider in options["providers"] if provider["id"] == "mlx-whisper")

        self.assertEqual(options["defaults"]["provider"], "mlx-whisper")
        self.assertIn("zh", [language["id"] for language in options["languages"]])
        self.assertIn("breeze-asr-25", [model["id"] for model in mlx["models"]])


if __name__ == "__main__":
    unittest.main()
