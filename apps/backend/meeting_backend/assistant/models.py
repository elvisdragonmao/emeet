from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional


@dataclass(frozen=True)
class AssistantTranscriptLine:
    source: str
    source_label: str
    speaker_hint: str
    speaker_id: str
    speaker_label: str
    start_ms: int
    end_ms: int
    text: str
    is_final: bool


@dataclass(frozen=True)
class AssistantRequest:
    action: str
    transcript: List[AssistantTranscriptLine]
    provider: str
    model: str
    thinking: str
    temperature: float
    max_tokens: int
    meeting_id: str = ""
    rolling_summary: str = ""
    previous_notes: List[Dict[str, str]] = field(default_factory=list)
    previous_actions: List[Dict[str, str]] = field(default_factory=list)


@dataclass(frozen=True)
class AssistantProviderDescriptor:
    id: str
    label: str
    kind: str
    installed: bool
    available: bool
    models: List[str]
    capabilities: List[str]
    risk_level: str
    auth_mode: str
    endpoint: str = ""
    binary_path: str = ""
    notes: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "label": self.label,
            "kind": self.kind,
            "installed": self.installed,
            "available": self.available,
            "models": self.models,
            "capabilities": self.capabilities,
            "risk_level": self.risk_level,
            "auth_mode": self.auth_mode,
            "endpoint": self.endpoint,
            "binary_path": self.binary_path,
            "notes": self.notes,
        }


@dataclass(frozen=True)
class AssistantResult:
    provider: str
    model: str
    thinking: str
    latency_ms: int
    drafts: List[Dict[str, str]]
    notes: List[Dict[str, str]]
    actions: List[Dict[str, str]]
    raw_text: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "provider": self.provider,
            "model": self.model,
            "thinking": self.thinking,
            "latency_ms": self.latency_ms,
            "drafts": self.drafts,
            "notes": self.notes,
            "actions": self.actions,
            "raw_text": self.raw_text,
        }
