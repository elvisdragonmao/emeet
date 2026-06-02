import unittest

from meeting_backend.transcription.mlx_whisper_provider import resolve_mlx_model_name


class MlxWhisperProviderTest(unittest.TestCase):
    def test_resolves_standard_whisper_aliases_to_mlx_repos(self) -> None:
        self.assertEqual(resolve_mlx_model_name("large-v3"), "mlx-community/whisper-large-v3-mlx")
        self.assertEqual(
            resolve_mlx_model_name("large-v3-turbo"),
            "mlx-community/whisper-large-v3-turbo",
        )

    def test_keeps_explicit_hugging_face_repo(self) -> None:
        self.assertEqual(
            resolve_mlx_model_name("custom/model"),
            "custom/model",
        )


if __name__ == "__main__":
    unittest.main()
