from meeting_backend.config import Settings
from meeting_backend.transcription.faster_whisper_provider import FasterWhisperStreamingTranscriber
from meeting_backend.transcription.mock import MockStreamingTranscriber


def create_transcriber(settings: Settings):
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
            final_interval_ms=settings.final_interval_ms,
        )

    raise ValueError("unsupported provider: {}".format(settings.provider))
