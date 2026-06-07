import time
from typing import Any, Dict, List


def normalize_meeting_title(title: str) -> str:
    normalized = " ".join(title.replace("#", " ").split()).strip(" \"'`")
    if not normalized:
        return ""
    if len(normalized) <= 80:
        return normalized
    return normalized[:77].rstrip() + "..."


def title_from_transcript(text: str) -> str:
    normalized = " ".join(text.split())
    if not normalized:
        return ""
    if len(normalized) <= 64:
        return normalized
    return normalized[:61].rstrip() + "..."


def meeting_record_markdown(record: Dict[str, Any]) -> str:
    meeting = record.get("meeting") or {}
    lines: List[str] = ["# {}".format(meeting.get("title") or "Meeting Record"), ""]
    if meeting.get("started_at_ms"):
        lines.append("- Started: {}".format(display_time_ms(int(meeting["started_at_ms"]))))
    if meeting.get("ended_at_ms"):
        lines.append("- Ended: {}".format(display_time_ms(int(meeting["ended_at_ms"]))))
    if meeting.get("stt_provider") or meeting.get("stt_model"):
        lines.append("- STT: {} / {}".format(meeting.get("stt_provider") or "", meeting.get("stt_model") or ""))
    if meeting.get("assistant_provider") or meeting.get("assistant_model"):
        lines.append(
            "- Assistant: {} / {}".format(
                meeting.get("assistant_provider") or "",
                meeting.get("assistant_model") or "",
            )
        )
    lines.append("")

    lines.extend(["## Meeting Notes", ""])
    notes = record.get("notes") or []
    if not notes:
        lines.append("_No meeting notes yet._")
    else:
        for note in notes:
            lines.append("### {}".format(note.get("title") or "Note"))
            lines.append(str(note.get("detail") or ""))
            lines.append("")

    lines.extend(["", "## Next Actions", ""])
    actions = record.get("actions") or []
    if not actions:
        lines.append("_No next actions yet._")
    else:
        for action in actions:
            lines.append("- [ ] {}  ".format(action.get("title") or "Next action"))
            lines.append("  Owner: {}  ".format(action.get("owner") or "Unassigned"))
            lines.append("  State: {}".format(action.get("state") or "Draft"))

    lines.extend(["", "## AI Suggestions", ""])
    assistant_responses = record.get("assistant_responses") or []
    if not assistant_responses:
        lines.append("_No assistant suggestions yet._")
    else:
        for response in assistant_responses:
            lines.append("### {}".format(str(response.get("action") or "").replace("_", " ").title()))
            lines.append("- Provider: {} / {}".format(response.get("provider") or "", response.get("model") or ""))
            for suggestion in response.get("suggestions") or []:
                lines.append("- **{}**: {}".format(suggestion.get("title") or "Suggestion", suggestion.get("detail") or ""))
            lines.append("")

    lines.extend(["## Transcript", ""])
    transcript = record.get("transcript") or []
    if not transcript:
        lines.append("_No transcript yet._")
    else:
        for line in transcript:
            speaker = line.get("speaker_label") or line.get("speaker_hint") or line.get("source") or "Unknown"
            lines.append(
                "- `{} - {}` **{}**: {}".format(
                    display_duration_ms(int(line.get("start_ms") or 0)),
                    display_duration_ms(int(line.get("end_ms") or 0)),
                    speaker,
                    line.get("text") or "",
                )
            )

    lines.append("")
    return "\n".join(lines)


def display_time_ms(milliseconds: int) -> str:
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(milliseconds / 1000))


def display_duration_ms(milliseconds: int) -> str:
    total_seconds = max(0, milliseconds // 1000)
    minutes = total_seconds // 60
    seconds = total_seconds % 60
    return "{:02d}:{:02d}".format(minutes, seconds)
