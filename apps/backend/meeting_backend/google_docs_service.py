import json
import os
import re
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple
from urllib.parse import parse_qs, urlparse

from meeting_backend.config import Settings


GOOGLE_DOCS_SCOPES = ["https://www.googleapis.com/auth/documents"]
LIVE_NOTES_TITLE = "emeet Live Notes"


@dataclass(frozen=True)
class TextIndexMapping:
    start_offset: int
    end_offset: int
    start_index: int
    end_index: int
    text: str


@dataclass(frozen=True)
class DocumentParagraph:
    start_offset: int
    end_offset: int
    start_index: int
    end_index: int
    text: str


@dataclass(frozen=True)
class DocumentHeading:
    text: str
    level: int
    start_offset: int
    end_offset: int
    start_index: int
    end_index: int

    def to_dict(self) -> Dict[str, Any]:
        return {
            "text": self.text,
            "level": self.level,
            "start_offset": self.start_offset,
            "end_offset": self.end_offset,
            "start_index": self.start_index,
            "end_index": self.end_index,
        }


@dataclass(frozen=True)
class DocumentSection:
    title: str
    level: int
    start_offset: int
    end_offset: int
    start_index: int
    end_index: int
    preview: str

    def to_dict(self) -> Dict[str, Any]:
        return {
            "title": self.title,
            "level": self.level,
            "start_offset": self.start_offset,
            "end_offset": self.end_offset,
            "start_index": self.start_index,
            "end_index": self.end_index,
            "preview": self.preview,
        }


@dataclass(frozen=True)
class DocumentSnapshot:
    document_id: str
    title: str
    revision_id: str
    plain_text: str
    mappings: List[TextIndexMapping]
    paragraphs: List[DocumentParagraph] = field(default_factory=list)
    headings: List[DocumentHeading] = field(default_factory=list)
    sections: List[DocumentSection] = field(default_factory=list)
    preview: str = ""
    end_index: int = 1

    def relevant_snippets(self, limit: int = 4) -> List[str]:
        snippets = [section.preview for section in self.sections if section.preview]
        if not snippets and self.preview:
            snippets = [self.preview]
        return snippets[:limit]

    def to_public_dict(self, *, include_plain_text: bool = False) -> Dict[str, Any]:
        payload = {
            "document_id": self.document_id,
            "title": self.title,
            "revision_id": self.revision_id,
            "preview": self.preview,
            "headings": [heading.to_dict() for heading in self.headings],
            "sections": [section.to_dict() for section in self.sections],
        }
        if include_plain_text:
            payload["plain_text"] = self.plain_text
        return payload


@dataclass(frozen=True)
class ReplacementRange:
    start_offset: int
    end_offset: int
    start_index: int
    end_index: int
    text: str


def extract_document_id(value: str) -> str:
    candidate = value.strip()
    if not candidate:
        raise ValueError("Google Docs URL is empty")

    if re.fullmatch(r"[A-Za-z0-9_-]{20,}", candidate):
        return candidate

    parsed = urlparse(candidate)
    match = re.search(r"/document/(?:u/\d+/)?d/([A-Za-z0-9_-]+)", parsed.path)
    if match:
        return match.group(1)

    query_id = parse_qs(parsed.query).get("id", [""])[0]
    if re.fullmatch(r"[A-Za-z0-9_-]{20,}", query_id):
        return query_id

    raise ValueError("Could not extract documentId from Google Docs URL")


