import math
import struct


def pcm16_duration_ms(byte_count: int, sample_rate: int, channels: int) -> int:
    bytes_per_frame = channels * 2
    if sample_rate <= 0 or bytes_per_frame <= 0:
        return 0
    frames = byte_count // bytes_per_frame
    return int(frames * 1000 / sample_rate)


def pcm16_rms(audio: bytes) -> float:
    if len(audio) < 2:
        return 0.0

    sample_count = len(audio) // 2
    samples = struct.unpack("<{}h".format(sample_count), audio[: sample_count * 2])
    if not samples:
        return 0.0

    square_sum = 0.0
    for sample in samples:
        normalized = sample / 32768.0
        square_sum += normalized * normalized

    return math.sqrt(square_sum / sample_count)


def sine_pcm16(sample_rate: int, duration_seconds: float, frequency_hz: float = 440.0, amplitude: float = 0.2) -> bytes:
    frame_count = int(sample_rate * duration_seconds)
    clamped_amplitude = max(0.0, min(amplitude, 1.0))
    frames = bytearray()

    for index in range(frame_count):
        radians = 2.0 * math.pi * frequency_hz * index / sample_rate
        sample = int(math.sin(radians) * clamped_amplitude * 32767)
        frames.extend(struct.pack("<h", sample))

    return bytes(frames)
