from meeting_backend.config import Settings
from meeting_backend.transcription.faster_whisper_provider import FasterWhisperStreamingTranscriber
from meeting_backend.transcription.mlx_whisper_provider import MlxWhisperStreamingTranscriber
from meeting_backend.transcription.segmenter import SpeechSegmenterConfig


def create_transcriber(settings: Settings):
    segmenter_config = SpeechSegmenterConfig(
        min_segment_ms=settings.segment_min_ms,
        silence_ms=settings.segment_silence_ms,
        max_segment_ms=settings.segment_max_ms,
        speech_rms_threshold=settings.vad_rms_threshold,
    )

    if settings.provider == "faster-whisper":
        return FasterWhisperStreamingTranscriber(
            model_name=settings.whisper_model,
            device=settings.whisper_device,
            compute_type=settings.whisper_compute_type,
            language=settings.whisper_language or None,
            segmenter_config=segmenter_config,
            diarization_provider=settings.diarization_provider,
            diarization_max_speakers=settings.diarization_max_speakers,
            diarization_cluster_threshold=settings.diarization_cluster_threshold,
        )
    if settings.provider == "mlx-whisper":
        return MlxWhisperStreamingTranscriber(
            model_name=settings.whisper_model,
            language=settings.whisper_language or None,
            segmenter_config=segmenter_config,
            diarization_provider=settings.diarization_provider,
            diarization_max_speakers=settings.diarization_max_speakers,
            diarization_cluster_threshold=settings.diarization_cluster_threshold,
        )

    raise ValueError("unsupported provider: {}".format(settings.provider))
