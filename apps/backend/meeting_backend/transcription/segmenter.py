from dataclasses import dataclass
from typing import List, Optional

from meeting_backend.audio import pcm16_duration_ms, pcm16_rms


@dataclass(frozen=True)
class SpeechSegmenterConfig:
    min_segment_ms: int = 800
    silence_ms: int = 700
    max_segment_ms: int = 12_000
    speech_rms_threshold: float = 0.012


@dataclass(frozen=True)
class SpeechSegment:
    audio: bytes
    start_ms: int
    end_ms: int
    reason: str


class SpeechWindowSegmenter:
    def __init__(
        self,
        *,
        sample_rate: int,
        channels: int,
        config: SpeechSegmenterConfig,
    ) -> None:
        self.sample_rate = sample_rate
        self.channels = channels
        self.config = config
        self.clock_ms = 0
        self.segment_start_ms: Optional[int] = None
        self.segment_audio = bytearray()
        self.segment_has_speech = False
        self.trailing_silence_ms = 0

    def accept_audio(self, audio: bytes) -> List[SpeechSegment]:
        duration_ms = pcm16_duration_ms(
            len(audio),
            sample_rate=self.sample_rate,
            channels=self.channels,
        )
        if duration_ms <= 0:
            return []

        chunk_start_ms = self.clock_ms
        chunk_end_ms = self.clock_ms + duration_ms
        is_speech = pcm16_rms(audio) >= self.config.speech_rms_threshold

        if not self.segment_audio and not is_speech:
            self.clock_ms = chunk_end_ms
            return []

        if self.segment_start_ms is None:
            self.segment_start_ms = chunk_start_ms

        self.segment_audio.extend(audio)
        if is_speech:
            self.segment_has_speech = True
            self.trailing_silence_ms = 0
        else:
            self.trailing_silence_ms += duration_ms

        self.clock_ms = chunk_end_ms
        if not self.segment_has_speech:
            return []

        segment_ms = self.clock_ms - self.segment_start_ms
        if segment_ms >= self.config.min_segment_ms and self.trailing_silence_ms >= self.config.silence_ms:
            return [self._emit(reason="silence")]

        if segment_ms >= self.config.max_segment_ms:
            return [self._emit(reason="max_duration")]

        return []

    def finish(self) -> List[SpeechSegment]:
        if not self.segment_audio or not self.segment_has_speech:
            self._reset()
            return []

        return [self._emit(reason="session_end")]

    def _emit(self, *, reason: str) -> SpeechSegment:
        if self.segment_start_ms is None:
            raise RuntimeError("segment has not started")

        segment = SpeechSegment(
            audio=bytes(self.segment_audio),
            start_ms=self.segment_start_ms,
            end_ms=self.clock_ms,
            reason=reason,
        )
        self._reset()
        return segment

    def _reset(self) -> None:
        self.segment_start_ms = None
        self.segment_audio.clear()
        self.segment_has_speech = False
        self.trailing_silence_ms = 0
