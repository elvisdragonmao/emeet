import importlib.util
import platform
import shutil
import subprocess
from typing import Any, Dict, List

from meeting_backend.config import Settings


LANGUAGE_OPTIONS = [
    {"id": "auto", "label": "Auto detect", "notes": "Use model language detection."},
    {"id": "zh", "label": "Chinese / Mandarin", "notes": "Recommended for Taiwanese Mandarin meetings."},
    {"id": "en", "label": "English", "notes": "Force English transcription."},
    {"id": "ja", "label": "Japanese", "notes": "Force Japanese transcription."},
]


def transcription_options(settings: Settings) -> Dict[str, Any]:
    hardware = hardware_info()
    mlx_installed = module_available("mlx_whisper")
    faster_whisper_installed = module_available("faster_whisper")
    apple_silicon = bool(hardware["apple_silicon"])
    memory_gb = float(hardware["memory_gb"])

    mlx_available = mlx_installed and apple_silicon
    faster_whisper_available = faster_whisper_installed

    return {
        "defaults": {
            "provider": settings.provider,
            "model": settings.whisper_model,
            "language": settings.whisper_language or "auto",
        },
        "hardware": hardware,
        "providers": [
            {
                "id": "mlx-whisper",
                "label": "MLX Whisper",
                "installed": mlx_installed,
                "available": mlx_available,
                "recommended": mlx_available,
                "notes": [
                    "Uses Apple Silicon GPU through MLX.",
                    "First model run downloads weights from Hugging Face.",
                ],
                "models": [
                    {
                        "id": "breeze-asr-25",
                        "label": "Breeze ASR 25",
                        "available": mlx_available and memory_gb >= 16,
                        "recommended": mlx_available and memory_gb >= 16,
                        "language_hint": "zh",
                        "estimated_size_gb": 3.1,
                        "notes": [
                            "Taiwan Mandarin and Mandarin-English code-switching.",
                            "MLX conversion: schsu/breeze-asr-25-mlx.",
                        ],
                    },
                    {
                        "id": "large-v3-turbo",
                        "label": "Whisper Large v3 Turbo",
                        "available": mlx_available,
                        "recommended": False,
                        "language_hint": "auto",
                        "estimated_size_gb": 1.6,
                        "notes": ["Fast general-purpose Whisper model."],
                    },
                    {
                        "id": "large-v3",
                        "label": "Whisper Large v3",
                        "available": mlx_available and memory_gb >= 16,
                        "recommended": False,
                        "language_hint": "auto",
                        "estimated_size_gb": 3.1,
                        "notes": ["Higher accuracy, heavier than turbo."],
                    },
                    {
                        "id": "medium",
                        "label": "Whisper Medium",
                        "available": mlx_available,
                        "recommended": False,
                        "language_hint": "auto",
                        "estimated_size_gb": 1.5,
                        "notes": ["Fallback for lower-memory systems."],
                    },
                ],
            },
            {
                "id": "faster-whisper",
                "label": "faster-whisper",
                "installed": faster_whisper_installed,
                "available": faster_whisper_available,
                "recommended": not mlx_available and faster_whisper_available,
                "notes": [
                    "CPU-compatible CTranslate2 route.",
                    "Use smaller models for real-time demos on CPU.",
                ],
                "models": [
                    model_option("large-v3-turbo", faster_whisper_available, "auto"),
                    model_option("large-v3", faster_whisper_available and memory_gb >= 16, "auto"),
                    model_option("medium", faster_whisper_available, "auto"),
                    model_option("small", faster_whisper_available, "auto"),
                    model_option("base", faster_whisper_available, "auto"),
                    model_option("tiny", faster_whisper_available, "auto"),
                ],
            },
        ],
        "languages": LANGUAGE_OPTIONS,
    }


def model_option(model_id: str, available: bool, language_hint: str) -> Dict[str, Any]:
    return {
        "id": model_id,
        "label": model_id,
        "available": available,
        "recommended": False,
        "language_hint": language_hint,
        "estimated_size_gb": 0.0,
        "notes": [],
    }


def module_available(name: str) -> bool:
    return importlib.util.find_spec(name) is not None


def hardware_info() -> Dict[str, Any]:
    machine = platform.machine()
    memory_bytes = physical_memory_bytes()
    return {
        "platform": platform.system(),
        "platform_version": platform.mac_ver()[0] or platform.release(),
        "machine": machine,
        "cpu": cpu_name(),
        "memory_gb": round(memory_bytes / 1024 / 1024 / 1024, 1) if memory_bytes else 0.0,
        "apple_silicon": platform.system() == "Darwin" and machine == "arm64",
    }


def physical_memory_bytes() -> int:
    if platform.system() == "Darwin" and shutil.which("sysctl"):
        completed = subprocess.run(
            ["sysctl", "-n", "hw.memsize"],
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode == 0:
            try:
                return int(completed.stdout.strip())
            except ValueError:
                return 0
    return 0


def cpu_name() -> str:
    if platform.system() == "Darwin" and shutil.which("sysctl"):
        completed = subprocess.run(
            ["sysctl", "-n", "machdep.cpu.brand_string"],
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode == 0:
            return completed.stdout.strip()
    return platform.processor()
