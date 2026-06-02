from typing import Dict, List, Optional

from meeting_backend.audio import pcm16_duration_ms, pcm16_rms
from meeting_backend.protocol import SessionStart, status_event, transcript_event


class MockStreamingTranscriber:
    provider_name = "mock"

    def __init__(self, partial_interval_ms: int = 800, final_interval_ms: int = 2400) -> None:
        self.partial_interval_ms = partial_interval_ms
        self.final_interval_ms = final_interval_ms
        self.session: Optional[SessionStart] = None
        self.total_ms = 0
        self.segment_index = 1
        self.segment_start_ms = 0
        self.segment_audio = bytearray()
        self.next_partial_ms = partial_interval_ms
        self.next_final_ms = final_interval_ms
        self.revision = 0

    def start(self, session: SessionStart) -> List[Dict]:
        self.session = session
        return [status_event("session started", provider=self.provider_name)]

    def accept_audio(self, audio: bytes) -> List[Dict]:
        if self.session is None:
            return []

        self.segment_audio.extend(audio)
        self.total_ms += pcm16_duration_ms(
            len(audio),
            sample_rate=self.session.sample_rate,
            channels=self.session.channels,
        )

        events: List[Dict] = []
        if self.total_ms >= self.next_partial_ms:
            events.append(self._event(is_final=False))
            self.next_partial_ms += self.partial_interval_ms

        if self.total_ms >= self.next_final_ms:
            events.append(self._event(is_final=True))
            self._rotate_segment()

        return events

    def finish(self) -> List[Dict]:
        if self.session is None or not self.segment_audio:
            return []
        event = self._event(is_final=True)
        self.segment_audio.clear()
        return [event]

    def _event(self, *, is_final: bool) -> Dict:
        if self.session is None:
            raise RuntimeError("session has not started")

        self.revision += 1
        rms = pcm16_rms(bytes(self.segment_audio))
        duration_seconds = max(0.0, (self.total_ms - self.segment_start_ms) / 1000.0)
        text = "[mock {} audio {:.1f}s rms={:.4f}]".format(
            self.session.source,
            duration_seconds,
            rms,
        )

        return transcript_event(
            event_type="transcript.final" if is_final else "transcript.partial",
            session=self.session,
            segment_index=self.segment_index,
            start_ms=self.segment_start_ms,
            end_ms=self.total_ms,
            text=text,
            revision=self.revision,
            is_final=is_final,
            provider=self.provider_name,
        )

    def _rotate_segment(self) -> None:
        self.segment_index += 1
        self.segment_start_ms = self.total_ms
        self.segment_audio.clear()
        self.next_partial_ms = self.total_ms + self.partial_interval_ms
        self.next_final_ms = self.total_ms + self.final_interval_ms
        self.revision = 0
