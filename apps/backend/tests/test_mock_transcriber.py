import unittest

from meeting_backend.audio import sine_pcm16
from meeting_backend.protocol import SessionStart
from meeting_backend.transcription.mock import MockStreamingTranscriber


class MockStreamingTranscriberTest(unittest.TestCase):
    def test_emits_partial_and_final_events(self) -> None:
        transcriber = MockStreamingTranscriber(partial_interval_ms=100, final_interval_ms=300)
        session = SessionStart(
            session_id="unit",
            source="microphone",
            sample_rate=16000,
            channels=1,
            sample_width=2,
        )

        events = transcriber.start(session)
        self.assertEqual(events[0]["type"], "session.status")

        audio = sine_pcm16(sample_rate=16000, duration_seconds=0.1)
        emitted = []
        for _ in range(3):
            emitted.extend(transcriber.accept_audio(audio))

        event_types = [event["type"] for event in emitted]
        self.assertIn("transcript.partial", event_types)
        self.assertIn("transcript.final", event_types)


if __name__ == "__main__":
    unittest.main()
