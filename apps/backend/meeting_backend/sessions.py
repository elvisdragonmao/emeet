import json
from typing import Any

from fastapi import WebSocket
from starlette.websockets import WebSocketDisconnect

from meeting_backend.config import Settings
from meeting_backend.protocol import error_event, parse_session_start
from meeting_backend.transcription import create_transcriber


class TranscriptionSession:
    def __init__(self, websocket: WebSocket, settings: Settings) -> None:
        self.websocket = websocket
        self.settings = settings
        self.transcriber = create_transcriber(settings)

    async def run(self) -> None:
        await self.websocket.accept()

        try:
            first_message = await self.websocket.receive_text()
            session = parse_session_start(json.loads(first_message))
            await self._send_many(self.transcriber.start(session))

            while True:
                message = await self.websocket.receive()
                if message["type"] == "websocket.disconnect":
                    break

                if message.get("bytes") is not None:
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
            await self._send_many(self.transcriber.finish())

    async def _handle_text(self, text: str) -> None:
        payload = json.loads(text)
        if payload.get("type") == "session.end":
            await self._send_many(self.transcriber.finish())
            await self.websocket.close()
            return

        await self._safe_send(error_event("unsupported message type: {}".format(payload.get("type"))))

    async def _send_many(self, events: Any) -> None:
        for event in events:
            await self._safe_send(event)

    async def _safe_send(self, event: Any) -> None:
        try:
            await self.websocket.send_json(event)
        except RuntimeError:
            pass
