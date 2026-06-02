import unittest

from meeting_backend.audio import sine_pcm16
from meeting_backend.protocol import SessionStart
from meeting_backend.transcription.segmented import SegmentedStreamingTranscriber, TranscriptionResult
from meeting_backend.transcription.segmenter import SpeechSegmenterConfig


class UnitSegmentedTranscriber(SegmentedStreamingTranscriber):
    provider_name = "unit"
    text = "segment"

    def status_message(self) -> str:
        return "unit ready"

    def transcribe_audio(self, audio: bytes) -> TranscriptionResult:
        return TranscriptionResult(text=self.text, confidence=0.5)


class SegmentedStreamingTranscriberTest(unittest.TestCase):
    def test_emits_status_and_final_transcript_events(self) -> None:
        transcriber = UnitSegmentedTranscriber(
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
        self.assertEqual(status[0]["provider"], "unit")

        self.assertEqual(transcriber.accept_audio(sine_pcm16(16000, 0.4)), [])
        events = transcriber.finish()

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["type"], "transcript.final")
        self.assertEqual(events[0]["provider"], "unit")
        self.assertEqual(events[0]["confidence"], 0.5)
        self.assertEqual(events[0]["segment_id"], "seg_unit_0001")

    def test_splits_transcript_text_into_sentence_events(self) -> None:
        transcriber = UnitSegmentedTranscriber(
            segmenter_config=SpeechSegmenterConfig(
                min_segment_ms=300,
                silence_ms=300,
                max_segment_ms=2000,
            )
        )
        transcriber.text = "First sentence. 第二句完成！"
        session = SessionStart(
            session_id="unit",
            source="microphone",
            sample_rate=16000,
            channels=1,
            sample_width=2,
        )

        transcriber.start(session)
        transcriber.accept_audio(sine_pcm16(16000, 0.4))
        events = transcriber.finish()

        self.assertEqual([event["text"] for event in events], ["First sentence.", "第二句完成！"])
        self.assertEqual(events[0]["segment_id"], "seg_unit_0001")
        self.assertEqual(events[1]["segment_id"], "seg_unit_0002")


if __name__ == "__main__":
    unittest.main()
