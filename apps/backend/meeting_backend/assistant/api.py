import asyncio
from typing import List, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from meeting_backend.assistant.models import AssistantRequest, AssistantTranscriptLine
from meeting_backend.assistant.service import generate_assistant_response, list_provider_descriptors
from meeting_backend.config import get_settings
from meeting_backend.google_docs_context import GOOGLE_DOC_CONNECTIONS
from meeting_backend.storage import MeetingStorage

router = APIRouter(prefix="/v1/assistant", tags=["assistant"])


class AssistantTranscriptLineBody(BaseModel):
    source: str = ""
    source_label: str = ""
    speaker_hint: str = ""
    speaker_id: str = ""
    speaker_label: str = ""
    start_ms: int = 0
    end_ms: int = 0
    text: str
    is_final: bool = True


class MeetingNoteBody(BaseModel):
    title: str = ""
    detail: str = ""


class MeetingActionBody(BaseModel):
    title: str = ""
    owner: str = ""
    state: str = ""


class AssistantRespondBody(BaseModel):
    action: str = Field(default="what_should_i_say")
    meeting_id: str = ""
    provider: Optional[str] = None
    model: Optional[str] = None
    thinking: Optional[str] = None
    transcript: List[AssistantTranscriptLineBody] = Field(default_factory=list)
    rolling_summary: str = ""
    previous_notes: List[MeetingNoteBody] = Field(default_factory=list)
    previous_actions: List[MeetingActionBody] = Field(default_factory=list)
    document_title: str = ""
    document_summary: str = ""
    document_snippets: List[str] = Field(default_factory=list)
    document_briefing: str = ""
    temperature: Optional[float] = None
    max_tokens: Optional[int] = None


@router.get("/providers")
async def providers():
    settings = get_settings()
    return await asyncio.to_thread(list_provider_descriptors, settings)


@router.post("/respond")
async def respond(body: AssistantRespondBody):
    settings = get_settings()
    document_title = body.document_title
    document_summary = body.document_summary
    document_snippets = body.document_snippets
    document_briefing = body.document_briefing
    if body.meeting_id and not (document_title or document_summary or document_snippets or document_briefing):
        connection = GOOGLE_DOC_CONNECTIONS.get(body.meeting_id)
        if connection:
            document_title = connection.snapshot.title
            document_summary = connection.snapshot.preview
            document_snippets = connection.snapshot.relevant_snippets()
            document_briefing = connection.document_briefing

    request = AssistantRequest(
        action=body.action,
        meeting_id=body.meeting_id,
        provider=body.provider or settings.assistant_provider,
        model=body.model or settings.assistant_model,
        thinking=body.thinking or settings.assistant_thinking,
        transcript=[
            AssistantTranscriptLine(
                source=line.source,
                source_label=line.source_label,
                speaker_hint=line.speaker_hint,
                speaker_id=line.speaker_id,
                speaker_label=line.speaker_label,
                start_ms=line.start_ms,
                end_ms=line.end_ms,
                text=line.text,
                is_final=line.is_final,
            )
            for line in body.transcript
        ],
        temperature=settings.assistant_temperature if body.temperature is None else body.temperature,
        max_tokens=settings.assistant_max_tokens if body.max_tokens is None else body.max_tokens,
        rolling_summary=body.rolling_summary,
        previous_notes=[
            {
                "title": item.title,
                "detail": item.detail,
            }
            for item in body.previous_notes
        ],
        previous_actions=[
            {
                "title": item.title,
                "owner": item.owner,
                "state": item.state,
            }
            for item in body.previous_actions
        ],
        document_title=document_title,
        document_summary=document_summary,
        document_snippets=document_snippets,
        document_briefing=document_briefing,
    )
    try:
        result = await asyncio.to_thread(generate_assistant_response, settings, request)
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    await asyncio.to_thread(MeetingStorage(settings.database_path).record_assistant_result, request, result)
    return result.to_dict()