class GoogleDocsService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def auth_status(self) -> Dict[str, Any]:
        return {
            "ready": self.is_token_configured(),
            "client_configured": os.path.exists(self.settings.google_oauth_client_path),
            "token_configured": os.path.exists(self.settings.google_token_path),
            "dependencies_available": google_dependencies_available(),
            "client_path": self.settings.google_oauth_client_path,
            "token_path": self.settings.google_token_path,
            "scopes": GOOGLE_DOCS_SCOPES,
        }

    def is_token_configured(self) -> bool:
        if not os.path.exists(self.settings.google_token_path):
            return False
        try:
            credentials = self._load_credentials()
        except Exception:
            return False
        return bool(
            credentials
            and (credentials.valid or (credentials.expired and credentials.refresh_token))
        )

    def authenticate_local(self) -> Dict[str, Any]:
        if not os.path.exists(self.settings.google_oauth_client_path):
            raise FileNotFoundError(
                "Google OAuth client JSON not found at {}".format(
                    self.settings.google_oauth_client_path
                )
            )

        credentials = self._load_credentials(allow_missing=True)
        if not credentials or not credentials.valid:
            if credentials and credentials.expired and credentials.refresh_token:
                self._refresh_credentials(credentials)
            else:
                credentials = self._run_local_oauth_flow()
            self._save_credentials(credentials)

        return self.auth_status()

    def build_client(self) -> Any:
        credentials = self._load_credentials()
        if not credentials.valid:
            if credentials.expired and credentials.refresh_token:
                self._refresh_credentials(credentials)
                self._save_credentials(credentials)
            else:
                raise RuntimeError("Google Docs OAuth token is not valid. Run /v1/google/auth/start.")

        return build_google_docs_client(credentials)

    def read_document(self, document_id: str, client: Any = None) -> DocumentSnapshot:
        client = client or self.build_client()
        document = client.documents().get(documentId=document_id).execute()
        return flatten_document(document_id, document)

    def batch_update(
        self,
        document_id: str,
        requests: List[Dict[str, Any]],
        *,
        revision_id: str = "",
        client: Any = None,
        write_control: str = "target",
    ) -> Dict[str, Any]:
        if not requests:
            raise ValueError("No Google Docs update requests were generated")

        body: Dict[str, Any] = {"requests": requests}
        control = build_write_control(revision_id, mode=write_control)
        if control:
            body["writeControl"] = control

        client = client or self.build_client()
        return client.documents().batchUpdate(documentId=document_id, body=body).execute()

    def append_text(self, document_id: str, text: str, *, client: Any = None) -> DocumentSnapshot:
        client = client or self.build_client()
        snapshot, _metadata = self._apply_snapshot_update(
            document_id,
            lambda snapshot: (build_append_text_requests(snapshot, text), None),
            client=client,
        )
        return snapshot

    def replace_text(
        self,
        document_id: str,
        find: str,
        replace: str,
        *,
        occurrence: str = "first",
        client: Any = None,
    ) -> Tuple[DocumentSnapshot, int]:
        client = client or self.build_client()
        snapshot, changed_count = self._apply_snapshot_update(
            document_id,
            lambda snapshot: build_replace_text_update(snapshot, find, replace, occurrence=occurrence),
            client=client,
        )
        return snapshot, int(changed_count or 0)

    def insert_text_under_heading(
        self,
        document_id: str,
        heading: str,
        text: str,
        *,
        client: Any = None,
    ) -> DocumentSnapshot:
        client = client or self.build_client()
        snapshot, _metadata = self._apply_snapshot_update(
            document_id,
            lambda snapshot: (build_insert_under_heading_requests(snapshot, heading, text), None),
            client=client,
        )
        return snapshot

    def rewrite_paragraph_containing_anchor(
        self,
        document_id: str,
        anchor: str,
        text: str,
        *,
        client: Any = None,
    ) -> DocumentSnapshot:
        client = client or self.build_client()
        snapshot, _metadata = self._apply_snapshot_update(
            document_id,
            lambda snapshot: (
                build_rewrite_paragraph_containing_anchor_requests(snapshot, anchor, text),
                None,
            ),
            client=client,
        )
        return snapshot

    def update_live_notes(
        self,
        document_id: str,
        live_notes_text: str,
        *,
        client: Any = None,
    ) -> DocumentSnapshot:
        client = client or self.build_client()
        snapshot, _metadata = self._apply_snapshot_update(
            document_id,
            lambda snapshot: (build_update_live_notes_requests(snapshot, live_notes_text), None),
            client=client,
        )
        return snapshot

    def _apply_snapshot_update(
        self,
        document_id: str,
        request_builder: Callable[[DocumentSnapshot], Tuple[List[Dict[str, Any]], Any]],
        *,
        client: Any,
    ) -> Tuple[DocumentSnapshot, Any]:
        snapshot = self.read_document(document_id, client=client)
        requests, metadata = request_builder(snapshot)
        try:
            self.batch_update(
                document_id,
                requests,
                revision_id=snapshot.revision_id,
                client=client,
            )
        except Exception as error:
            if not is_revision_conflict_error(error):
                raise
            snapshot = self.read_document(document_id, client=client)
            requests, metadata = request_builder(snapshot)
            self.batch_update(
                document_id,
                requests,
                revision_id=snapshot.revision_id,
                client=client,
            )
        return self.read_document(document_id, client=client), metadata

    def _load_credentials(self, *, allow_missing: bool = False) -> Any:
        if not os.path.exists(self.settings.google_token_path):
            if allow_missing:
                return None
            raise FileNotFoundError(
                "Google OAuth token not found at {}".format(self.settings.google_token_path)
            )

        credentials_cls = google_credentials_class()
        return credentials_cls.from_authorized_user_file(
            self.settings.google_token_path,
            GOOGLE_DOCS_SCOPES,
        )

    def _refresh_credentials(self, credentials: Any) -> None:
        request_cls = google_request_class()
        credentials.refresh(request_cls())

    def _run_local_oauth_flow(self) -> Any:
        flow_cls = google_installed_app_flow_class()
        flow = flow_cls.from_client_secrets_file(
            self.settings.google_oauth_client_path,
            GOOGLE_DOCS_SCOPES,
        )
        return flow.run_local_server(port=0)

    def _save_credentials(self, credentials: Any) -> None:
        directory = os.path.dirname(os.path.abspath(self.settings.google_token_path))
        os.makedirs(directory, exist_ok=True)
        with open(self.settings.google_token_path, "w", encoding="utf-8") as token_file:
            token_file.write(credentials.to_json())


