from meeting_backend.config import Settings
from meeting_backend.transcription.mock import MockStreamingTranscriber


def create_transcriber(settings: Settings):
    if settings.provider == "mock":
        return MockStreamingTranscriber(
            partial_interval_ms=settings.partial_interval_ms,
            final_interval_ms=settings.final_interval_ms,
        )

    raise ValueError("unsupported provider: {}".format(settings.provider))
