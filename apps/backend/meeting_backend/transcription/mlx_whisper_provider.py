import os
import tempfile
import wave
from typing import Dict, List, Optional

from meeting_backend.protocol import SessionStart, status_event, transcript_event
from meeting_backend.transcription.segmenter import SpeechSegment, SpeechSegmenterConfig, SpeechWindowSegmenter

MLX_MODEL_ALIASES = {
    "tiny": "mlx-community/whisper-tiny",
    "base": "mlx-community/whisper-base-mlx-fp32",
    "small": "mlx-community/whisper-small-mlx-fp32",
    "medium": "mlx-community/whisper-medium-mlx-fp32",
    "large-v2": "mlx-community/whisper-large-v2-mlx-fp32",
    "large-v3": "mlx-community/whisper-large-v3-mlx",
    "large-v3-turbo": "mlx-community/whisper-large-v3-turbo",
}


class MlxWhisperStreamingTranscriber:
    provider_name = "mlx-whisper"

    def __init__(
        self,
        *,
        model_name: str,
        language: Optional[str],
        segmenter_config: SpeechSegmenterConfig,
    ) -> None:
        try:
            import mlx_whisper
        except ImportError as error:
            raise RuntimeError(
                "mlx-whisper provider requires `python -m pip install -e \".[mlx-whisper]\"`"
            ) from error

        self._mlx_whisper = mlx_whisper
        self.model_name = model_name
        self.resolved_model_name = resolve_mlx_model_name(model_name)
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
                "mlx-whisper provider ready: {} ({})".format(
                    self.model_name,
                    self.resolved_model_name,
                ),
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

        audio = segment.audio
        if not audio:
            return None

        wav_path = self._write_temp_wav(audio)
        try:
            result = self._transcribe_wav(wav_path)
        finally:
            os.unlink(wav_path)

        text = str(result.get("text") or "").strip()
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

    def _transcribe_wav(self, wav_path: str) -> Dict:
        kwargs = {"path_or_hf_repo": self.resolved_model_name}
        if self.language:
            kwargs["language"] = self.language

        return self._mlx_whisper.transcribe(wav_path, **kwargs)

    def _write_temp_wav(self, audio: bytes) -> str:
        if self.session is None:
            raise RuntimeError("session has not started")

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as file:
            path = file.name

        with wave.open(path, "wb") as wav:
            wav.setnchannels(self.session.channels)
            wav.setsampwidth(self.session.sample_width)
            wav.setframerate(self.session.sample_rate)
            wav.writeframes(audio)

        return path


def resolve_mlx_model_name(model_name: str) -> str:
    return MLX_MODEL_ALIASES.get(model_name, model_name)
