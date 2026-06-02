from meeting_backend.config import Settings
from meeting_backend.transcription.faster_whisper_provider import FasterWhisperStreamingTranscriber
from meeting_backend.transcription.mlx_whisper_provider import MlxWhisperStreamingTranscriber
from meeting_backend.transcription.mock import MockStreamingTranscriber
from meeting_backend.transcription.segmenter import SpeechSegmenterConfig


def create_transcriber(settings: Settings):
    segmenter_config = SpeechSegmenterConfig(
        min_segment_ms=settings.segment_min_ms,
        silence_ms=settings.segment_silence_ms,
        max_segment_ms=settings.segment_max_ms,
        speech_rms_threshold=settings.vad_rms_threshold,
    )

    if settings.provider == "mock":
        return MockStreamingTranscriber(
            partial_interval_ms=settings.partial_interval_ms,
            final_interval_ms=settings.final_interval_ms,
        )
    if settings.provider == "faster-whisper":
        return FasterWhisperStreamingTranscriber(
            model_name=settings.whisper_model,
            device=settings.whisper_device,
            compute_type=settings.whisper_compute_type,
            language=settings.whisper_language or None,
            segmenter_config=segmenter_config,
        )
    if settings.provider == "mlx-whisper":
        return MlxWhisperStreamingTranscriber(
            model_name=settings.whisper_model,
            language=settings.whisper_language or None,
            segmenter_config=segmenter_config,
        )

    raise ValueError("unsupported provider: {}".format(settings.provider))
