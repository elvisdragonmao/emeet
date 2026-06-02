from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Dict, List, Optional

from meeting_backend.protocol import SessionStart, status_event, transcript_event
from meeting_backend.transcription.segmenter import SpeechSegment, SpeechSegmenterConfig, SpeechWindowSegmenter


@dataclass(frozen=True)
class TranscriptionResult:
    text: str
    confidence: Optional[float] = None


class SegmentedStreamingTranscriber(ABC):
    provider_name: str

    def __init__(self, *, segmenter_config: SpeechSegmenterConfig) -> None:
        self.segmenter_config = segmenter_config
        self.session: Optional[SessionStart] = None
        self.segmenter: Optional[SpeechWindowSegmenter] = None
        self.segment_index = 1

    def start(self, session: SessionStart) -> List[Dict]:
        self.session = session
        self.segmenter = SpeechWindowSegmenter(
            sample_rate=session.sample_rate,
            channels=session.channels,
            config=self.segmenter_config,
        )
        return [status_event(self.status_message(), provider=self.provider_name)]

    def accept_audio(self, audio: bytes) -> List[Dict]:
        if self.session is None or self.segmenter is None:
            return []

        return self._transcribe_segments(self.segmenter.accept_audio(audio))

    def finish(self) -> List[Dict]:
        if self.session is None or self.segmenter is None:
            return []

        return self._transcribe_segments(self.segmenter.finish())

    @abstractmethod
    def status_message(self) -> str:
        ...

    @abstractmethod
    def transcribe_audio(self, audio: bytes) -> TranscriptionResult:
        ...

    def _transcribe_segments(self, segments: List[SpeechSegment]) -> List[Dict]:
        events: List[Dict] = []
        for segment in segments:
            event = self._transcribe_segment(segment)
            if event is not None:
                events.append(event)
        return events

    def _transcribe_segment(self, segment: SpeechSegment) -> Optional[Dict]:
        if self.session is None:
            return None

        result = self.transcribe_audio(segment.audio)
        text = result.text.strip()
        if not text:
            text = "[no speech detected]"

        event = transcript_event(
            event_type="transcript.final",
            session=self.session,
            segment_index=self.segment_index,
            start_ms=segment.start_ms,
            end_ms=segment.end_ms,
            text=text,
            revision=1,
            is_final=True,
            provider=self.provider_name,
            confidence=result.confidence,
        )
        self.segment_index += 1
        return event
