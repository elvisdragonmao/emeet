import asyncio
from typing import Optional

from fastapi import APIRouter, HTTPException, Query, Response
from pydantic import BaseModel

from meeting_backend.assistant.models import AssistantRequest, AssistantTranscriptLine
from meeting_backend.assistant.service import generate_assistant_response
from meeting_backend.config import get_settings
from meeting_backend.storage import MeetingStorage

router = APIRouter(prefix="/v1/meetings", tags=["meetings"])


class MeetingRenameBody(BaseModel):
    title: str


class MeetingGenerateTitleBody(BaseModel):
    provider: Optional[str] = None
    model: Optional[str] = None
    thinking: Optional[str] = None


@router.get("")
async def list_meetings(limit: int = Query(default=50, ge=1, le=200)):
    settings = get_settings()
    meetings = await asyncio.to_thread(
        MeetingStorage(settings.database_path).list_meetings,
        limit=limit,
    )
    return {"meetings": meetings}


@router.get("/{meeting_id}")
async def get_meeting_record(meeting_id: str):
    settings = get_settings()
    record = await asyncio.to_thread(MeetingStorage(settings.database_path).meeting_record, meeting_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Meeting not found")
    return record


@router.patch("/{meeting_id}")
async def rename_meeting(meeting_id: str, body: MeetingRenameBody):
    settings = get_settings()
    title = body.title.strip()
    if not title:
        raise HTTPException(status_code=400, detail="Meeting title cannot be empty")

    meeting = await asyncio.to_thread(
        MeetingStorage(settings.database_path).rename_meeting,
        meeting_id,
        title,
    )
    if meeting is None:
        raise HTTPException(status_code=404, detail="Meeting not found")
    return {"meeting": meeting}


@router.get("/{meeting_id}/export")
async def export_meeting(meeting_id: str):
    settings = get_settings()
    markdown = await asyncio.to_thread(MeetingStorage(settings.database_path).meeting_markdown, meeting_id)
    if markdown is None:
        raise HTTPException(status_code=404, detail="Meeting not found")
    return Response(markdown, media_type="text/markdown; charset=utf-8")


@router.post("/{meeting_id}/generate-title")
async def generate_meeting_title(meeting_id: str, body: MeetingGenerateTitleBody):
    settings = get_settings()
    storage = MeetingStorage(settings.database_path)
    record = await asyncio.to_thread(storage.meeting_record, meeting_id)
    if record is None:
        raise HTTPException(status_code=404, detail="Meeting not found")

    meeting = record["meeting"]
    if meeting.get("title_is_manual"):
        return {"meeting": meeting, "generated": False}

    request = AssistantRequest(
        action="meeting_title",
        meeting_id=meeting_id,
        provider=body.provider or settings.assistant_provider,
        model=body.model or settings.assistant_model,
        thinking=body.thinking or settings.assistant_thinking,
        temperature=settings.assistant_temperature,
        max_tokens=min(settings.assistant_max_tokens, 120),
        transcript=[
            AssistantTranscriptLine(
                source=str(line.get("source") or ""),
                source_label=str(line.get("speaker_label") or line.get("source") or ""),
                speaker_hint=str(line.get("speaker_hint") or ""),
                speaker_id=str(line.get("speaker_id") or ""),
                speaker_label=str(line.get("speaker_label") or ""),
                start_ms=int(line.get("start_ms") or 0),
                end_ms=int(line.get("end_ms") or 0),
                text=str(line.get("text") or ""),
                is_final=True,
            )
            for line in (record.get("transcript") or [])[-16:]
        ],
        previous_notes=record.get("notes") or [],
        previous_actions=record.get("actions") or [],
    )

    if not request.transcript and not request.previous_notes and not request.previous_actions:
        return {"meeting": meeting, "generated": False}

    try:
        result = await asyncio.to_thread(generate_assistant_response, settings, request)
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    generated_title = generated_title_from_result(result.drafts)
    if not generated_title:
        return {"meeting": meeting, "generated": False}

    updated_meeting = await asyncio.to_thread(
        storage.update_generated_meeting_title,
        meeting_id,
        generated_title,
    )
    if updated_meeting is None:
        raise HTTPException(status_code=404, detail="Meeting not found")
    return {"meeting": updated_meeting, "generated": updated_meeting.get("title") != meeting.get("title")}


def generated_title_from_result(drafts):
    for draft in drafts:
        title = str(draft.get("title") or "").strip()
        if title:
            return title
    return ""
