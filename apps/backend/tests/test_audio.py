import unittest

from meeting_backend.audio import pcm16_duration_ms, pcm16_rms, sine_pcm16


class AudioTest(unittest.TestCase):
    def test_pcm16_duration_ms(self) -> None:
        self.assertEqual(pcm16_duration_ms(3200, sample_rate=16000, channels=1), 100)

    def test_sine_pcm16_has_energy(self) -> None:
        audio = sine_pcm16(sample_rate=16000, duration_seconds=0.1)
        self.assertGreater(pcm16_rms(audio), 0.01)


if __name__ == "__main__":
    unittest.main()
