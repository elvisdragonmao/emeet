from dataclasses import dataclass, field
from threading import Lock
from typing import Dict, List, Optional

from meeting_backend.google_docs_service import DocumentSnapshot


@dataclass(frozen=True)
class GoogleDocMeetingConnection:
    meeting_id: str
    snapshot: DocumentSnapshot
    document_briefing: str = ""
    briefing_notes: List[Dict[str, str]] = field(default_factory=list)
    briefing_actions: List[Dict[str, str]] = field(default_factory=list)
    briefing_error: str = ""


class GoogleDocConnectionStore:
    def __init__(self) -> None:
        self._lock = Lock()
        self._connections: Dict[str, GoogleDocMeetingConnection] = {}

    def set(self, connection: GoogleDocMeetingConnection) -> None:
        with self._lock:
            self._connections[connection_key(connection.meeting_id)] = connection

    def get(self, meeting_id: str) -> Optional[GoogleDocMeetingConnection]:
        with self._lock:
            return self._connections.get(connection_key(meeting_id))

    def update_snapshot(self, meeting_id: str, snapshot: DocumentSnapshot) -> GoogleDocMeetingConnection:
        key = connection_key(meeting_id)
        with self._lock:
            existing = self._connections.get(key)
            connection = GoogleDocMeetingConnection(
                meeting_id=meeting_id,
                snapshot=snapshot,
                document_briefing=existing.document_briefing if existing else "",
                briefing_notes=existing.briefing_notes if existing else [],
                briefing_actions=existing.briefing_actions if existing else [],
                briefing_error=existing.briefing_error if existing else "",
            )
            self._connections[key] = connection
            return connection


def connection_key(meeting_id: str) -> str:
    return meeting_id.strip() or "default"


GOOGLE_DOC_CONNECTIONS = GoogleDocConnectionStore()