def flatten_document(document_id: str, document: Dict[str, Any]) -> DocumentSnapshot:
    plain_parts: List[str] = []
    mappings: List[TextIndexMapping] = []
    paragraphs: List[DocumentParagraph] = []
    headings: List[DocumentHeading] = []
    body_content = document.get("body", {}).get("content") or []
    end_index = 1

    for structural in body_content:
        if structural.get("endIndex"):
            end_index = max(end_index, int(structural["endIndex"]))
        paragraph = structural.get("paragraph")
        if not paragraph:
            continue

        paragraph_start_offset = sum(len(part) for part in plain_parts)
        paragraph_start_index = int(structural.get("startIndex") or 1)
        paragraph_end_index = int(structural.get("endIndex") or paragraph_start_index)

        for element in paragraph.get("elements") or []:
            text_run = element.get("textRun") or {}
            content = text_run.get("content")
            if content is None:
                continue

            start_offset = sum(len(part) for part in plain_parts)
            plain_parts.append(content)
            end_offset = start_offset + len(content)
            mappings.append(
                TextIndexMapping(
                    start_offset=start_offset,
                    end_offset=end_offset,
                    start_index=int(element.get("startIndex") or paragraph_start_index),
                    end_index=int(element.get("endIndex") or paragraph_end_index),
                    text=content,
                )
            )

        paragraph_end_offset = sum(len(part) for part in plain_parts)
        paragraph_text = "".join(plain_parts)[paragraph_start_offset:paragraph_end_offset]
        if paragraph_text:
            paragraphs.append(
                DocumentParagraph(
                    start_offset=paragraph_start_offset,
                    end_offset=paragraph_end_offset,
                    start_index=paragraph_start_index,
                    end_index=paragraph_end_index,
                    text=paragraph_text,
                )
            )
        heading_level = heading_level_for_paragraph(paragraph)
        heading_text = paragraph_text.strip()
        if heading_level > 0 and heading_text:
            headings.append(
                DocumentHeading(
                    text=heading_text,
                    level=heading_level,
                    start_offset=paragraph_start_offset,
                    end_offset=paragraph_end_offset,
                    start_index=paragraph_start_index,
                    end_index=paragraph_end_index,
                )
            )

    plain_text = "".join(plain_parts)
    sections = build_sections(plain_text, headings, end_index)
    return DocumentSnapshot(
        document_id=document_id,
        title=str(document.get("title") or "Untitled Google Doc"),
        revision_id=str(document.get("revisionId") or ""),
        plain_text=plain_text,
        mappings=mappings,
        paragraphs=paragraphs,
        headings=headings,
        sections=sections,
        preview=build_preview(plain_text),
        end_index=end_index,
    )


