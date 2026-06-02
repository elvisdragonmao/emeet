import unittest

from meeting_backend.assistant.schema import (
    SchemaValidationError,
    canonical_assistant_payload,
    validate_assistant_payload,
)


class AssistantSchemaTest(unittest.TestCase):
    def test_validates_expected_response_shape(self) -> None:
        validate_assistant_payload(
            {
                "drafts": [
                    {
                        "title": "Reply",
                        "detail": "I can follow up on that.",
                        "badge": "AI",
                        "icon_name": "quote.bubble",
                    }
                ],
                "notes": [{"title": "Decision", "detail": "Use the local backend."}],
                "actions": [{"title": "Send recap", "owner": "Self", "state": "Draft"}],
            }
        )

    def test_rejects_missing_required_root_key(self) -> None:
        with self.assertRaises(SchemaValidationError):
            validate_assistant_payload({"drafts": [], "notes": []})

    def test_canonical_payload_normalizes_invalid_model_output(self) -> None:
        payload = canonical_assistant_payload(
            {"drafts": [{"text": "Raw answer without schema"}]},
            "Raw answer without schema",
        )

        self.assertEqual(payload["drafts"][0]["title"], "AI Suggestion")
        self.assertEqual(payload["drafts"][0]["detail"], "Raw answer without schema")
        self.assertEqual(payload["notes"], [])
        self.assertEqual(payload["actions"], [])


if __name__ == "__main__":
    unittest.main()
