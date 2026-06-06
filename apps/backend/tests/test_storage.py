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

            storage.record_session_start(session, provider="faster-whisper", model="large-v3-turbo")
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
                    provider="faster-whisper",
                )
            )
            storage.record_assistant_result(
                AssistantRequest(
                    action="meeting_notes",
                    provider="ollama",
                    model="fast",
                    thinking="high",
                    temperature=0.2,
                    max_tokens=700,
                    transcript=[
                        AssistantTranscriptLine(
                            source="microphone",
                            source_label="Self",
                            speaker_hint="self",
                            speaker_id="self",
                            speaker_label="Self",
                            start_ms=0,
                            end_ms=900,
                            text="Hello from the meeting.",
                            is_final=True,
                        )
                    ],
                ),
                AssistantResult(
                    provider="ollama",
                    model="fast",
                    thinking="high",
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
                speaker = connection.execute(
                    "SELECT speaker_id, speaker_label FROM transcript_segments WHERE segment_id = ?",
                    ("seg_local-session_0001",),
                ).fetchone()
                self.assertEqual(speaker, ("self", "Self"))

    def test_extracts_session_id_from_segment_id(self) -> None:
        self.assertEqual(session_id_from_segment_id("seg_macos-system-abcd_0001"), "macos-system-abcd")
        self.assertEqual(session_id_from_segment_id("bad"), "")

    def test_adds_new_columns_to_existing_database(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database_path = os.path.join(directory, "meeting.sqlite3")
            with sqlite3.connect(database_path) as connection:
                connection.execute(
                    """
                    CREATE TABLE transcript_segments (
                        segment_id TEXT PRIMARY KEY,
                        session_id TEXT NOT NULL,
                        source TEXT NOT NULL,
                        speaker_hint TEXT NOT NULL,
                        start_ms INTEGER NOT NULL,
                        end_ms INTEGER NOT NULL,
                        text TEXT NOT NULL,
                        revision INTEGER NOT NULL,
                        is_final INTEGER NOT NULL,
                        confidence REAL NOT NULL,
                        provider TEXT NOT NULL,
                        created_at_ms INTEGER NOT NULL,
                        updated_at_ms INTEGER NOT NULL
                    )
                    """
                )
                connection.execute(
                    """
                    CREATE TABLE assistant_runs (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        action TEXT NOT NULL,
                        provider TEXT NOT NULL,
                        model TEXT NOT NULL,
                        thinking TEXT NOT NULL,
                        latency_ms INTEGER NOT NULL,
                        raw_text TEXT,
                        created_at_ms INTEGER NOT NULL
                    )
                    """
                )

            MeetingStorage(database_path).initialize()

            with sqlite3.connect(database_path) as connection:
                transcript_columns = table_columns(connection, "transcript_segments")
                assistant_run_columns = table_columns(connection, "assistant_runs")
                self.assertIn("speaker_id", transcript_columns)
                self.assertIn("speaker_label", transcript_columns)
                self.assertIn("meeting_id", assistant_run_columns)


def count_rows(connection: sqlite3.Connection, table: str) -> int:
    return int(connection.execute("SELECT COUNT(*) FROM {}".format(table)).fetchone()[0])


def table_columns(connection: sqlite3.Connection, table: str):
    return {row[1] for row in connection.execute("PRAGMA table_info({})".format(table)).fetchall()}


if __name__ == "__main__":
    unittest.main()
