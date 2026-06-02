from abc import ABC, abstractmethod
from dataclasses import dataclass
import re
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
            events.extend(self._transcribe_segment(segment))
        return events

    def _transcribe_segment(self, segment: SpeechSegment) -> List[Dict]:
        if self.session is None:
            return []

        result = self.transcribe_audio(segment.audio)
        text = result.text.strip()
        if not text:
            text = "[no speech detected]"

        sentences = split_transcript_sentences(text)
        ranges = distribute_time_ranges(
            start_ms=segment.start_ms,
            end_ms=segment.end_ms,
            texts=sentences,
        )
        events = []
        for sentence, (start_ms, end_ms) in zip(sentences, ranges):
            events.append(
                transcript_event(
                    event_type="transcript.final",
                    session=self.session,
                    segment_index=self.segment_index,
                    start_ms=start_ms,
                    end_ms=end_ms,
                    text=sentence,
                    revision=1,
                    is_final=True,
                    provider=self.provider_name,
                    confidence=result.confidence,
                )
            )
            self.segment_index += 1
        return events


def split_transcript_sentences(text: str) -> List[str]:
    stripped = text.strip()
    if not stripped:
        return []

    parts = re.findall(r"[^.!?。！？]+[.!?。！？]+|[^.!?。！？]+$", stripped)
    sentences = [part.strip() for part in parts if part.strip()]
    return sentences or [stripped]


def distribute_time_ranges(*, start_ms: int, end_ms: int, texts: List[str]) -> List[tuple]:
    if not texts:
        return []
    if len(texts) == 1:
        return [(start_ms, end_ms)]

    duration_ms = max(0, end_ms - start_ms)
    weights = [max(1, len(text)) for text in texts]
    total_weight = sum(weights)
    ranges = []
    cursor = start_ms
    for index, weight in enumerate(weights):
        if index == len(weights) - 1:
            next_cursor = end_ms
        else:
            next_cursor = start_ms + round(duration_ms * sum(weights[: index + 1]) / total_weight)
            next_cursor = max(cursor, min(end_ms, next_cursor))
        ranges.append((cursor, next_cursor))
        cursor = next_cursor
    return ranges