def heading_level_for_paragraph(paragraph: Dict[str, Any]) -> int:
    style = paragraph.get("paragraphStyle") or {}
    named_style = str(style.get("namedStyleType") or "")
    match = re.fullmatch(r"HEADING_([1-6])", named_style)
    return int(match.group(1)) if match else 0


def build_sections(
    plain_text: str,
    headings: Sequence[DocumentHeading],
    document_end_index: int,
) -> List[DocumentSection]:
    sections: List[DocumentSection] = []
    for index, heading in enumerate(headings):
        next_heading = headings[index + 1] if index + 1 < len(headings) else None
        end_offset = next_heading.start_offset if next_heading else len(plain_text)
        end_index = next_heading.start_index if next_heading else max(1, document_end_index - 1)
        body = plain_text[heading.end_offset:end_offset]
        sections.append(
            DocumentSection(
                title=heading.text,
                level=heading.level,
                start_offset=heading.start_offset,
                end_offset=end_offset,
                start_index=heading.start_index,
                end_index=end_index,
                preview=build_preview(body),
            )
        )
    return sections


def build_preview(text: str, *, max_chars: int = 700) -> str:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    preview = "\n".join(lines)
    if len(preview) <= max_chars:
        return preview
    return preview[: max_chars - 1].rstrip() + "..."


def build_write_control(revision_id: str, *, mode: str = "target") -> Dict[str, str]:
    if not revision_id:
        return {}
    if mode == "required":
        return {"requiredRevisionId": revision_id}
    return {"targetRevisionId": revision_id}


def build_append_text_requests(snapshot: DocumentSnapshot, text: str) -> List[Dict[str, Any]]:
    insert_text = normalize_append_text(text)
    return [
        {
            "insertText": {
                "location": {"index": append_index(snapshot)},
                "text": insert_text,
            }
        }
    ]


def normalize_append_text(text: str) -> str:
    stripped = text.rstrip()
    if not stripped:
        raise ValueError("Append text is empty")
    prefix = "\n\n" if not stripped.startswith("\n") else ""
    return "{}{}\n".format(prefix, stripped)


def append_index(snapshot: DocumentSnapshot) -> int:
    return max(1, snapshot.end_index - 1)


def build_replace_text_requests(
    snapshot: DocumentSnapshot,
    find: str,
    replace: str,
    *,
    occurrence: str = "first",
) -> List[Dict[str, Any]]:
    find = validate_find_text(find)
    if occurrence == "all":
        return [
            {
                "replaceAllText": {
                    "containsText": {"text": find, "matchCase": True},
                    "replaceText": replace,
                }
            }
        ]

    ranges = calculate_replacement_ranges(snapshot, find, occurrence=occurrence)
    if not ranges:
        raise ValueError("Text was not found in the connected Google Doc")

    target = ranges[0]
    return [
        {
            "deleteContentRange": {
                "range": {
                    "startIndex": target.start_index,
                    "endIndex": target.end_index,
                }
            }
        },
        {
            "insertText": {
                "location": {"index": target.start_index},
                "text": replace,
            }
        },
    ]


