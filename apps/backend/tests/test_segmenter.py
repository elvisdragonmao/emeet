import unittest

from meeting_backend.audio import sine_pcm16
from meeting_backend.transcription.segmenter import SpeechSegmenterConfig, SpeechWindowSegmenter


def silence_pcm16(sample_rate: int, duration_seconds: float) -> bytes:
    return bytes(int(sample_rate * duration_seconds) * 2)


class SpeechWindowSegmenterTest(unittest.TestCase):
    def test_ignores_leading_silence(self) -> None:
        segmenter = SpeechWindowSegmenter(
            sample_rate=16000,
            channels=1,
            config=SpeechSegmenterConfig(min_segment_ms=300, silence_ms=300, max_segment_ms=2000),
        )

        self.assertEqual(segmenter.accept_audio(silence_pcm16(16000, 0.5)), [])
        self.assertEqual(segmenter.clock_ms, 500)

    def test_finalizes_after_trailing_silence(self) -> None:
        segmenter = SpeechWindowSegmenter(
            sample_rate=16000,
            channels=1,
            config=SpeechSegmenterConfig(min_segment_ms=300, silence_ms=300, max_segment_ms=2000),
        )

        self.assertEqual(segmenter.accept_audio(sine_pcm16(16000, 0.4)), [])
        segments = segmenter.accept_audio(silence_pcm16(16000, 0.3))

        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0].reason, "silence")
        self.assertEqual(segments[0].start_ms, 0)
        self.assertEqual(segments[0].end_ms, 700)

    def test_forces_split_when_speech_runs_too_long(self) -> None:
        segmenter = SpeechWindowSegmenter(
            sample_rate=16000,
            channels=1,
            config=SpeechSegmenterConfig(min_segment_ms=300, silence_ms=300, max_segment_ms=900),
        )

        self.assertEqual(segmenter.accept_audio(sine_pcm16(16000, 0.4)), [])
        self.assertEqual(segmenter.accept_audio(sine_pcm16(16000, 0.4)), [])
        segments = segmenter.accept_audio(sine_pcm16(16000, 0.2))

        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0].reason, "max_duration")
        self.assertEqual(segments[0].start_ms, 0)
        self.assertEqual(segments[0].end_ms, 1000)

    def test_flushes_remaining_speech_on_finish(self) -> None:
        segmenter = SpeechWindowSegmenter(
            sample_rate=16000,
            channels=1,
            config=SpeechSegmenterConfig(min_segment_ms=300, silence_ms=300, max_segment_ms=2000),
        )

        segmenter.accept_audio(sine_pcm16(16000, 0.2))
        segments = segmenter.finish()

        self.assertEqual(len(segments), 1)
        self.assertEqual(segments[0].reason, "session_end")


if __name__ == "__main__":
    unittest.main()
