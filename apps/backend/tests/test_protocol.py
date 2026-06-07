import unittest

from meeting_backend.protocol import SessionStart, parse_session_start, pong_event, transcript_event


class ProtocolTest(unittest.TestCase):
    def test_pong_event_echoes_client_ping_metadata(self) -> None:
        event = pong_event(
            ping_id="ping-1",
            client_sent_at_ms=123,
            server_sent_at_ms=456,
        )

        self.assertEqual(event["type"], "server.pong")
        self.assertEqual(event["ping_id"], "ping-1")
        self.assertEqual(event["client_sent_at_ms"], 123)
        self.assertEqual(event["server_sent_at_ms"], 456)

    def test_transcript_event_includes_speaker_label_contract(self) -> None:
        session = SessionStart(
            session_id="unit-system",
            source="system",
            sample_rate=16000,
            channels=1,
            sample_width=2,
        )

        event = transcript_event(
            event_type="transcript.final",
            session=session,
            segment_index=1,
            start_ms=0,
            end_ms=1000,
            text="Hello.",
            revision=1,
            is_final=True,
            provider="unit",
            speaker_hint="other",
            speaker_id="speaker_1",
            speaker_label="Speaker 1",
        )

        self.assertEqual(event["speaker_hint"], "other")
        self.assertEqual(event["speaker_id"], "speaker_1")
        self.assertEqual(event["speaker_label"], "Speaker 1")

    def test_parse_session_start_accepts_stt_overrides(self) -> None:
        session = parse_session_start(
            {
                "type": "session.start",
                "session_id": "mtg-demo-microphone",
                "source": "microphone",
                "sample_rate": 16000,
                "channels": 1,
                "sample_width": 2,
                "stt_provider": "mlx-whisper",
                "stt_model": "breeze-asr-25",
                "stt_language": "zh",
            }
        )

        self.assertEqual(session.stt_provider, "mlx-whisper")
        self.assertEqual(session.stt_model, "breeze-asr-25")
        self.assertEqual(session.stt_language, "zh")


if __name__ == "__main__":
    unittest.main()
