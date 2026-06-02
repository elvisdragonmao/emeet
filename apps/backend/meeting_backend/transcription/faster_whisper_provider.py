from typing import Dict, List, Optional

from meeting_backend.audio import pcm16_duration_ms
from meeting_backend.protocol import SessionStart, status_event, transcript_event


class FasterWhisperStreamingTranscriber:
    provider_name = "faster-whisper"

    def __init__(
        self,
        *,
        model_name: str,
        device: str,
        compute_type: str,
        language: Optional[str],
        final_interval_ms: int = 2400,
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
        self.final_interval_ms = final_interval_ms
        self.session: Optional[SessionStart] = None
        self.total_ms = 0
        self.segment_index = 1
        self.segment_start_ms = 0
        self.segment_audio = bytearray()
        self.next_final_ms = final_interval_ms
        self.revision = 0

    def start(self, session: SessionStart) -> List[Dict]:
        self.session = session
        return [
            status_event(
                "faster-whisper model loaded: {}".format(self.model_name),
                provider=self.provider_name,
            )
        ]

    def accept_audio(self, audio: bytes) -> List[Dict]:
        if self.session is None:
            return []

        self.segment_audio.extend(audio)
        self.total_ms += pcm16_duration_ms(
            len(audio),
            sample_rate=self.session.sample_rate,
            channels=self.session.channels,
        )

        if self.total_ms < self.next_final_ms:
            return []

        event = self._transcribe_current_segment()
        self._rotate_segment()
        return [event] if event is not None else []

    def finish(self) -> List[Dict]:
        if self.session is None or not self.segment_audio:
            return []

        event = self._transcribe_current_segment()
        self.segment_audio.clear()
        return [event] if event is not None else []

    def _transcribe_current_segment(self) -> Optional[Dict]:
        if self.session is None:
            return None

        audio_array = self._pcm16_to_float32(bytes(self.segment_audio))
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

        self.revision += 1
        return transcript_event(
            event_type="transcript.final",
            session=self.session,
            segment_index=self.segment_index,
            start_ms=self.segment_start_ms,
            end_ms=self.total_ms,
            text=text,
            revision=self.revision,
            is_final=True,
            provider=self.provider_name,
            confidence=None,
        )

    def _pcm16_to_float32(self, audio: bytes):
        sample_count = len(audio) // 2
        if sample_count <= 0:
            return self._np.array([], dtype=self._np.float32)

        samples = self._np.frombuffer(audio[: sample_count * 2], dtype="<i2")
        return samples.astype(self._np.float32) / 32768.0

    def _rotate_segment(self) -> None:
        self.segment_index += 1
        self.segment_start_ms = self.total_ms
        self.segment_audio.clear()
        self.next_final_ms = self.total_ms + self.final_interval_ms
        self.revision = 0
