import os
import tempfile
import wave
from typing import Dict, List, Optional

from meeting_backend.audio import pcm16_duration_ms
from meeting_backend.protocol import SessionStart, status_event, transcript_event

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
        final_interval_ms: int = 2400,
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
                "mlx-whisper provider ready: {} ({})".format(
                    self.model_name,
                    self.resolved_model_name,
                ),
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

        audio = bytes(self.segment_audio)
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

    def _rotate_segment(self) -> None:
        self.segment_index += 1
        self.segment_start_ms = self.total_ms
        self.segment_audio.clear()
        self.next_final_ms = self.total_ms + self.final_interval_ms
        self.revision = 0


def resolve_mlx_model_name(model_name: str) -> str:
    return MLX_MODEL_ALIASES.get(model_name, model_name)
