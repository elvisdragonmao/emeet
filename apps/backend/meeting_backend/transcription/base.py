from typing import Dict, List, Protocol

from meeting_backend.protocol import SessionStart


class StreamingTranscriber(Protocol):
    provider_name: str

    def start(self, session: SessionStart) -> List[Dict]:
        ...

    def accept_audio(self, audio: bytes) -> List[Dict]:
        ...

    def finish(self) -> List[Dict]:
        ...
