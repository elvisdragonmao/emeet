import asyncio
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from meeting_backend.assistant.models import AssistantRequest
from meeting_backend.assistant.service import generate_assistant_response
from meeting_backend.browser_controller import BrowserController
from meeting_backend.config import get_settings
from meeting_backend.google_docs_context import (
    GOOGLE_DOC_CONNECTIONS,
    GoogleDocMeetingConnection,
)
from meeting_backend.google_docs_service import (
    DocumentSnapshot,
    GoogleDocsService,
    extract_document_id,
    format_meeting_notes_append,
)
from meeting_backend.storage import MeetingStorage


router = APIRouter(prefix="/v1/google", tags=["google-docs"])


class GoogleConnectBody(BaseModel):
    url: str
    meeting_id: str = ""
    provider: Optional[str] = None
    model: Optional[str] = None
    thinking: Optional[str] = None


class GoogleMeetingBody(BaseModel):
    meeting_id: str = ""
    document_id: str = ""


class GoogleAppendBody(GoogleMeetingBody):
    text: str


class GoogleReplaceTextBody(GoogleMeetingBody):
    find: str
    replace: str
    occurrence: str = "first"


class GoogleInsertUnderHeadingBody(GoogleMeetingBody):
    heading: str
    text: str


class GoogleRewriteParagraphBody(GoogleMeetingBody):
    anchor: str
    text: str


class GoogleBrowserOpenBody(GoogleMeetingBody):
    url: str = ""


class GoogleBrowserFindBody(GoogleMeetingBody):
    text: str


class GoogleAppendMeetingNotesBody(GoogleMeetingBody):
    notes: List[Dict[str, str]] = Field(default_factory=list)
    actions: List[Dict[str, str]] = Field(default_factory=list)
    transcript: List[Dict[str, Any]] = Field(default_factory=list)


class GoogleUpdateLiveNotesBody(GoogleAppendMeetingNotesBody):
    pass


@router.get("/auth/status")
async def google_auth_status():
    settings = get_settings()
    service = GoogleDocsService(settings)
    return await asyncio.to_thread(service.auth_status)


@router.post("/auth/start")
async def google_auth_start():
    settings = get_settings()
    service = GoogleDocsService(settings)
    try:
        return await asyncio.to_thread(service.authenticate_local)
    except FileNotFoundError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error


