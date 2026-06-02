from dataclasses import dataclass
from typing import Dict, List

from meeting_backend.assistant.models import AssistantRequest, AssistantTranscriptLine


OUTPUT_CONTRACT = (
    "Return compact JSON only. The JSON object must contain keys drafts, notes, and actions. "
    "drafts is an array of objects with title, detail, badge, icon_name. "
    "notes is an array of objects with title and detail. "
    "actions is an array of objects with title, owner, and state. "
    "Use empty arrays when a section is not relevant."
)


BASE_SYSTEM_PROMPT = (
    "You are a real-time meeting assistant. Use only the transcript context. "
    "Do not invent facts, owners, dates, budgets, approvals, or commitments. "
    "If information was not stated, keep it unassigned or mark it as draft."
)


@dataclass(frozen=True)
class PromptTemplate:
    action: str
    system: str
    instruction: str


PROMPT_TEMPLATES: Dict[str, PromptTemplate] = {
    "what_should_i_say": PromptTemplate(
        action="what_should_i_say",
        system=BASE_SYSTEM_PROMPT,
        instruction=(
            "Generate 2-3 concise, natural response suggestions the user can say next. "
            "Prefer short spoken Chinese unless the transcript is clearly English. "
            "The response should be conservative and should not commit to dates, budgets, or ownership."
        ),
    ),
    "follow_up_questions": PromptTemplate(
        action="follow_up_questions",
        system=BASE_SYSTEM_PROMPT,
        instruction=(
            "Generate 3 practical follow-up questions. Prioritize questions that clarify goals, "
            "constraints, ownership, timeline, risks, or decision criteria."
        ),
    ),
    "meeting_notes": PromptTemplate(
        action="meeting_notes",
        system=BASE_SYSTEM_PROMPT,
        instruction=(
            "Generate a structured meeting record, not a one-sentence summary. "
            "Use the notes array as fixed meeting-record sections with these titles when applicable: "
            "討論主題與內容, 目前結論, 待討論事項, 未解決問題. "
            "Each note detail should be 2-5 concise bullet points separated by newlines when enough context exists. "
            "Use the actions array for CTA / next actions only. Each action should include the task, owner if stated "
            "or Unassigned if not stated, and a state such as Draft, Confirmed, Waiting, or Blocked. "
            "Do not guess owners, due dates, conclusions, or commitments that were not stated."
        ),
    ),
    "chat": PromptTemplate(
        action="chat",
        system=BASE_SYSTEM_PROMPT,
        instruction=(
            "Answer the user's meeting-context question using the transcript only. "
            "If the transcript does not contain enough evidence, say what is missing."
        ),
    ),
}


def build_messages(request: AssistantRequest) -> List[Dict[str, str]]:
    template = prompt_template_for_action(request.action)
    transcript = transcript_context(request.transcript)
    user = (
        "Action: {action}\n"
        "Thinking setting requested by user: {thinking}\n"
        "Instruction: {instruction}\n\n"
        "Transcript:\n{transcript}\n\n"
        "{output_contract}"
    ).format(
        action=request.action,
        thinking=request.thinking,
        instruction=template.instruction,
        transcript=transcript,
        output_contract=OUTPUT_CONTRACT,
    )
    return [
        {"role": "system", "content": "{} {}".format(template.system, OUTPUT_CONTRACT)},
        {"role": "user", "content": user},
    ]


def prompt_template_for_action(action: str) -> PromptTemplate:
    return PROMPT_TEMPLATES.get(action, PROMPT_TEMPLATES["chat"])


def transcript_context(lines: List[AssistantTranscriptLine]) -> str:
    if not lines:
        return "(No transcript yet.)"

    formatted = []
    for line in lines[-16:]:
        source = line.source_label or line.source or "Unknown"
        status = "final" if line.is_final else "partial"
        formatted.append("[{} {}-{} {}] {}".format(source, line.start_ms, line.end_ms, status, line.text))
    return "\n".join(formatted)
