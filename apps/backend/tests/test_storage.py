import os
import sqlite3
import tempfile
import unittest

from meeting_backend.assistant.models import AssistantRequest, AssistantResult, AssistantTranscriptLine
from meeting_backend.protocol import SessionStart, transcript_event
from meeting_backend.storage import MeetingStorage, session_id_from_segment_id


class StorageTest(unittest.TestCase):
    def test_creates_schema_and_records_meeting_data(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database_path = os.path.join(directory, "meeting.sqlite3")
            storage = MeetingStorage(database_path)
            session = SessionStart(
                session_id="local-session",
                source="microphone",
                sample_rate=16000,
                channels=1,
                sample_width=2,
            )

            storage.record_session_start(session, provider="mock", model="mock-model")
            storage.record_transcript_event(
                transcript_event(
                    event_type="transcript.final",
                    session=session,
                    segment_index=1,
                    start_ms=0,
                    end_ms=900,
                    text="Hello from the meeting.",
                    revision=1,
                    is_final=True,
                    provider="mock",
                )
            )
            storage.record_assistant_result(
                AssistantRequest(
                    action="meeting_notes",
                    provider="mock",
                    model="mock-conversation",
                    thinking="medium",
                    temperature=0.2,
                    max_tokens=700,
                    transcript=[
                        AssistantTranscriptLine(
                            source="microphone",
                            source_label="Self",
                            speaker_hint="self",
                            start_ms=0,
                            end_ms=900,
                            text="Hello from the meeting.",
                            is_final=True,
                        )
                    ],
                ),
                AssistantResult(
                    provider="mock",
                    model="mock-conversation",
                    thinking="medium",
                    latency_ms=12,
                    drafts=[
                        {
                            "title": "Draft",
                            "detail": "Say hello.",
                            "badge": "AI",
                            "icon_name": "quote.bubble",
                        }
                    ],
                    notes=[{"title": "Note", "detail": "Greeting was discussed."}],
                    actions=[{"title": "Send recap", "owner": "Self", "state": "Draft"}],
                    raw_text="{}",
                ),
            )
            storage.record_session_end("local-session")

            with sqlite3.connect(database_path) as connection:
                self.assertEqual(count_rows(connection, "sessions"), 1)
                self.assertEqual(count_rows(connection, "transcript_segments"), 1)
                self.assertEqual(count_rows(connection, "assistant_suggestions"), 1)
                self.assertEqual(count_rows(connection, "notes"), 1)
                self.assertEqual(count_rows(connection, "actions"), 1)
                ended_at_ms = connection.execute(
                    "SELECT ended_at_ms FROM sessions WHERE session_id = ?",
                    ("local-session",),
                ).fetchone()[0]
                self.assertIsNotNone(ended_at_ms)

    def test_extracts_session_id_from_segment_id(self) -> None:
        self.assertEqual(session_id_from_segment_id("seg_macos-system-abcd_0001"), "macos-system-abcd")
        self.assertEqual(session_id_from_segment_id("bad"), "")


def count_rows(connection: sqlite3.Connection, table: str) -> int:
    return int(connection.execute("SELECT COUNT(*) FROM {}".format(table)).fetchone()[0])


if __name__ == "__main__":
    unittest.main()
