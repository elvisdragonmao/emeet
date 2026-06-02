import unittest

from meeting_backend.assistant.models import AssistantRequest, AssistantTranscriptLine
from meeting_backend.assistant.service import (
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


if __name__ == "__main__":
    unittest.main()
