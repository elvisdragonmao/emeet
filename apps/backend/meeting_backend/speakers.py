import math
import sys
from array import array
from dataclasses import dataclass
from typing import List, Optional, Sequence


@dataclass(frozen=True)
class SpeakerAssignment:
    speaker_hint: str
    speaker_id: str
    speaker_label: str


@dataclass
class _SpeakerCluster:
    speaker_id: str
    speaker_label: str
    centroid: List[float]
    observations: int = 1


class LocalSpeakerAssigner:
    """Assigns stable local speaker labels for transcript segments.

    This is intentionally a small online assigner, not a full diarization model.
    It keeps the demo local-only and provides a replaceable contract for a later
    pyannote/SpeakerKit implementation.
    """

    def __init__(
        self,
        *,
        source: str,
        provider: str,
        sample_rate: int,
        max_speakers: int = 4,
        cluster_threshold: float = 0.32,
    ) -> None:
        self.source = source
        self.provider = provider.strip().lower()
        self.sample_rate = sample_rate
        self.max_speakers = max(1, max_speakers)
        self.cluster_threshold = max(0.01, cluster_threshold)
        self._clusters: List[_SpeakerCluster] = []

    def assign(self, audio: bytes) -> SpeakerAssignment:
        if self.source == "microphone":
            return SpeakerAssignment(
                speaker_hint="self",
                speaker_id="self",
                speaker_label="Self",
            )

        if self.source != "system":
            return SpeakerAssignment(
                speaker_hint="unknown",
                speaker_id="unknown",
                speaker_label="Unknown",
            )

        if self.provider in {"", "none", "source", "source-only"}:
            return SpeakerAssignment(
                speaker_hint="other",
                speaker_id="other",
                speaker_label="Other",
            )

        if self.provider not in {"local", "local-clustering", "heuristic"}:
            return SpeakerAssignment(
                speaker_hint="other",
                speaker_id="other",
                speaker_label="Other",
            )

        feature = extract_voice_feature(audio, sample_rate=self.sample_rate)
        if not feature:
            return self._fallback_system_assignment()

        cluster = self._assign_cluster(feature)
        return SpeakerAssignment(
            speaker_hint="other",
            speaker_id=cluster.speaker_id,
            speaker_label=cluster.speaker_label,
        )

    def _fallback_system_assignment(self) -> SpeakerAssignment:
        if self._clusters:
            cluster = self._clusters[0]
            return SpeakerAssignment(
                speaker_hint="other",
                speaker_id=cluster.speaker_id,
                speaker_label=cluster.speaker_label,
            )

        cluster = self._new_cluster([])
        return SpeakerAssignment(
            speaker_hint="other",
            speaker_id=cluster.speaker_id,
            speaker_label=cluster.speaker_label,
        )

    def _assign_cluster(self, feature: List[float]) -> _SpeakerCluster:
        if not self._clusters:
            return self._new_cluster(feature)

        distances = [cosine_distance(feature, cluster.centroid) for cluster in self._clusters]
        best_index, best_distance = min(enumerate(distances), key=lambda item: item[1])
        if best_distance > self.cluster_threshold and len(self._clusters) < self.max_speakers:
            return self._new_cluster(feature)

        cluster = self._clusters[best_index]
        cluster.centroid = blend_vectors(cluster.centroid, feature, weight=0.18)
        cluster.observations += 1
        return cluster

    def _new_cluster(self, feature: List[float]) -> _SpeakerCluster:
        index = len(self._clusters) + 1
        cluster = _SpeakerCluster(
            speaker_id="speaker_{}".format(index),
            speaker_label="Speaker {}".format(index),
            centroid=feature,
        )
        self._clusters.append(cluster)
        return cluster


def extract_voice_feature(audio: bytes, *, sample_rate: int) -> List[float]:
    numpy_feature = extract_numpy_voice_feature(audio, sample_rate=sample_rate)
    if numpy_feature:
        return numpy_feature
    return extract_basic_voice_feature(audio)


