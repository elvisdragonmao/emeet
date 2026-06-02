import asyncio
import json
import os
import sys
import wave

import websockets


def websocket_uri() -> str:
    explicit_url = os.getenv("MEETING_BACKEND_WS_URL")
    if explicit_url:
        return explicit_url

    host = os.getenv("MEETING_BACKEND_HOST", "127.0.0.1")
    port = os.getenv("MEETING_BACKEND_PORT", "8765")
    return "ws://{}:{}/v1/transcribe/ws".format(host, port)


def receive_timeout() -> float:
    return float(os.getenv("MEETING_BACKEND_CLIENT_TIMEOUT", "10"))


async def stream_wav(path: str) -> None:
    with wave.open(path, "rb") as wav:
        channels = wav.getnchannels()
        sample_rate = wav.getframerate()
        sample_width = wav.getsampwidth()
        audio = wav.readframes(wav.getnframes())

    if channels != 1 or sample_rate != 16000 or sample_width != 2:
        raise SystemExit("expected 16 kHz mono PCM16 wav")

    uri = websocket_uri()
    timeout = receive_timeout()
    frame_ms = 100
    frame_bytes = int(sample_rate * frame_ms / 1000) * sample_width

    async with websockets.connect(uri) as websocket:
        await websocket.send(
            json.dumps(
                {
                    "type": "session.start",
                    "session_id": "wav-client",
                    "source": "microphone",
                    "sample_rate": sample_rate,
                    "channels": channels,
                    "sample_width": sample_width,
                }
            )
        )
        print(await websocket.recv())

        for offset in range(0, len(audio), frame_bytes):
            await websocket.send(audio[offset : offset + frame_bytes])
            await asyncio.sleep(frame_ms / 1000)

        await websocket.send(json.dumps({"type": "session.end"}))
        try:
            while True:
                print(await asyncio.wait_for(websocket.recv(), timeout=timeout))
        except (asyncio.TimeoutError, websockets.ConnectionClosed):
            pass


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: python scripts/send_wav_audio.py /path/to/audio.wav")
    asyncio.run(stream_wav(sys.argv[1]))
