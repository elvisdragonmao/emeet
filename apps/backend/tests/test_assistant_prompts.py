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
        self.assertIn("drafts, notes, and actions", messages[1]["content"])


if __name__ == "__main__":
    unittest.main()