@router.post("/docs/connect")
async def google_docs_connect(body: GoogleConnectBody):
    settings = get_settings()
    service = GoogleDocsService(settings)
    try:
        document_id = extract_document_id(body.url)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error

    try:
        snapshot = await asyncio.to_thread(service.read_document, document_id)
    except FileNotFoundError as error:
        raise HTTPException(status_code=401, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    briefing_text = ""
    briefing_notes: List[Dict[str, str]] = []
    briefing_actions: List[Dict[str, str]] = []
    briefing_error = ""
    try:
        result = await asyncio.to_thread(
            generate_document_briefing,
            settings,
            body,
            snapshot,
        )
        briefing_notes = result.notes
        briefing_actions = result.actions
        briefing_text = document_briefing_text(result.notes, result.actions)
    except Exception as error:
        briefing_error = str(error)

    connection = GoogleDocMeetingConnection(
        meeting_id=body.meeting_id,
        snapshot=snapshot,
        document_briefing=briefing_text,
        briefing_notes=briefing_notes,
        briefing_actions=briefing_actions,
        briefing_error=briefing_error,
    )
    GOOGLE_DOC_CONNECTIONS.set(connection)
    return snapshot_response(connection)


@router.post("/docs/refresh")
async def google_docs_refresh(body: GoogleMeetingBody):
    settings = get_settings()
    service = GoogleDocsService(settings)
    connection = connection_for_body(body)
    document_id = body.document_id or connection.snapshot.document_id
    try:
        snapshot = await asyncio.to_thread(service.read_document, document_id)
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    updated = GOOGLE_DOC_CONNECTIONS.update_snapshot(body.meeting_id, snapshot)
    return snapshot_response(updated)


@router.post("/docs/append")
async def google_docs_append(body: GoogleAppendBody):
    service = GoogleDocsService(get_settings())
    connection = connection_for_body(body)
    document_id = body.document_id or connection.snapshot.document_id
    try:
        snapshot = await asyncio.to_thread(service.append_text, document_id, body.text)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    updated = GOOGLE_DOC_CONNECTIONS.update_snapshot(body.meeting_id, snapshot)
    return write_response(updated, "Text appended to Google Doc.")


@router.post("/docs/replace-text")
async def google_docs_replace_text(body: GoogleReplaceTextBody):
    service = GoogleDocsService(get_settings())
    connection = connection_for_body(body)
    document_id = body.document_id or connection.snapshot.document_id
    try:
        snapshot, changed_count = await asyncio.to_thread(
            service.replace_text,
            document_id,
            body.find,
            body.replace,
            occurrence=body.occurrence,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    updated = GOOGLE_DOC_CONNECTIONS.update_snapshot(body.meeting_id, snapshot)
    return write_response(updated, "Replaced {} occurrence(s).".format(changed_count))


@router.post("/docs/insert-under-heading")
async def google_docs_insert_under_heading(body: GoogleInsertUnderHeadingBody):
    service = GoogleDocsService(get_settings())
    connection = connection_for_body(body)
    document_id = body.document_id or connection.snapshot.document_id
    try:
        snapshot = await asyncio.to_thread(
            service.insert_text_under_heading,
            document_id,
            body.heading,
            body.text,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    updated = GOOGLE_DOC_CONNECTIONS.update_snapshot(body.meeting_id, snapshot)
    return write_response(updated, "Inserted text under heading.")


@router.post("/docs/rewrite-paragraph")
async def google_docs_rewrite_paragraph(body: GoogleRewriteParagraphBody):
    service = GoogleDocsService(get_settings())
    connection = connection_for_body(body)
    document_id = body.document_id or connection.snapshot.document_id
    try:
        snapshot = await asyncio.to_thread(
            service.rewrite_paragraph_containing_anchor,
            document_id,
            body.anchor,
            body.text,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    updated = GOOGLE_DOC_CONNECTIONS.update_snapshot(body.meeting_id, snapshot)
    return write_response(updated, "Rewrote paragraph containing anchor text.")


@router.post("/docs/append-meeting-notes")
async def google_docs_append_meeting_notes(body: GoogleAppendMeetingNotesBody):
    settings = get_settings()
    service = GoogleDocsService(settings)
    connection = connection_for_body(body)
    notes, actions = meeting_record_from_body_or_storage(settings, body)
    text = format_meeting_notes_append(
        title=connection.snapshot.title,
        notes=notes,
        actions=actions,
        transcript=body.transcript,
    )
    try:
        snapshot = await asyncio.to_thread(
            service.append_text,
            body.document_id or connection.snapshot.document_id,
            text,
        )
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    updated = GOOGLE_DOC_CONNECTIONS.update_snapshot(body.meeting_id, snapshot)
    return write_response(updated, "Meeting notes appended to Google Doc.")


@router.post("/docs/update-live-notes")
async def google_docs_update_live_notes(body: GoogleUpdateLiveNotesBody):
    settings = get_settings()
    service = GoogleDocsService(settings)
    connection = connection_for_body(body)
    notes, actions = meeting_record_from_body_or_storage(settings, body)
    text = format_meeting_notes_append(
        title=connection.snapshot.title,
        notes=notes,
        actions=actions,
        transcript=body.transcript,
    )
    try:
        snapshot = await asyncio.to_thread(
            service.update_live_notes,
            body.document_id or connection.snapshot.document_id,
            text,
        )
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=502, detail=str(error)) from error

    updated = GOOGLE_DOC_CONNECTIONS.update_snapshot(body.meeting_id, snapshot)
    return write_response(updated, "emeet Live Notes updated.")


@router.get("/browser/status")
async def google_browser_status():
    return await asyncio.to_thread(BrowserController().status)


@router.post("/browser/open")
async def google_browser_open(body: GoogleBrowserOpenBody):
    try:
        url = body.url or google_doc_url_for_body(body)
        return await asyncio.to_thread(BrowserController().open_url, url)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=503, detail=str(error)) from error


@router.post("/browser/scroll-bottom")
async def google_browser_scroll_bottom(_body: GoogleMeetingBody):
    try:
        return await asyncio.to_thread(BrowserController().scroll_to_bottom)
    except Exception as error:
        raise HTTPException(status_code=503, detail=str(error)) from error


@router.post("/browser/find-visible-text")
async def google_browser_find_visible_text(body: GoogleBrowserFindBody):
    try:
        return await asyncio.to_thread(BrowserController().find_visible_text, body.text)
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    except Exception as error:
        raise HTTPException(status_code=503, detail=str(error)) from error


def generate_document_briefing(
    settings: Any,
    body: GoogleConnectBody,
    snapshot: DocumentSnapshot,
) -> Any:
    request = AssistantRequest(
        action="document_briefing",
        meeting_id=body.meeting_id,
        provider=body.provider or settings.assistant_provider,
        model=body.model or settings.assistant_model,
        thinking=body.thinking or settings.assistant_thinking,
        transcript=[],
        rolling_summary="",
        previous_notes=[],
        previous_actions=[],
        temperature=settings.assistant_temperature,
        max_tokens=settings.assistant_max_tokens,
        document_title=snapshot.title,
        document_summary=snapshot.preview,
        document_snippets=document_briefing_snippets(snapshot),
    )
    return generate_assistant_response(settings, request)


def document_briefing_snippets(snapshot: DocumentSnapshot) -> List[str]:
    snippets = snapshot.relevant_snippets(limit=6)
    if snippets:
        return snippets
    if snapshot.plain_text:
        return [snapshot.plain_text[:5000]]
    return []


def document_briefing_text(notes: List[Dict[str, str]], actions: List[Dict[str, str]]) -> str:
    lines: List[str] = []
    for note in notes:
        title = note.get("title") or "Document note"
        detail = note.get("detail") or ""
        lines.append("{}: {}".format(title, detail).strip())
    if actions:
        lines.append("Actions:")
        for action in actions:
            lines.append(
                "- {} / owner={} / state={}".format(
                    action.get("title") or "Next action",
                    action.get("owner") or "Unassigned",
                    action.get("state") or "Draft",
                )
            )
    return "\n".join(lines)


def connection_for_body(body: GoogleMeetingBody) -> GoogleDocMeetingConnection:
    connection = GOOGLE_DOC_CONNECTIONS.get(body.meeting_id)
    if not connection:
        raise HTTPException(status_code=404, detail="No Google Doc is connected to this meeting")
    return connection


def google_doc_url_for_body(body: GoogleMeetingBody) -> str:
    connection = connection_for_body(body)
    return "https://docs.google.com/document/d/{}/edit".format(connection.snapshot.document_id)


def meeting_record_from_body_or_storage(
    settings: Any,
    body: GoogleAppendMeetingNotesBody,
) -> tuple[List[Dict[str, str]], List[Dict[str, str]]]:
    notes = body.notes
    actions = body.actions
    if (notes or actions) or not body.meeting_id:
        return notes, actions

    record = MeetingStorage(settings.database_path).latest_meeting_record(body.meeting_id)
    return record["notes"], record["actions"]


def snapshot_response(connection: GoogleDocMeetingConnection) -> Dict[str, Any]:
    payload = connection.snapshot.to_public_dict(include_plain_text=True)
    payload.update(
        {
            "connected": True,
            "meeting_id": connection.meeting_id,
            "document_briefing": connection.document_briefing,
            "briefing_notes": connection.briefing_notes,
            "briefing_actions": connection.briefing_actions,
            "briefing_error": connection.briefing_error,
            "snippets": connection.snapshot.relevant_snippets(),
        }
    )
    return payload


def write_response(connection: GoogleDocMeetingConnection, message: str) -> Dict[str, Any]:
    payload = snapshot_response(connection)
    payload.update({"status": "ok", "message": message})
    return payload