def build_replace_text_update(
    snapshot: DocumentSnapshot,
    find: str,
    replace: str,
    *,
    occurrence: str = "first",
) -> Tuple[List[Dict[str, Any]], int]:
    requests = build_replace_text_requests(snapshot, find, replace, occurrence=occurrence)
    if occurrence == "all":
        return requests, snapshot.plain_text.count(validate_find_text(find))
    return requests, len(calculate_replacement_ranges(snapshot, find, occurrence=occurrence))


def calculate_replacement_ranges(
    snapshot: DocumentSnapshot,
    find: str,
    *,
    occurrence: str = "first",
) -> List[ReplacementRange]:
    find = validate_find_text(find)
    if occurrence not in {"first", "all"}:
        raise ValueError("occurrence must be first or all")

    ranges: List[ReplacementRange] = []
    start = 0
    while True:
        offset = snapshot.plain_text.find(find, start)
        if offset < 0:
            break
        end_offset = offset + len(find)
        ranges.append(
            ReplacementRange(
                start_offset=offset,
                end_offset=end_offset,
                start_index=offset_to_structural_index(snapshot, offset),
                end_index=offset_to_structural_index(snapshot, end_offset),
                text=find,
            )
        )
        if occurrence == "first":
            break
        start = end_offset

    return list(reversed(ranges)) if occurrence == "all" else ranges


def validate_find_text(find: str) -> str:
    find = find.strip()
    if not find:
        raise ValueError("Find text is empty")
    return find


def offset_to_structural_index(snapshot: DocumentSnapshot, offset: int) -> int:
    if offset < 0 or offset > len(snapshot.plain_text):
        raise ValueError("Text offset is outside the document snapshot")

    for mapping in snapshot.mappings:
        if mapping.start_offset <= offset < mapping.end_offset:
            prefix = snapshot.plain_text[mapping.start_offset:offset]
            return mapping.start_index + utf16_code_units(prefix)
        if offset == mapping.end_offset:
            return mapping.end_index

    if snapshot.mappings and offset == len(snapshot.plain_text):
        return snapshot.mappings[-1].end_index
    return append_index(snapshot)


def utf16_code_units(text: str) -> int:
    # Google Docs structural indices use UTF-16 code units. Python string offsets
    # count Unicode code points, so non-BMP characters need this conversion.
    return len(text.encode("utf-16-le")) // 2


def build_insert_under_heading_requests(
    snapshot: DocumentSnapshot,
    heading_text: str,
    text: str,
) -> List[Dict[str, Any]]:
    heading_text = validate_heading_text(heading_text)
    body = normalize_insert_text(text)
    heading = find_heading(snapshot, heading_text) or find_plain_text_heading(snapshot, heading_text)
    if not heading:
        return build_append_missing_heading_requests(snapshot, heading_text, body)

    insert_text = "\n{}\n".format(body)
    return [
        {
            "insertText": {
                "location": {"index": section_end_for_heading(snapshot, heading)},
                "text": insert_text,
            }
        }
    ]


def build_append_missing_heading_requests(
    snapshot: DocumentSnapshot,
    heading_text: str,
    text: str,
) -> List[Dict[str, Any]]:
    insert_at = append_index(snapshot)
    insert_text = normalize_append_text("{}\n\n{}".format(heading_text, text))
    prefix_units = utf16_code_units(insert_text) - utf16_code_units(insert_text.lstrip("\n"))
    heading_start = insert_at + prefix_units
    heading_end = heading_start + utf16_code_units(heading_text)
    return [
        {
            "insertText": {
                "location": {"index": insert_at},
                "text": insert_text,
            }
        },
        {
            "updateParagraphStyle": {
                "range": {"startIndex": heading_start, "endIndex": heading_end},
                "paragraphStyle": {"namedStyleType": "HEADING_1"},
                "fields": "namedStyleType",
            }
        },
    ]


