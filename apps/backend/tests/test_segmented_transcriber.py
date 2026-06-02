import unittest

from meeting_backend.audio import sine_pcm16
from meeting_backend.protocol import SessionStart
from meeting_backend.transcription.segmented import SegmentedStreamingTranscriber, TranscriptionResult
from meeting_backend.transcription.segmenter import SpeechSegmenterConfig


class FakeSegmentedTranscriber(SegmentedStreamingTranscriber):
    provider_name = "fake"

    def status_message(self) -> str:
        return "fake ready"

    def transcribe_audio(self, audio: bytes) -> TranscriptionResult:
        return TranscriptionResult(text="segment {}".format(len(audio)), confidence=0.5)


class SegmentedStreamingTranscriberTest(unittest.TestCase):
    def test_emits_status_and_final_transcript_events(self) -> None:
        transcriber = FakeSegmentedTranscriber(
            segmenter_config=SpeechSegmenterConfig(
                min_segment_ms=300,
                silence_ms=300,
                max_segment_ms=2000,
            )
        )
        session = SessionStart(
            session_id="unit",
            source="microphone",
            sample_rate=16000,
            channels=1,
            sample_width=2,
        )

        status = transcriber.start(session)
        self.assertEqual(status[0]["type"], "session.status")
        self.assertEqual(status[0]["provider"], "fake")

        self.assertEqual(transcriber.accept_audio(sine_pcm16(16000, 0.4)), [])
        events = transcriber.finish()

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["type"], "transcript.final")
        self.assertEqual(events[0]["provider"], "fake")
        self.assertEqual(events[0]["confidence"], 0.5)
        self.assertEqual(events[0]["segment_id"], "seg_unit_0001")


if __name__ == "__main__":
    unittest.main()
