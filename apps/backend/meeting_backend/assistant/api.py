import asyncio
from typing import List, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from meeting_backend.assistant.models import AssistantRequest, AssistantTranscriptLine
from meeting_backend.assistant.service import generate_assistant_response, list_provider_descriptors
from meeting_backend.config import get_settings

router = APIRouter(prefix="/v1/assistant", tags=["assistant"])


class AssistantTranscriptLineBody(BaseModel):
    source: str = ""
    source_label: str = ""
    speaker_hint: str = ""
    start_ms: int = 0
    end_ms: int = 0
    text: str
    is_final: bool = True


class AssistantRespondBody(BaseModel):
    action: str = Field(default="what_should_i_say")
    provider: Optional[str] = None
    model: Optional[str] = None
    thinking: Optional[str] = None
    transcript: List[AssistantTranscriptLineBody] = Field(default_factory=list)
    temperature: Optional[float] = None
    max_tokens: Optional[int] = None


@router.get("/providers")
async def providers():
    settings = get_settings()
    return await asyncio.to_thread(list_provider_descriptors, settings)


@router.post("/respond")
async def respond(body: AssistantRespondBody):
    settings = get_settings()
    request = AssistantRequest(
        action=body.action,
        provider=body.provider or settings.assistant_provider,
        model=body.model or settings.assistant_model,
        thinking=body.thinking or settings.assistant_thinking,
        transcript=[
            AssistantTranscriptLine(
                source=line.source,
                source_label=line.source_label,
                speaker_hint=line.speaker_hint,
                start_ms=line.start_ms,
                end_ms=line.end_ms,
                text=line.text,
                is_final=line.is_final,
            )
            for line in body.transcript
        ],
        temperature=settings.assistant_temperature if body.temperature is None else body.temperature,
        max_tokens=settings.assistant_max_tokens if body.max_tokens is None else body.max_tokens,
    )
    try:
        result = await asyncio.to_thread(generate_assistant_response, settings, request)
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    return result.to_dict()
