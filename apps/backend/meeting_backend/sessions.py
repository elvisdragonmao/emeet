import json
from typing import Any, Optional

from fastapi import WebSocket
from starlette.websockets import WebSocketDisconnect

from meeting_backend.config import Settings, with_transcription_overrides
from meeting_backend.protocol import error_event, parse_session_start, pong_event
from meeting_backend.storage import MeetingStorage
from meeting_backend.transcription import create_transcriber
from meeting_backend.transcription.base import StreamingTranscriber


class TranscriptionSession:
    def __init__(self, websocket: WebSocket, settings: Settings) -> None:
        self.websocket = websocket
        self.settings = settings
        self.transcriber: Optional[StreamingTranscriber] = None
        self.session_id: Optional[str] = None
        self.storage = MeetingStorage(settings.database_path)

    async def run(self) -> None:
        await self.websocket.accept()

        try:
            first_message = await self.websocket.receive_text()
            session = parse_session_start(json.loads(first_message))
            self.session_id = session.session_id
            session_settings = with_transcription_overrides(
                self.settings,
                provider=session.stt_provider,
                model=session.stt_model,
                language=session.stt_language,
            )
            self.transcriber = create_transcriber(session_settings)
            self.storage.record_session_start(
                session,
                provider=session_settings.provider,
                model=session_settings.whisper_model,
            )
            await self._send_many(self.transcriber.start(session))

            while True:
                message = await self.websocket.receive()
                if message["type"] == "websocket.disconnect":
                    break

                if message.get("bytes") is not None:
                    if self.transcriber is None:
                        await self._safe_send(error_event("session has not started"))
                        continue
                    events = self.transcriber.accept_audio(message["bytes"])
                    await self._send_many(events)
                    continue

                if message.get("text") is not None:
                    await self._handle_text(message["text"])
                    continue
        except WebSocketDisconnect:
            pass
        except Exception as error:
            await self._safe_send(error_event(str(error)))
        finally:
            if self.transcriber is not None:
                await self._send_many(self.transcriber.finish())
            if self.session_id is not None:
                self.storage.record_session_end(self.session_id)

    async def _handle_text(self, text: str) -> None:
        payload = json.loads(text)
        if payload.get("type") == "client.ping":
            await self._safe_send(
                pong_event(
                    ping_id=payload.get("ping_id"),
                    client_sent_at_ms=payload.get("client_sent_at_ms"),
                )
            )
            return

        if payload.get("type") == "session.end":
            if self.transcriber is not None:
                await self._send_many(self.transcriber.finish())
            await self.websocket.close()
            return

        await self._safe_send(error_event("unsupported message type: {}".format(payload.get("type"))))

    async def _send_many(self, events: Any) -> None:
        for event in events:
            self.storage.record_transcript_event(event)
            await self._safe_send(event)

    async def _safe_send(self, event: Any) -> None:
        try:
            await self.websocket.send_json(event)
        except RuntimeError:
            pass
