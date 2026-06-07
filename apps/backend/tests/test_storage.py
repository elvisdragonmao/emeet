import os
import sqlite3
import tempfile
import unittest

from meeting_backend.assistant.models import AssistantRequest, AssistantResult, AssistantTranscriptLine
from meeting_backend.protocol import SessionStart, transcript_event
from meeting_backend.storage import MeetingStorage, meeting_id_from_session_id, session_id_from_segment_id


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

    def test_extracts_meeting_id_from_source_session_id(self) -> None:
        self.assertEqual(meeting_id_from_session_id("mtg-123-microphone"), "mtg-123")
        self.assertEqual(meeting_id_from_session_id("mtg-123-system"), "mtg-123")
        self.assertEqual(meeting_id_from_session_id("local-session"), "local-session")

    def test_lists_history_records_for_saved_meetings(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            database_path = os.path.join(directory, "meeting.sqlite3")
            storage = MeetingStorage(database_path)
            session = SessionStart(
                session_id="mtg-demo-microphone",
                source="microphone",
                sample_rate=16000,
                channels=1,
                sample_width=2,
            )

            storage.record_session_start(session, provider="mlx-whisper", model="large-v3-turbo")
            storage.record_transcript_event(
                transcript_event(
                    event_type="transcript.final",
                    session=session,
                    segment_index=1,
                    start_ms=0,
                    end_ms=1200,
                    text="We need to confirm the demo checklist.",
                    revision=1,
                    is_final=True,
                    provider="mlx-whisper",
                )
            )
            storage.record_assistant_result(
                AssistantRequest(
                    action="meeting_notes",
                    meeting_id="mtg-demo",
                    provider="codex-cli",
                    model="gpt-5.5",
                    thinking="medium",
                    temperature=0.2,
                    max_tokens=700,
                    transcript=[],
                ),
                AssistantResult(
                    provider="codex-cli",
                    model="gpt-5.5",
                    thinking="medium",
                    latency_ms=20,
                    drafts=[],
                    notes=[{"title": "討論主題與內容", "detail": "Demo checklist needs confirmation."}],
                    actions=[{"title": "Confirm demo checklist", "owner": "Self", "state": "Draft"}],
                    raw_text="debug text is not exposed through history",
                ),
            )
            storage.record_assistant_result(
                AssistantRequest(
                    action="what_should_i_say",
                    meeting_id="mtg-demo",
                    provider="codex-cli",
                    model="gpt-5.5",
                    thinking="medium",
                    temperature=0.2,
                    max_tokens=700,
                    transcript=[],
                ),
                AssistantResult(
                    provider="codex-cli",
                    model="gpt-5.5",
                    thinking="medium",
                    latency_ms=15,
                    drafts=[
                        {
                            "title": "Clarify scope",
                            "detail": "Could we confirm which demo steps are required?",
                            "badge": "AI",
                            "icon_name": "quote.bubble",
                        }
                    ],
                    notes=[],
                    actions=[],
                    raw_text="debug text is not exposed through history",
                ),
            )
            storage.record_session_end("mtg-demo-microphone")

            meetings = storage.list_meetings()
            self.assertEqual(len(meetings), 1)
            self.assertEqual(meetings[0]["meeting_id"], "mtg-demo")
            self.assertEqual(meetings[0]["transcript_count"], 1)
            self.assertEqual(meetings[0]["assistant_response_count"], 1)
            self.assertEqual(meetings[0]["notes_count"], 1)
            self.assertEqual(meetings[0]["actions_count"], 1)

            record = storage.meeting_record("mtg-demo")
            self.assertIsNotNone(record)
            assert record is not None
            self.assertEqual(record["transcript"][0]["text"], "We need to confirm the demo checklist.")
            self.assertEqual(record["assistant_responses"][0]["action"], "what_should_i_say")
            self.assertEqual(record["assistant_responses"][0]["suggestions"][0]["title"], "Clarify scope")
            self.assertNotIn("raw_text", record["assistant_responses"][0])
            self.assertEqual(record["notes"][0]["title"], "討論主題與內容")
            self.assertEqual(record["actions"][0]["title"], "Confirm demo checklist")

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
