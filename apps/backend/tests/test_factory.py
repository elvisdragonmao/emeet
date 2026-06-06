import unittest

from meeting_backend.config import Settings
from meeting_backend.transcription import factory


class RecordingTranscriber:
    provider_name = "recording"
    calls = []

    def __init__(self, **kwargs) -> None:
        self.kwargs = kwargs
        self.__class__.calls.append(kwargs)


class FactoryTest(unittest.TestCase):
    def test_creates_faster_whisper_provider(self) -> None:
        original = factory.FasterWhisperStreamingTranscriber
        RecordingTranscriber.calls = []
        factory.FasterWhisperStreamingTranscriber = RecordingTranscriber
        try:
            transcriber = factory.create_transcriber(Settings(provider="faster-whisper"))
        finally:
            factory.FasterWhisperStreamingTranscriber = original

        self.assertEqual(transcriber.provider_name, "recording")
        self.assertEqual(RecordingTranscriber.calls[0]["model_name"], "large-v3-turbo")
        self.assertEqual(RecordingTranscriber.calls[0]["diarization_provider"], "local-clustering")

    def test_creates_mlx_provider(self) -> None:
        original = factory.MlxWhisperStreamingTranscriber
        RecordingTranscriber.calls = []
        factory.MlxWhisperStreamingTranscriber = RecordingTranscriber
        try:
            transcriber = factory.create_transcriber(Settings(provider="mlx-whisper"))
        finally:
            factory.MlxWhisperStreamingTranscriber = original

        self.assertEqual(transcriber.provider_name, "recording")
        self.assertEqual(RecordingTranscriber.calls[0]["model_name"], "large-v3-turbo")

    def test_rejects_unknown_provider(self) -> None:
        with self.assertRaises(ValueError):
            factory.create_transcriber(Settings(provider="missing"))


if __name__ == "__main__":
    unittest.main()
