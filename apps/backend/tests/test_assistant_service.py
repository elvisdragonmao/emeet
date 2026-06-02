import unittest

from meeting_backend.assistant.models import AssistantRequest, AssistantTranscriptLine
from meeting_backend.assistant.service import (
    build_codex_exec_command,
    generate_assistant_response,
    list_provider_descriptors,
    parse_assistant_json,
)
from meeting_backend.config import Settings


class AssistantServiceTest(unittest.TestCase):
    def test_mock_provider_generates_drafts(self) -> None:
        request = AssistantRequest(
            action="what_should_i_say",
            provider="mock",
            model="mock-conversation",
            thinking="medium",
            temperature=0.2,
            max_tokens=700,
            transcript=[
                AssistantTranscriptLine(
                    source="system",
                    source_label="Other",
                    speaker_hint="other",
                    start_ms=0,
                    end_ms=1200,
                    text="Can we finish the demo by Friday?",
                    is_final=True,
                )
            ],
        )

        result = generate_assistant_response(Settings(), request)

        self.assertEqual(result.provider, "mock")
        self.assertEqual(result.model, "mock-conversation")
        self.assertGreaterEqual(len(result.drafts), 1)
        self.assertIn("Friday", result.raw_text or "")

    def test_mock_provider_generates_meeting_notes_and_actions(self) -> None:
        request = AssistantRequest(
            action="meeting_notes",
            provider="mock",
            model="mock-conversation",
            thinking="medium",
            temperature=0.2,
            max_tokens=700,
            transcript=[
                AssistantTranscriptLine(
                    source="system",
                    source_label="Other",
                    speaker_hint="other",
                    start_ms=0,
                    end_ms=1200,
                    text="We need Eva to confirm the demo checklist.",
                    is_final=True,
                )
            ],
        )

        result = generate_assistant_response(Settings(), request)

        self.assertGreaterEqual(len(result.notes), 1)
        self.assertGreaterEqual(len(result.actions), 1)
        self.assertIn("demo checklist", result.raw_text or "")

    def test_provider_descriptors_include_mock_and_cli_entries(self) -> None:
        descriptors = list_provider_descriptors(Settings())
        provider_ids = [provider["id"] for provider in descriptors["providers"]]

        self.assertIn("mock", provider_ids)
        self.assertIn("ollama", provider_ids)
        self.assertIn("openai-compatible", provider_ids)
        self.assertIn("codex-cli", provider_ids)
        self.assertEqual(descriptors["defaults"]["thinking"], "medium")

    def test_parse_assistant_json_extracts_object_from_text(self) -> None:
        parsed = parse_assistant_json('Here is JSON:\n{"drafts": [{"title": "A"}]}')

        self.assertEqual(parsed["drafts"][0]["title"], "A")

    def test_parse_assistant_json_ignores_non_object_json(self) -> None:
        self.assertEqual(parse_assistant_json('[{"title": "A"}]'), {})

    def test_codex_exec_command_skips_unsupported_approval_flag(self) -> None:
        help_text = """
        Options:
          -c, --config <key=value>
          -m, --model <MODEL>
              --sandbox <SANDBOX_MODE>
              --skip-git-repo-check
              --ephemeral
          -o, --output-last-message <FILE>
              --color <COLOR>
        """

        command = build_codex_exec_command(
            "codex",
            "gpt-5.4-mini",
            "medium",
            "/tmp/out.txt",
            help_text=help_text,
        )

        self.assertNotIn("--ask-for-approval", command)
        self.assertIn("--sandbox", command)
        self.assertIn("read-only", command)
        self.assertEqual(command[-1], "-")

    def test_codex_exec_command_uses_approval_flag_when_supported(self) -> None:
        help_text = """
        Options:
              --ask-for-approval <APPROVAL_POLICY>
        """

        command = build_codex_exec_command(
            "codex",
            "",
            "none",
            "/tmp/out.txt",
            help_text=help_text,
        )

        self.assertIn("--ask-for-approval", command)
        self.assertIn("never", command)


if __name__ == "__main__":
    unittest.main()