def extract_numpy_voice_feature(audio: bytes, *, sample_rate: int) -> List[float]:
    try:
        import numpy as np  # type: ignore
    except Exception:
        return []

    if len(audio) < 160:
        return []

    samples = np.frombuffer(audio, dtype="<i2").astype(np.float32) / 32768.0
    if samples.size < max(160, sample_rate // 25):
        return []

    samples = samples - float(np.mean(samples))
    frame_length = max(128, int(sample_rate * 0.025))
    hop = max(64, int(sample_rate * 0.010))
    if samples.size < frame_length:
        frame_length = int(samples.size)
        hop = frame_length

    band_vectors = []
    rms_values = []
    zcr_values = []
    window = np.hanning(frame_length).astype(np.float32)
    fft_size = 1
    while fft_size < frame_length:
        fft_size *= 2
    fft_size = max(256, fft_size)

    for start in range(0, max(1, samples.size - frame_length + 1), hop):
        frame = samples[start : start + frame_length]
        if frame.size < frame_length:
            break
        rms = float(np.sqrt(np.mean(frame * frame)))
        if rms < 0.002:
            continue
        spectrum = np.abs(np.fft.rfft(frame * window, n=fft_size))[1:]
        if spectrum.size == 0:
            continue
        bands = np.array_split(spectrum, 32)
        band_vectors.append([float(np.log1p(np.mean(band))) for band in bands if band.size])
        rms_values.append(math.log1p(rms * 100.0))
        signs = np.signbit(frame)
        zcr_values.append(float(np.count_nonzero(signs[1:] != signs[:-1]) / max(1, frame.size - 1)))

    if not band_vectors:
        return []

    bands_array = np.asarray(band_vectors, dtype=np.float32)
    feature = np.concatenate(
        [
            bands_array.mean(axis=0),
            bands_array.std(axis=0),
            np.asarray(
                [
                    float(np.mean(rms_values)),
                    float(np.std(rms_values)),
                    float(np.mean(zcr_values)),
                    float(np.std(zcr_values)),
                ],
                dtype=np.float32,
            ),
        ]
    )
    return normalize_vector([float(value) for value in feature])


def extract_basic_voice_feature(audio: bytes) -> List[float]:
    samples = pcm16_samples(audio)
    if len(samples) < 32:
        return []

    mean_abs = sum(abs(sample) for sample in samples) / len(samples)
    rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
    peak = max(abs(sample) for sample in samples) or 1
    zero_crossings = sum(
        1
        for previous, current in zip(samples, samples[1:])
        if (previous < 0 <= current) or (previous >= 0 > current)
    )
    zcr = zero_crossings / max(1, len(samples) - 1)
    return normalize_vector(
        [
            math.log1p(mean_abs),
            math.log1p(rms),
            math.log1p(peak),
            zcr,
            rms / peak,
        ]
    )


def pcm16_samples(audio: bytes) -> array:
    samples = array("h")
    usable_length = len(audio) - (len(audio) % 2)
    samples.frombytes(audio[:usable_length])
    if sys.byteorder != "little":
        samples.byteswap()
    return samples


def normalize_vector(values: Sequence[float]) -> List[float]:
    finite_values = [0.0 if not math.isfinite(value) else float(value) for value in values]
    norm = math.sqrt(sum(value * value for value in finite_values))
    if norm <= 0:
        return []
    return [value / norm for value in finite_values]


def cosine_distance(left: Sequence[float], right: Sequence[float]) -> float:
    if not left or not right or len(left) != len(right):
        return 1.0
    similarity = sum(a * b for a, b in zip(left, right))
    return max(0.0, min(2.0, 1.0 - similarity))


def blend_vectors(left: Sequence[float], right: Sequence[float], *, weight: float) -> List[float]:
    if not left or len(left) != len(right):
        return list(right)

    left_weight = max(0.0, min(1.0, 1.0 - weight))
    right_weight = max(0.0, min(1.0, weight))
    return normalize_vector([left_weight * a + right_weight * b for a, b in zip(left, right)])
