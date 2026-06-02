import asyncio
import json

import websockets

from meeting_backend.audio import sine_pcm16


async def main() -> None:
    uri = "ws://127.0.0.1:8765/v1/transcribe/ws"
    sample_rate = 16_000
    frame_ms = 100
    frame_bytes = int(sample_rate * frame_ms / 1000) * 2
    audio = sine_pcm16(sample_rate=sample_rate, duration_seconds=3.0)

    async with websockets.connect(uri) as websocket:
        await websocket.send(
            json.dumps(
                {
                    "type": "session.start",
                    "session_id": "test-client",
                    "source": "microphone",
                    "sample_rate": sample_rate,
                    "channels": 1,
                    "sample_width": 2,
                }
            )
        )
        print(await websocket.recv())

        for offset in range(0, len(audio), frame_bytes):
            await websocket.send(audio[offset : offset + frame_bytes])
            try:
                while True:
                    event = await asyncio.wait_for(websocket.recv(), timeout=0.01)
                    print(event)
            except asyncio.TimeoutError:
                pass
            await asyncio.sleep(frame_ms / 1000)

        await websocket.send(json.dumps({"type": "session.end"}))
        try:
            while True:
                print(await asyncio.wait_for(websocket.recv(), timeout=0.5))
        except (asyncio.TimeoutError, websockets.ConnectionClosed):
            pass


if __name__ == "__main__":
    asyncio.run(main())
