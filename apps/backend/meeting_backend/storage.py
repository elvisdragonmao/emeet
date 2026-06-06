import os
import sqlite3
import time
from typing import Any, Dict

from meeting_backend.assistant.models import AssistantRequest, AssistantResult
from meeting_backend.protocol import SessionStart


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS sessions (
    session_id TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    sample_rate INTEGER NOT NULL,
    channels INTEGER NOT NULL,
    sample_width INTEGER NOT NULL,
    stt_provider TEXT NOT NULL,
    stt_model TEXT NOT NULL,
    started_at_ms INTEGER NOT NULL,
    ended_at_ms INTEGER,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS transcript_segments (
    segment_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,
    source TEXT NOT NULL,
    speaker_hint TEXT NOT NULL,
    speaker_id TEXT NOT NULL DEFAULT '',
    speaker_label TEXT NOT NULL DEFAULT '',
    start_ms INTEGER NOT NULL,
    end_ms INTEGER NOT NULL,
    text TEXT NOT NULL,
    revision INTEGER NOT NULL,
    is_final INTEGER NOT NULL,
    confidence REAL NOT NULL,
    provider TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(session_id)
);

CREATE TABLE IF NOT EXISTS assistant_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    meeting_id TEXT NOT NULL DEFAULT '',
    action TEXT NOT NULL,
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    thinking TEXT NOT NULL,
    latency_ms INTEGER NOT NULL,
    raw_text TEXT,
    created_at_ms INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS assistant_suggestions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    detail TEXT NOT NULL,
    badge TEXT NOT NULL,
    icon_name TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    FOREIGN KEY (run_id) REFERENCES assistant_runs(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS notes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    detail TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    FOREIGN KEY (run_id) REFERENCES assistant_runs(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id INTEGER NOT NULL,
    title TEXT NOT NULL,
    owner TEXT NOT NULL,
    state TEXT NOT NULL,
    created_at_ms INTEGER NOT NULL,
    FOREIGN KEY (run_id) REFERENCES assistant_runs(id) ON DELETE CASCADE
);
"""


class MeetingStorage:
    def __init__(self, database_path: str) -> None:
        self.database_path = database_path

    def initialize(self) -> None:
        self._ensure_parent_directory()
        with self._connect() as connection:
            connection.executescript(SCHEMA_SQL)
            ensure_column(
                connection,
                table="transcript_segments",
                column="speaker_id",
                definition="TEXT NOT NULL DEFAULT ''",
            )
            ensure_column(
                connection,
                table="transcript_segments",
                column="speaker_label",
                definition="TEXT NOT NULL DEFAULT ''",
            )
            ensure_column(
                connection,
                table="assistant_runs",
                column="meeting_id",
                definition="TEXT NOT NULL DEFAULT ''",
            )

    def record_session_start(self, session: SessionStart, *, provider: str, model: str) -> None:
        self.initialize()
        now = current_time_ms()
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO sessions (
                    session_id, source, sample_rate, channels, sample_width,
                    stt_provider, stt_model, started_at_ms, ended_at_ms,
                    created_at_ms, updated_at_ms
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET
                    source = excluded.source,
                    sample_rate = excluded.sample_rate,
                    channels = excluded.channels,
                    sample_width = excluded.sample_width,
                    stt_provider = excluded.stt_provider,
                    stt_model = excluded.stt_model,
                    started_at_ms = excluded.started_at_ms,
                    ended_at_ms = NULL,
                    updated_at_ms = excluded.updated_at_ms
                """,
                (
                    session.session_id,
                    session.source,
                    session.sample_rate,
                    session.channels,
                    session.sample_width,
                    provider,
                    model,
                    now,
                    now,
                    now,
                ),
            )

    def record_session_end(self, session_id: str) -> None:
        self.initialize()
        now = current_time_ms()
        with self._connect() as connection:
            connection.execute(
                """
                UPDATE sessions
                SET ended_at_ms = ?, updated_at_ms = ?
                WHERE session_id = ?
                """,
                (now, now, session_id),
            )

    def record_transcript_event(self, event: Dict[str, Any]) -> None:
        if event.get("type") not in {"transcript.partial", "transcript.final"}:
            return

        segment_id = str(event.get("segment_id") or "")
        session_id = session_id_from_segment_id(segment_id)
        if not segment_id or not session_id:
            return

        self.initialize()
        now = current_time_ms()
        with self._connect() as connection:
            connection.execute(
                """
                INSERT INTO transcript_segments (
                    segment_id, session_id, source, speaker_hint, speaker_id, speaker_label, start_ms, end_ms,
                    text, revision, is_final, confidence, provider,
                    created_at_ms, updated_at_ms
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(segment_id) DO UPDATE SET
                    source = excluded.source,
                    speaker_hint = excluded.speaker_hint,
                    speaker_id = excluded.speaker_id,
                    speaker_label = excluded.speaker_label,
                    start_ms = excluded.start_ms,
                    end_ms = excluded.end_ms,
                    text = excluded.text,
                    revision = excluded.revision,
                    is_final = excluded.is_final,
                    confidence = excluded.confidence,
                    provider = excluded.provider,
                    updated_at_ms = excluded.updated_at_ms
                """,
                (
                    segment_id,
                    session_id,
                    str(event.get("source") or ""),
                    str(event.get("speaker_hint") or ""),
                    str(event.get("speaker_id") or ""),
                    str(event.get("speaker_label") or ""),
                    int(event.get("start_ms") or 0),
                    int(event.get("end_ms") or 0),
                    str(event.get("text") or ""),
                    int(event.get("revision") or 0),
                    1 if event.get("is_final") else 0,
                    float(event.get("confidence") or 0.0),
                    str(event.get("provider") or ""),
                    now,
                    now,
                ),
            )

    def record_assistant_result(self, request: AssistantRequest, result: AssistantResult) -> int:
        self.initialize()
        now = current_time_ms()
        with self._connect() as connection:
            cursor = connection.execute(
                """
                INSERT INTO assistant_runs (
                    meeting_id, action, provider, model, thinking, latency_ms, raw_text, created_at_ms
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    request.meeting_id,
                    request.action,
                    result.provider,
                    result.model,
                    result.thinking,
                    result.latency_ms,
                    result.raw_text,
                    now,
                ),
            )
            run_id = int(cursor.lastrowid)

            connection.executemany(
                """
                INSERT INTO assistant_suggestions (
                    run_id, title, detail, badge, icon_name, created_at_ms
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                [
                    (
                        run_id,
                        item["title"],
                        item["detail"],
                        item["badge"],
                        item["icon_name"],
                        now,
                    )
                    for item in result.drafts
                ],
            )
            connection.executemany(
                """
                INSERT INTO notes (run_id, title, detail, created_at_ms)
                VALUES (?, ?, ?, ?)
                """,
                [(run_id, item["title"], item["detail"], now) for item in result.notes],
            )
            connection.executemany(
                """
                INSERT INTO actions (run_id, title, owner, state, created_at_ms)
                VALUES (?, ?, ?, ?, ?)
                """,
                [
                    (
                        run_id,
                        item["title"],
                        item["owner"],
                        item["state"],
                        now,
                    )
                    for item in result.actions
                ],
            )
            return run_id

    def latest_meeting_record(self, meeting_id: str) -> Dict[str, Any]:
        if not meeting_id:
            return {"notes": [], "actions": []}

        self.initialize()
        with self._connect() as connection:
            row = connection.execute(
                """
                SELECT id
                FROM assistant_runs
                WHERE meeting_id = ?
                  AND action = 'meeting_notes'
                ORDER BY id DESC
                LIMIT 1
                """,
                (meeting_id,),
            ).fetchone()
            if row is None:
                return {"notes": [], "actions": []}

            run_id = int(row[0])
            notes = [
                {"title": str(note[0]), "detail": str(note[1])}
                for note in connection.execute(
                    """
                    SELECT title, detail
                    FROM notes
                    WHERE run_id = ?
                    ORDER BY id
                    """,
                    (run_id,),
                ).fetchall()
            ]
            actions = [
                {"title": str(action[0]), "owner": str(action[1]), "state": str(action[2])}
                for action in connection.execute(
                    """
                    SELECT title, owner, state
                    FROM actions
                    WHERE run_id = ?
                    ORDER BY id
                    """,
                    (run_id,),
                ).fetchall()
            ]
            return {"notes": notes, "actions": actions}

    def _connect(self) -> sqlite3.Connection:
        connection = sqlite3.connect(self.database_path)
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    def _ensure_parent_directory(self) -> None:
        if self.database_path == ":memory:":
            return

        directory = os.path.dirname(os.path.abspath(self.database_path))
        os.makedirs(directory, exist_ok=True)


def current_time_ms() -> int:
    return int(time.time() * 1000)


def ensure_column(connection: sqlite3.Connection, *, table: str, column: str, definition: str) -> None:
    columns = {
        str(row[1])
        for row in connection.execute("PRAGMA table_info({})".format(table)).fetchall()
    }
    if column in columns:
        return
    connection.execute("ALTER TABLE {} ADD COLUMN {} {}".format(table, column, definition))


def session_id_from_segment_id(segment_id: str) -> str:
    if not segment_id.startswith("seg_"):
        return ""

    body = segment_id[len("seg_") :]
    separator = body.rfind("_")
    if separator <= 0:
        return ""
    return body[:separator]