def build_rewrite_paragraph_containing_anchor_requests(
    snapshot: DocumentSnapshot,
    anchor_text: str,
    text: str,
) -> List[Dict[str, Any]]:
    paragraph = paragraph_containing_anchor(snapshot, anchor_text)
    if paragraph is None:
        raise ValueError("Anchor text was not found in a single Google Doc paragraph")

    replacement = normalize_paragraph_rewrite_text(text)
    return [
        {
            "deleteContentRange": {
                "range": {
                    "startIndex": paragraph.start_index,
                    "endIndex": paragraph.end_index,
                }
            }
        },
        {
            "insertText": {
                "location": {"index": paragraph.start_index},
                "text": replacement,
            }
        },
    ]


def paragraph_containing_anchor(
    snapshot: DocumentSnapshot,
    anchor_text: str,
) -> Optional[DocumentParagraph]:
    anchor = validate_find_text(anchor_text)
    start_offset = snapshot.plain_text.find(anchor)
    if start_offset < 0:
        return None
    end_offset = start_offset + len(anchor)

    for paragraph in snapshot.paragraphs:
        if paragraph.start_offset <= start_offset and end_offset <= paragraph.end_offset:
            return paragraph
    return None


def normalize_insert_text(text: str) -> str:
    stripped = text.strip()
    if not stripped:
        raise ValueError("Insert text is empty")
    return stripped


def normalize_paragraph_rewrite_text(text: str) -> str:
    stripped = text.strip()
    if not stripped:
        raise ValueError("Replacement paragraph is empty")
    return stripped + "\n"


def validate_heading_text(heading_text: str) -> str:
    heading = heading_text.strip()
    if not heading:
        raise ValueError("Heading text is empty")
    return heading


def build_update_live_notes_requests(
    snapshot: DocumentSnapshot,
    live_notes_text: str,
) -> List[Dict[str, Any]]:
    body = live_notes_text.strip()
    if not body:
        raise ValueError("Live notes text is empty")

    heading = find_heading(snapshot, LIVE_NOTES_TITLE) or find_plain_text_heading(snapshot, LIVE_NOTES_TITLE)
    if not heading:
        insert_at = append_index(snapshot)
        title_text = "{}\n\n".format(LIVE_NOTES_TITLE)
        insert_text = "\n\n{}{}\n".format(title_text, body)
        title_start = insert_at + 2
        title_end = title_start + utf16_code_units(LIVE_NOTES_TITLE)
        return [
            {
                "insertText": {
                    "location": {"index": insert_at},
                    "text": insert_text,
                }
            },
            {
                "updateParagraphStyle": {
                    "range": {"startIndex": title_start, "endIndex": title_end},
                    "paragraphStyle": {"namedStyleType": "HEADING_1"},
                    "fields": "namedStyleType",
                }
            },
        ]

    section_end_index = section_end_for_heading(snapshot, heading)
    replacement = "\n{}\n".format(body)
    requests: List[Dict[str, Any]] = []
    if section_end_index > heading.end_index:
        requests.append(
            {
                "deleteContentRange": {
                    "range": {
                        "startIndex": heading.end_index,
                        "endIndex": section_end_index,
                    }
                }
            }
        )
    requests.append(
        {
            "insertText": {
                "location": {"index": heading.end_index},
                "text": replacement,
            }
        }
    )
    return requests


def find_heading(snapshot: DocumentSnapshot, heading_text: str) -> Optional[DocumentHeading]:
    normalized = normalize_heading_text(heading_text)
    for heading in snapshot.headings:
        if normalize_heading_text(heading.text) == normalized:
            return heading
    return None


