import os
import tempfile
import wave
from typing import Dict, Optional

from meeting_backend.transcription.segmented import SegmentedStreamingTranscriber, TranscriptionResult
from meeting_backend.transcription.segmenter import SpeechSegmenterConfig

MLX_MODEL_ALIASES = {
    "tiny": "mlx-community/whisper-tiny",
    "base": "mlx-community/whisper-base-mlx-fp32",
    "small": "mlx-community/whisper-small-mlx-fp32",
    "medium": "mlx-community/whisper-medium-mlx-fp32",
    "large-v2": "mlx-community/whisper-large-v2-mlx-fp32",
    "large-v3": "mlx-community/whisper-large-v3-mlx",
    "large-v3-turbo": "mlx-community/whisper-large-v3-turbo",
}


class MlxWhisperStreamingTranscriber(SegmentedStreamingTranscriber):
    provider_name = "mlx-whisper"

    def __init__(
        self,
        *,
        model_name: str,
        language: Optional[str],
        segmenter_config: SpeechSegmenterConfig,
        diarization_provider: str = "local-clustering",
        diarization_max_speakers: int = 4,
        diarization_cluster_threshold: float = 0.32,
    ) -> None:
        try:
            import mlx_whisper
        except ImportError as error:
            raise RuntimeError(
                "mlx-whisper provider requires `python -m pip install -e \".[mlx-whisper]\"`"
            ) from error

        super().__init__(
            segmenter_config=segmenter_config,
            diarization_provider=diarization_provider,
            diarization_max_speakers=diarization_max_speakers,
            diarization_cluster_threshold=diarization_cluster_threshold,
        )
        self._mlx_whisper = mlx_whisper
        self.model_name = model_name
        self.resolved_model_name = resolve_mlx_model_name(model_name)
        self.language = language

    def status_message(self) -> str:
        return "mlx-whisper provider ready: {} ({})".format(
            self.model_name,
            self.resolved_model_name,
        )

    def transcribe_audio(self, audio: bytes) -> TranscriptionResult:
        if not audio:
            return TranscriptionResult(text="")

        wav_path = self._write_temp_wav(audio)
        try:
            result = self._transcribe_wav(wav_path)
        finally:
            os.unlink(wav_path)

        return TranscriptionResult(text=str(result.get("text") or ""))

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
