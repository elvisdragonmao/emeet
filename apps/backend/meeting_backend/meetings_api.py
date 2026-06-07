import asyncio

from fastapi import APIRouter, HTTPException, Query

from meeting_backend.config import get_settings
from meeting_backend.storage import MeetingStorage

router = APIRouter(prefix="/v1/meetings", tags=["meetings"])


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
