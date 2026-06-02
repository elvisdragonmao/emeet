from typing import Dict, List, Optional

from meeting_backend.protocol import SessionStart, status_event, transcript_event
from meeting_backend.transcription.segmenter import SpeechSegment, SpeechSegmenterConfig, SpeechWindowSegmenter


class FasterWhisperStreamingTranscriber:
    provider_name = "faster-whisper"

    def __init__(
        self,
        *,
        model_name: str,
        device: str,
        compute_type: str,
        language: Optional[str],
        segmenter_config: SpeechSegmenterConfig,
    ) -> None:
        try:
            import numpy as np
            from faster_whisper import WhisperModel
        except ImportError as error:
            raise RuntimeError(
                "faster-whisper provider requires `python -m pip install -e \".[stt]\"`"
            ) from error

        self._np = np
        self.model = WhisperModel(model_name, device=device, compute_type=compute_type)
        self.model_name = model_name
        self.language = language
        self.session: Optional[SessionStart] = None
        self.segmenter_config = segmenter_config
        self.segmenter: Optional[SpeechWindowSegmenter] = None
        self.segment_index = 1

    def start(self, session: SessionStart) -> List[Dict]:
        self.session = session
        self.segmenter = SpeechWindowSegmenter(
            sample_rate=session.sample_rate,
            channels=session.channels,
            config=self.segmenter_config,
        )
        return [
            status_event(
                "faster-whisper model loaded: {}".format(self.model_name),
                provider=self.provider_name,
            )
        ]

    def accept_audio(self, audio: bytes) -> List[Dict]:
        if self.session is None or self.segmenter is None:
            return []

        events: List[Dict] = []
        for segment in self.segmenter.accept_audio(audio):
            event = self._transcribe_segment(segment)
            if event is not None:
                events.append(event)
        return events

    def finish(self) -> List[Dict]:
        if self.session is None or self.segmenter is None:
            return []

        events = []
        for segment in self.segmenter.finish():
            event = self._transcribe_segment(segment)
            if event is not None:
                events.append(event)
        return events

    def _transcribe_segment(self, segment: SpeechSegment) -> Optional[Dict]:
        if self.session is None:
            return None

        audio_array = self._pcm16_to_float32(segment.audio)
        if audio_array.size == 0:
            return None

        segments, _info = self.model.transcribe(
            audio_array,
            language=self.language,
            beam_size=1,
            vad_filter=False,
        )
        text = " ".join(segment.text.strip() for segment in segments).strip()
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
            confidence=None,
        )
        self.segment_index += 1
        return event

    def _pcm16_to_float32(self, audio: bytes):
        sample_count = len(audio) // 2
        if sample_count <= 0:
            return self._np.array([], dtype=self._np.float32)

        samples = self._np.frombuffer(audio[: sample_count * 2], dtype="<i2")
        return samples.astype(self._np.float32) / 32768.0
