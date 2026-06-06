from typing import Optional

from meeting_backend.transcription.segmented import SegmentedStreamingTranscriber, TranscriptionResult
from meeting_backend.transcription.segmenter import SpeechSegmenterConfig


class FasterWhisperStreamingTranscriber(SegmentedStreamingTranscriber):
    provider_name = "faster-whisper"

    def __init__(
        self,
        *,
        model_name: str,
        device: str,
        compute_type: str,
        language: Optional[str],
        segmenter_config: SpeechSegmenterConfig,
        diarization_provider: str = "local-clustering",
        diarization_max_speakers: int = 4,
        diarization_cluster_threshold: float = 0.32,
    ) -> None:
        try:
            import numpy as np
            from faster_whisper import WhisperModel
        except ImportError as error:
            raise RuntimeError(
                "faster-whisper provider requires `python -m pip install -e \".[stt]\"`"
            ) from error

        super().__init__(
            segmenter_config=segmenter_config,
            diarization_provider=diarization_provider,
            diarization_max_speakers=diarization_max_speakers,
            diarization_cluster_threshold=diarization_cluster_threshold,
        )
        self._np = np
        self.model = WhisperModel(model_name, device=device, compute_type=compute_type)
        self.model_name = model_name
        self.language = language

    def status_message(self) -> str:
        return "faster-whisper model loaded: {}".format(self.model_name)

    def transcribe_audio(self, audio: bytes) -> TranscriptionResult:
        audio_array = self._pcm16_to_float32(audio)
        if audio_array.size == 0:
            return TranscriptionResult(text="")

        segments, _info = self.model.transcribe(
            audio_array,
            language=self.language,
            beam_size=1,
            vad_filter=False,
        )
        text = " ".join(segment.text.strip() for segment in segments).strip()
        return TranscriptionResult(text=text)

    def _pcm16_to_float32(self, audio: bytes):
        sample_count = len(audio) // 2
        if sample_count <= 0:
            return self._np.array([], dtype=self._np.float32)

        samples = self._np.frombuffer(audio[: sample_count * 2], dtype="<i2")
        return samples.astype(self._np.float32) / 32768.0
