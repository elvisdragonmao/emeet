import unittest

from meeting_backend.assistant.models import AssistantRequest, AssistantTranscriptLine
from meeting_backend.assistant.prompts import build_messages, prompt_template_for_action


class AssistantPromptsTest(unittest.TestCase):
    def test_exposes_separate_templates_for_core_actions(self) -> None:
        self.assertIn("say next", prompt_template_for_action("what_should_i_say").instruction)
        self.assertIn("follow-up questions", prompt_template_for_action("follow_up_questions").instruction)
        self.assertIn("structured meeting record", prompt_template_for_action("meeting_notes").instruction)
        self.assertIn("討論主題與內容", prompt_template_for_action("meeting_notes").instruction)
        self.assertIn("meeting-context question", prompt_template_for_action("chat").instruction)
        self.assertIn("explicit spoken command addressed to AI", prompt_template_for_action("document_edit_plan").instruction)
        self.assertIn("saved-meeting title", prompt_template_for_action("meeting_title").instruction)

    def test_build_messages_includes_transcript_and_output_contract(self) -> None:
        request = AssistantRequest(
            action="meeting_notes",
            provider="ollama",
            model="fast",
            thinking="high",
            temperature=0.2,
            max_tokens=700,
            transcript=[
                AssistantTranscriptLine(
                        source="system",
                        source_label="Other",
                        speaker_hint="other",
                        speaker_id="speaker_1",
                        speaker_label="Speaker 1",
                        start_ms=100,
                    end_ms=900,
                    text="Please confirm the launch checklist.",
                    is_final=True,
                )
            ],
        )

        messages = build_messages(request)

        self.assertEqual(messages[0]["role"], "system")
        self.assertEqual(messages[1]["role"], "user")
        self.assertIn("structured meeting record", messages[1]["content"])
        self.assertIn("未解決問題", messages[1]["content"])
        self.assertIn("Please confirm the launch checklist.", messages[1]["content"])
        self.assertIn("Speaker 1", messages[1]["content"])
        self.assertIn("drafts, notes, and actions", messages[1]["content"])

    def test_build_messages_includes_rolling_memory(self) -> None:
        request = AssistantRequest(
            action="meeting_notes",
            provider="ollama",
            model="fast",
            thinking="medium",
            temperature=0.2,
            max_tokens=700,
            meeting_id="mtg-1",
            rolling_summary="Current notes:\n- 目前結論: 已確認先做本機模式。",
            previous_notes=[{"title": "目前結論", "detail": "已確認先做本機模式。"}],
            previous_actions=[{"title": "整理 speaker labels", "owner": "Unassigned", "state": "Draft"}],
            transcript=[
                AssistantTranscriptLine(
                    source="system",
                    source_label="Other",
                    speaker_hint="other",
                    speaker_id="speaker_2",
                    speaker_label="Speaker 2",
                    start_ms=1000,
                    end_ms=2200,
                    text="We should add rolling summary.",
                    is_final=True,
                )
            ],
        )

        content = build_messages(request)[1]["content"]

        self.assertIn("Existing rolling meeting memory", content)
        self.assertIn("mtg-1", content)
        self.assertIn("整理 speaker labels", content)
        self.assertIn("Speaker 2", content)

    def test_document_edit_plan_requires_explicit_ai_command(self) -> None:
        request = AssistantRequest(
            action="document_edit_plan",
            provider="ollama",
            model="fast",
            thinking="medium",
            temperature=0.2,
            max_tokens=700,
            meeting_id="mtg-1",
            document_title="Demo plan",
            document_summary="TODO: confirm demo owner",
            transcript=[
                AssistantTranscriptLine(
                    source="microphone",
                    source_label="Self",
                    speaker_hint="self",
                    speaker_id="self",
                    speaker_label="Self",
                    start_ms=0,
                    end_ms=1800,
                    text="AI 請幫我把 TODO 改成 Eva will confirm the demo owner.",
                    is_final=True,
                )
            ],
        )

        content = build_messages(request)[1]["content"]

        self.assertIn("intent, find, replace, heading, text, anchor, occurrence", content)
        self.assertIn("AI 請幫我", content)
        self.assertIn("請你幫我", content)
        self.assertIn("requires_user_confirmation to false", content)


if __name__ == "__main__":
    unittest.main()
