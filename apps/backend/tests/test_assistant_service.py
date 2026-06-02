import os
import tempfile
import unittest

from meeting_backend.assistant.models import AssistantRequest, AssistantTranscriptLine
from meeting_backend.assistant import service
from meeting_backend.assistant.service import (
    build_codex_exec_command,
    generate_assistant_response,
    list_provider_descriptors,
    parse_assistant_json,
    read_codex_config_model,
)
from meeting_backend.config import Settings


class AssistantServiceTest(unittest.TestCase):
    def test_ollama_provider_generates_drafts(self) -> None:
        request = AssistantRequest(
            action="what_should_i_say",
            provider="ollama",
            model="fast",
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

        original = service.ollama_completion
        service.ollama_completion = lambda *_args: (
            '{"drafts":[{"title":"Answer Friday","detail":"We can target Friday after checking scope.",'
            '"badge":"AI","icon_name":"quote.bubble"}],"notes":[],"actions":[]}'
        )
        try:
            result = generate_assistant_response(Settings(), request)
        finally:
            service.ollama_completion = original

        self.assertEqual(result.provider, "ollama")
        self.assertEqual(result.model, "fast")
        self.assertEqual(result.thinking, "medium")
        self.assertGreaterEqual(len(result.drafts), 1)
        self.assertIn("Friday", result.raw_text or "")

    def test_ollama_provider_generates_meeting_notes_and_actions(self) -> None:
        request = AssistantRequest(
            action="meeting_notes",
            provider="ollama",
            model="fast",
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

        original = service.ollama_completion
        service.ollama_completion = lambda *_args: (
            '{"drafts":[],"notes":[{"title":"討論主題與內容","detail":"Eva owns the demo checklist."},'
            '{"title":"目前結論","detail":"Checklist needs confirmation."},'
            '{"title":"待討論事項","detail":"Confirm timing."},'
            '{"title":"未解決問題","detail":"Who signs off?"}],'
            '"actions":[{"title":"Confirm demo checklist","owner":"Eva","state":"Draft"}]}'
        )
        try:
            result = generate_assistant_response(Settings(), request)
        finally:
            service.ollama_completion = original

        self.assertGreaterEqual(len(result.notes), 4)
        self.assertGreaterEqual(len(result.actions), 1)
        self.assertIn("討論主題與內容", [note["title"] for note in result.notes])
        self.assertIn("未解決問題", [note["title"] for note in result.notes])
        self.assertIn("demo checklist", result.raw_text or "")

    def test_provider_descriptors_include_local_and_cli_entries(self) -> None:
        descriptors = list_provider_descriptors(Settings())
        provider_ids = [provider["id"] for provider in descriptors["providers"]]

        self.assertIn("ollama", provider_ids)
        self.assertIn("openai-compatible", provider_ids)
        self.assertIn("codex-cli", provider_ids)
        self.assertEqual(descriptors["defaults"]["provider"], "codex-cli")
        self.assertEqual(descriptors["defaults"]["model"], "gpt-5.5")
        self.assertEqual(descriptors["defaults"]["thinking"], "medium")

        codex = next(provider for provider in descriptors["providers"] if provider["id"] == "codex-cli")
        self.assertEqual(codex["risk_level"], "low")
        self.assertIn("text_output", codex["capabilities"])
        self.assertIn("gpt-5.5", codex["models"])

    def test_openai_compatible_descriptor_discovers_candidate_and_lmstudio_models(self) -> None:
        original_openai = service.list_openai_compatible_models
        original_lmstudio = service.list_lmstudio_models_cli
        service.OPENAI_COMPATIBLE_MODEL_ENDPOINTS.clear()

        def fake_openai_models(base_url, _api_key, _timeout_ms):
            if base_url == "http://127.0.0.1:8000/v1":
                return ["qwen-fast"], ""
            return [], "offline"

        service.list_openai_compatible_models = fake_openai_models
        service.list_lmstudio_models_cli = lambda _timeout_ms: (["local/gemma"], "")
        try:
            descriptor = service.openai_compatible_descriptor(Settings()).to_dict()
        finally:
            service.list_openai_compatible_models = original_openai
            service.list_lmstudio_models_cli = original_lmstudio

        self.assertTrue(descriptor["available"])
        self.assertEqual(descriptor["models"], ["qwen-fast", "local/gemma"])
        self.assertEqual(
            service.OPENAI_COMPATIBLE_MODEL_ENDPOINTS["qwen-fast"],
            "http://127.0.0.1:8000/v1",
        )
        self.assertIn("verified_local:http_models_endpoint:http://127.0.0.1:8000/v1", descriptor["notes"])
        self.assertIn("known_to_tool:lmstudio_cli", descriptor["notes"])
        service.OPENAI_COMPATIBLE_MODEL_ENDPOINTS.clear()

    def test_reads_codex_config_model_without_credentials(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "config.toml")
            with open(path, "w", encoding="utf-8") as config:
                config.write('model = "gpt-fast"\napi_key = "secret"\n')

            self.assertEqual(read_codex_config_model(path), "gpt-fast")

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
        self.assertNotIn("--risk-level", command)
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