def find_plain_text_heading(snapshot: DocumentSnapshot, heading_text: str) -> Optional[DocumentHeading]:
    normalized = normalize_heading_text(heading_text)
    for line in re.finditer(r"(^|\n)([^\n]+)", snapshot.plain_text):
        text = line.group(2).strip()
        if normalize_heading_text(text) != normalized:
            continue
        start_offset = line.start(2)
        end_offset = line.end(2)
        return DocumentHeading(
            text=text,
            level=1,
            start_offset=start_offset,
            end_offset=end_offset,
            start_index=offset_to_structural_index(snapshot, start_offset),
            end_index=offset_to_structural_index(snapshot, min(end_offset + 1, len(snapshot.plain_text))),
        )
    return None


def section_end_for_heading(snapshot: DocumentSnapshot, heading: DocumentHeading) -> int:
    for candidate in snapshot.headings:
        if candidate.start_index > heading.start_index and candidate.level <= heading.level:
            return candidate.start_index
    return append_index(snapshot)


def normalize_heading_text(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip()).lower()


def format_meeting_notes_append(
    *,
    title: str,
    notes: Sequence[Dict[str, str]],
    actions: Sequence[Dict[str, str]],
    transcript: Sequence[Dict[str, Any]] = (),
) -> str:
    lines = ["# emeet Meeting Notes", ""]
    if title:
        lines.extend(["Source document: {}".format(title), ""])

    lines.extend(["## Notes", ""])
    if notes:
        for note in notes:
            lines.append("### {}".format(note.get("title") or "Note"))
            detail = str(note.get("detail") or "").strip()
            lines.append(detail or "_No detail._")
            lines.append("")
    else:
        lines.extend(["_No meeting notes yet._", ""])

    lines.extend(["## Next Actions", ""])
    if actions:
        for action in actions:
            owner = action.get("owner") or "Unassigned"
            state = action.get("state") or "Draft"
            lines.append("- [ ] {}  ".format(action.get("title") or "Next action"))
            lines.append("  Owner: {}  ".format(owner))
            lines.append("  State: {}".format(state))
    else:
        lines.append("_No next actions yet._")

    if transcript:
        lines.extend(["", "## Transcript Evidence", ""])
        for line in transcript[-12:]:
            speaker = line.get("speaker_label") or line.get("source_label") or line.get("source") or "Unknown"
            text = str(line.get("text") or "").strip()
            if text:
                lines.append("- **{}**: {}".format(speaker, text))

    return "\n".join(lines).rstrip() + "\n"


def google_dependencies_available() -> bool:
    try:
        google_credentials_class()
        google_request_class()
        google_installed_app_flow_class()
        from googleapiclient.discovery import build as _build

        _build
    except Exception:
        return False
    return True


def google_credentials_class() -> Any:
    from google.oauth2.credentials import Credentials

    return Credentials


def google_request_class() -> Any:
    from google.auth.transport.requests import Request

    return Request


def google_installed_app_flow_class() -> Any:
    from google_auth_oauthlib.flow import InstalledAppFlow

    return InstalledAppFlow


def build_google_docs_client(credentials: Any) -> Any:
    from googleapiclient.discovery import build

    return build("docs", "v1", credentials=credentials)


def is_revision_conflict_error(error: Exception) -> bool:
    status = getattr(getattr(error, "resp", None), "status", None)
    if status in {400, 409, 412}:
        text = error_text(error).lower()
        return any(
            marker in text
            for marker in (
                "revision",
                "writecontrol",
                "write control",
                "targetrevisionid",
                "requiredrevisionid",
                "conflict",
                "precondition",
            )
        )
    return False


def error_text(error: Exception) -> str:
    content = getattr(error, "content", b"")
    if isinstance(content, bytes):
        content_text = content.decode("utf-8", errors="replace")
    else:
        content_text = str(content or "")

    try:
        parsed = json.loads(content_text)
        if isinstance(parsed, dict):
            return json.dumps(parsed, ensure_ascii=False)
    except Exception:
        pass

    return "{} {}".format(str(error), content_text)
