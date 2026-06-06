import unittest

from meeting_backend.audio import sine_pcm16
from meeting_backend.speakers import LocalSpeakerAssigner


class LocalSpeakerAssignerTest(unittest.TestCase):
    def test_microphone_is_self(self) -> None:
        assigner = LocalSpeakerAssigner(
            source="microphone",
            provider="local-clustering",
            sample_rate=16000,
        )

        assignment = assigner.assign(sine_pcm16(16000, 0.4))

        self.assertEqual(assignment.speaker_hint, "self")
        self.assertEqual(assignment.speaker_id, "self")
        self.assertEqual(assignment.speaker_label, "Self")

    def test_system_audio_uses_numbered_speakers(self) -> None:
        assigner = LocalSpeakerAssigner(
            source="system",
            provider="local-clustering",
            sample_rate=16000,
        )

        assignment = assigner.assign(sine_pcm16(16000, 0.4))

        self.assertEqual(assignment.speaker_hint, "other")
        self.assertEqual(assignment.speaker_id, "speaker_1")
        self.assertEqual(assignment.speaker_label, "Speaker 1")

    def test_source_provider_keeps_other_label(self) -> None:
        assigner = LocalSpeakerAssigner(
            source="system",
            provider="source",
            sample_rate=16000,
        )

        assignment = assigner.assign(sine_pcm16(16000, 0.4))

        self.assertEqual(assignment.speaker_id, "other")
        self.assertEqual(assignment.speaker_label, "Other")


if __name__ == "__main__":
    unittest.main()
