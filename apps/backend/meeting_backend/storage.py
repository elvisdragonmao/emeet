import os
import sqlite3
import time
from typing import Any, Dict, List, Optional

from meeting_backend.assistant.models import AssistantRequest, AssistantResult
from meeting_backend.meeting_records import meeting_record_markdown, normalize_meeting_title, title_from_transcript
from meeting_backend.protocol import SessionStart


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS meetings (
    meeting_id TEXT PRIMARY KEY,
    title TEXT NOT NULL DEFAULT '',
    title_is_manual INTEGER NOT NULL DEFAULT 0,
    started_at_ms INTEGER NOT NULL,
    ended_at_ms INTEGER,
    stt_provider TEXT NOT NULL DEFAULT '',
    stt_model TEXT NOT NULL DEFAULT '',
    assistant_provider TEXT NOT NULL DEFAULT '',
    assistant_model TEXT NOT NULL DEFAULT '',
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL
);

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
            ensure_column(
                connection,
                table="meetings",
                column="title_is_manual",
                definition="INTEGER NOT NULL DEFAULT 0",
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
            upsert_meeting(
                connection,
                meeting_id=meeting_id_from_session_id(session.session_id),
                started_at_ms=now,
                ended_at_ms=None,
                stt_provider=provider,
                stt_model=model,
                now=now,
                clear_ended=True,
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
            row = connection.execute(
                """
                SELECT session_id, started_at_ms, ended_at_ms, stt_provider, stt_model, updated_at_ms
                FROM sessions
                WHERE session_id = ?
                """,
                (session_id,),
            ).fetchone()
            if row is not None:
                upsert_meeting(
                    connection,
                    meeting_id=meeting_id_from_session_id(str(row[0])),
                    started_at_ms=int(row[1]),
                    ended_at_ms=None if row[2] is None else int(row[2]),
                    stt_provider=str(row[3]),
                    stt_model=str(row[4]),
                    now=int(row[5]),
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
            if event.get("is_final"):
                update_meeting_title_from_transcript(
                    connection,
                    meeting_id=meeting_id_from_session_id(session_id),
                    text=str(event.get("text") or ""),
                    now=now,
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
            if request.meeting_id:
                upsert_meeting(
                    connection,
                    meeting_id=request.meeting_id,
                    started_at_ms=now,
                    ended_at_ms=None,
                    assistant_provider=result.provider,
                    assistant_model=result.model,
                    now=now,
                )
            return run_id

    def list_meetings(self, *, limit: int = 50) -> List[Dict[str, Any]]:
        self.initialize()
        normalized_limit = max(1, min(limit, 200))
        with self._connect() as connection:
            self._backfill_meetings(connection)
            rows = connection.execute(
                """
                SELECT
                    meeting_id, title, title_is_manual, started_at_ms, ended_at_ms,
                    stt_provider, stt_model, assistant_provider, assistant_model,
                    created_at_ms, updated_at_ms
                FROM meetings
                ORDER BY updated_at_ms DESC
                LIMIT ?
                """,
                (normalized_limit,),
            ).fetchall()
            return [self._meeting_summary(connection, row) for row in rows]

    def meeting_record(self, meeting_id: str) -> Optional[Dict[str, Any]]:
        if not meeting_id:
            return None

        self.initialize()
        with self._connect() as connection:
            self._backfill_meetings(connection)
            row = connection.execute(
                """
                SELECT
                    meeting_id, title, title_is_manual, started_at_ms, ended_at_ms,
                    stt_provider, stt_model, assistant_provider, assistant_model,
                    created_at_ms, updated_at_ms
                FROM meetings
                WHERE meeting_id = ?
                """,
                (meeting_id,),
            ).fetchone()
            if row is None:
                return None

            return {
                "meeting": self._meeting_summary(connection, row),
                "transcript": self._meeting_transcript(connection, meeting_id),
                "assistant_responses": self._meeting_assistant_responses(connection, meeting_id),
                **self._latest_meeting_record(connection, meeting_id),
            }

    def latest_meeting_record(self, meeting_id: str) -> Dict[str, Any]:
        if not meeting_id:
            return {"notes": [], "actions": []}

        self.initialize()
        with self._connect() as connection:
            return self._latest_meeting_record(connection, meeting_id)

    def rename_meeting(self, meeting_id: str, title: str) -> Optional[Dict[str, Any]]:
        normalized_title = normalize_meeting_title(title)
        if not meeting_id or not normalized_title:
            return None

        self.initialize()
        now = current_time_ms()
        with self._connect() as connection:
            self._backfill_meetings(connection)
            row = connection.execute(
                "SELECT meeting_id FROM meetings WHERE meeting_id = ?",
                (meeting_id,),
            ).fetchone()
            if row is None:
                return None

            connection.execute(
                """
                UPDATE meetings
                SET title = ?, title_is_manual = 1, updated_at_ms = ?
                WHERE meeting_id = ?
                """,
                (normalized_title, now, meeting_id),
            )
            return self.meeting_summary(connection, meeting_id)

    def update_generated_meeting_title(self, meeting_id: str, title: str) -> Optional[Dict[str, Any]]:
        normalized_title = normalize_meeting_title(title)
        if not meeting_id or not normalized_title:
            return None

        self.initialize()
        now = current_time_ms()
        with self._connect() as connection:
            self._backfill_meetings(connection)
            row = connection.execute(
                "SELECT title_is_manual FROM meetings WHERE meeting_id = ?",
                (meeting_id,),
            ).fetchone()
            if row is None:
                return None
            if bool(row[0]):
                return self.meeting_summary(connection, meeting_id)

            connection.execute(
                """
                UPDATE meetings
                SET title = ?, title_is_manual = 0, updated_at_ms = ?
                WHERE meeting_id = ?
                """,
                (normalized_title, now, meeting_id),
            )
            return self.meeting_summary(connection, meeting_id)

    def meeting_summary(self, connection: sqlite3.Connection, meeting_id: str) -> Optional[Dict[str, Any]]:
        row = connection.execute(
            """
            SELECT
                meeting_id, title, title_is_manual, started_at_ms, ended_at_ms,
                stt_provider, stt_model, assistant_provider, assistant_model,
                created_at_ms, updated_at_ms
            FROM meetings
            WHERE meeting_id = ?
            """,
            (meeting_id,),
        ).fetchone()
        if row is None:
            return None
        return self._meeting_summary(connection, row)

    def meeting_markdown(self, meeting_id: str) -> Optional[str]:
        record = self.meeting_record(meeting_id)
        if record is None:
            return None
        return meeting_record_markdown(record)

    def _backfill_meetings(self, connection: sqlite3.Connection) -> None:
        for row in connection.execute(
            """
            SELECT session_id, started_at_ms, ended_at_ms, stt_provider, stt_model, updated_at_ms
            FROM sessions
            """
        ).fetchall():
            upsert_meeting(
                connection,
                meeting_id=meeting_id_from_session_id(str(row[0])),
                started_at_ms=int(row[1]),
                ended_at_ms=None if row[2] is None else int(row[2]),
                stt_provider=str(row[3]),
                stt_model=str(row[4]),
                now=int(row[5]),
            )

        for row in connection.execute(
            """
            SELECT meeting_id, provider, model, created_at_ms
            FROM assistant_runs
            WHERE meeting_id != ''
            """
        ).fetchall():
            upsert_meeting(
                connection,
                meeting_id=str(row[0]),
                started_at_ms=int(row[3]),
                ended_at_ms=None,
                assistant_provider=str(row[1]),
                assistant_model=str(row[2]),
                now=int(row[3]),
            )

    def _meeting_summary(self, connection: sqlite3.Connection, row: sqlite3.Row) -> Dict[str, Any]:
        meeting_id = str(row[0])
        title_is_manual = bool(row[2])
        started_at_ms = int(row[3])
        ended_at_ms = None if row[4] is None else int(row[4])
        updated_at_ms = int(row[10])
        effective_end_ms = ended_at_ms if ended_at_ms is not None else updated_at_ms
        notes_actions = self._latest_meeting_record(connection, meeting_id)
        title = str(row[1] or "") or first_transcript_title(connection, meeting_id) or "Untitled meeting"

        return {
            "meeting_id": meeting_id,
            "title": title,
            "title_is_manual": title_is_manual,
            "started_at_ms": started_at_ms,
            "ended_at_ms": ended_at_ms,
            "duration_ms": max(0, effective_end_ms - started_at_ms),
            "stt_provider": str(row[5] or ""),
            "stt_model": str(row[6] or ""),
            "assistant_provider": str(row[7] or ""),
            "assistant_model": str(row[8] or ""),
            "transcript_count": transcript_count(connection, meeting_id),
            "assistant_response_count": assistant_response_count(connection, meeting_id),
            "notes_count": len(notes_actions["notes"]),
            "actions_count": len(notes_actions["actions"]),
            "created_at_ms": int(row[9]),
            "updated_at_ms": updated_at_ms,
        }

    def _meeting_transcript(self, connection: sqlite3.Connection, meeting_id: str) -> List[Dict[str, Any]]:
        session_ids = session_ids_for_meeting(connection, meeting_id)
        if not session_ids:
            return []

        placeholders = ",".join("?" for _ in session_ids)
        return [
            {
                "segment_id": str(row[0]),
                "source": str(row[1]),
                "speaker_hint": str(row[2]),
                "speaker_id": str(row[3]),
                "speaker_label": str(row[4]),
                "start_ms": int(row[5]),
                "end_ms": int(row[6]),
                "text": str(row[7]),
                "revision": int(row[8]),
                "is_final": bool(row[9]),
                "confidence": float(row[10]),
                "provider": str(row[11]),
                "created_at_ms": int(row[12]),
            }
            for row in connection.execute(
                """
                SELECT
                    segment_id, source, speaker_hint, speaker_id, speaker_label,
                    start_ms, end_ms, text, revision, is_final, confidence, provider, created_at_ms
                FROM transcript_segments
                WHERE is_final = 1
                  AND session_id IN ({})
                ORDER BY created_at_ms, start_ms, segment_id
                """.format(placeholders),
                session_ids,
            ).fetchall()
        ]

    def _meeting_assistant_responses(
        self,
        connection: sqlite3.Connection,
        meeting_id: str,
    ) -> List[Dict[str, Any]]:
        responses: List[Dict[str, Any]] = []
        for row in connection.execute(
            """
            SELECT id, action, provider, model, thinking, latency_ms, created_at_ms
            FROM assistant_runs
            WHERE meeting_id = ?
              AND action IN ('what_should_i_say', 'follow_up_questions', 'chat')
            ORDER BY created_at_ms DESC, id DESC
            """,
            (meeting_id,),
        ).fetchall():
            run_id = int(row[0])
            responses.append(
                {
                    "id": run_id,
                    "action": str(row[1]),
                    "provider": str(row[2]),
                    "model": str(row[3]),
                    "thinking": str(row[4]),
                    "latency_ms": int(row[5]),
                    "created_at_ms": int(row[6]),
                    "suggestions": [
                        {
                            "id": int(suggestion[0]),
                            "title": str(suggestion[1]),
                            "detail": str(suggestion[2]),
                            "badge": str(suggestion[3]),
                            "icon_name": str(suggestion[4]),
                        }
                        for suggestion in connection.execute(
                            """
                            SELECT id, title, detail, badge, icon_name
                            FROM assistant_suggestions
                            WHERE run_id = ?
                            ORDER BY id
                            """,
                            (run_id,),
                        ).fetchall()
                    ],
                }
            )
        return responses

    def _latest_meeting_record(
        self,
        connection: sqlite3.Connection,
        meeting_id: str,
    ) -> Dict[str, List[Dict[str, str]]]:
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


def upsert_meeting(
    connection: sqlite3.Connection,
    *,
    meeting_id: str,
    started_at_ms: int,
    ended_at_ms: Optional[int],
    now: int,
    title: str = "",
    stt_provider: str = "",
    stt_model: str = "",
    assistant_provider: str = "",
    assistant_model: str = "",
    clear_ended: bool = False,
) -> None:
    if not meeting_id:
        return

    existing = connection.execute(
        """
        SELECT
            title, title_is_manual, started_at_ms, ended_at_ms, stt_provider, stt_model,
            assistant_provider, assistant_model, created_at_ms, updated_at_ms
        FROM meetings
        WHERE meeting_id = ?
        """,
        (meeting_id,),
    ).fetchone()
    if existing is None:
        connection.execute(
            """
            INSERT INTO meetings (
                meeting_id, title, title_is_manual, started_at_ms, ended_at_ms,
                stt_provider, stt_model, assistant_provider, assistant_model,
                created_at_ms, updated_at_ms
            )
            VALUES (?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                meeting_id,
                title,
                started_at_ms,
                ended_at_ms,
                stt_provider,
                stt_model,
                assistant_provider,
                assistant_model,
                now,
                now,
            ),
        )
        return

    existing_ended_at_ms = None if existing[3] is None else int(existing[3])
    next_ended_at_ms: Optional[int]
    if clear_ended:
        next_ended_at_ms = None
    elif ended_at_ms is None:
        next_ended_at_ms = existing_ended_at_ms
    elif existing_ended_at_ms is None:
        next_ended_at_ms = ended_at_ms
    else:
        next_ended_at_ms = max(existing_ended_at_ms, ended_at_ms)

    connection.execute(
        """
        UPDATE meetings
        SET
            title = ?,
            started_at_ms = ?,
            ended_at_ms = ?,
            stt_provider = ?,
            stt_model = ?,
            assistant_provider = ?,
            assistant_model = ?,
            updated_at_ms = ?
        WHERE meeting_id = ?
        """,
        (
            str(existing[0] or "") or title,
            min(int(existing[2]), started_at_ms),
            next_ended_at_ms,
            stt_provider or str(existing[4] or ""),
            stt_model or str(existing[5] or ""),
            assistant_provider or str(existing[6] or ""),
            assistant_model or str(existing[7] or ""),
            max(int(existing[9]), now),
            meeting_id,
        ),
    )


def update_meeting_title_from_transcript(
    connection: sqlite3.Connection,
    *,
    meeting_id: str,
    text: str,
    now: int,
) -> None:
    title = title_from_transcript(text)
    if not meeting_id or not title:
        return

    connection.execute(
        """
        UPDATE meetings
        SET
            title = CASE WHEN title = '' THEN ? ELSE title END,
            updated_at_ms = ?
        WHERE meeting_id = ?
          AND title_is_manual = 0
        """,
        (title, now, meeting_id),
    )


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


def meeting_id_from_session_id(session_id: str) -> str:
    normalized = session_id.strip()
    if not normalized:
        return ""

    for suffix in ("-microphone", "-system"):
        if normalized.endswith(suffix):
            meeting_id = normalized[: -len(suffix)]
            return meeting_id or normalized
    return normalized


def session_ids_for_meeting(connection: sqlite3.Connection, meeting_id: str) -> List[str]:
    return [
        str(row[0])
        for row in connection.execute("SELECT session_id FROM sessions").fetchall()
        if meeting_id_from_session_id(str(row[0])) == meeting_id
    ]


def transcript_count(connection: sqlite3.Connection, meeting_id: str) -> int:
    session_ids = session_ids_for_meeting(connection, meeting_id)
    if not session_ids:
        return 0
    placeholders = ",".join("?" for _ in session_ids)
    return int(
        connection.execute(
            """
            SELECT COUNT(*)
            FROM transcript_segments
            WHERE is_final = 1
              AND session_id IN ({})
            """.format(placeholders),
            session_ids,
        ).fetchone()[0]
    )


def assistant_response_count(connection: sqlite3.Connection, meeting_id: str) -> int:
    return int(
        connection.execute(
            """
            SELECT COUNT(*)
            FROM assistant_runs
            WHERE meeting_id = ?
              AND action IN ('what_should_i_say', 'follow_up_questions', 'chat')
            """,
            (meeting_id,),
        ).fetchone()[0]
    )


def first_transcript_title(connection: sqlite3.Connection, meeting_id: str) -> str:
    session_ids = session_ids_for_meeting(connection, meeting_id)
    if not session_ids:
        return ""
    placeholders = ",".join("?" for _ in session_ids)
    row = connection.execute(
        """
        SELECT text
        FROM transcript_segments
        WHERE is_final = 1
          AND session_id IN ({})
          AND text != ''
        ORDER BY created_at_ms, start_ms, segment_id
        LIMIT 1
        """.format(placeholders),
        session_ids,
    ).fetchone()
    if row is None:
        return ""
    return title_from_transcript(str(row[0]))
