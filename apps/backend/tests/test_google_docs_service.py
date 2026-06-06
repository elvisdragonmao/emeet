import unittest

from meeting_backend.google_docs_service import (
    LIVE_NOTES_TITLE,
    build_append_text_requests,
    build_replace_text_requests,
    build_write_control,
    build_update_live_notes_requests,
    calculate_replacement_ranges,
    extract_document_id,
    flatten_document,
    format_meeting_notes_append,
    utf16_code_units,
)


class GoogleDocsServiceTest(unittest.TestCase):
    def test_extracts_document_id_from_google_docs_urls(self) -> None:
        document_id = "1AbcDefGhij_KlmNoPqrStuVwxyz-1234567890"

        self.assertEqual(
            extract_document_id("https://docs.google.com/document/d/{}/edit".format(document_id)),
            document_id,
        )
        self.assertEqual(
            extract_document_id(
                "https://docs.google.com/document/u/0/d/{}/edit?tab=t.0".format(document_id)
            ),
            document_id,
        )
        self.assertEqual(extract_document_id(document_id), document_id)

    def test_rejects_invalid_google_docs_url(self) -> None:
        with self.assertRaises(ValueError):
            extract_document_id("https://example.com/not-a-doc")

    def test_flattens_document_text_headings_sections_and_preview(self) -> None:
        snapshot = flatten_document("doc-1", sample_document())

        self.assertEqual(snapshot.title, "Demo Doc")
        self.assertEqual(snapshot.revision_id, "rev-1")
        self.assertEqual(snapshot.plain_text, "Project Plan\nTODO item\nBody text\n")
        self.assertEqual(snapshot.preview, "Project Plan\nTODO item\nBody text")
        self.assertEqual(len(snapshot.headings), 1)
        self.assertEqual(snapshot.headings[0].text, "Project Plan")
        self.assertEqual(snapshot.headings[0].level, 1)
        self.assertEqual(len(snapshot.sections), 1)
        self.assertIn("TODO item", snapshot.sections[0].preview)

    def test_append_request_inserts_before_final_newline(self) -> None:
        snapshot = flatten_document("doc-1", sample_document())
        requests = build_append_text_requests(snapshot, "Meeting notes")

        self.assertEqual(requests[0]["insertText"]["location"]["index"], 33)
        self.assertEqual(requests[0]["insertText"]["text"], "\n\nMeeting notes\n")

    def test_write_control_uses_target_revision_by_default(self) -> None:
        self.assertEqual(build_write_control("rev-1"), {"targetRevisionId": "rev-1"})
        self.assertEqual(
            build_write_control("rev-1", mode="required"),
            {"requiredRevisionId": "rev-1"},
        )
        self.assertEqual(build_write_control(""), {})

    def test_first_replacement_uses_delete_then_insert_range(self) -> None:
        snapshot = flatten_document("doc-1", sample_document())
        requests = build_replace_text_requests(snapshot, "TODO", "Done", occurrence="first")

        self.assertEqual(
            requests,
            [
                {"deleteContentRange": {"range": {"startIndex": 14, "endIndex": 18}}},
                {"insertText": {"location": {"index": 14}, "text": "Done"}},
            ],
        )

    def test_all_replacement_uses_replace_all_text(self) -> None:
        snapshot = flatten_document("doc-1", sample_document())
        requests = build_replace_text_requests(snapshot, "TODO", "Done", occurrence="all")

        self.assertEqual(
            requests,
            [
                {
                    "replaceAllText": {
                        "containsText": {"text": "TODO", "matchCase": True},
                        "replaceText": "Done",
                    }
                }
            ],
        )

    def test_replacement_ranges_for_all_are_end_to_start(self) -> None:
        snapshot = flatten_document("doc-2", repeated_document())
        ranges = calculate_replacement_ranges(snapshot, "alpha", occurrence="all")

        self.assertEqual([item.start_index for item in ranges], [12, 1])
        self.assertEqual([item.end_index for item in ranges], [17, 6])

    def test_live_notes_request_creates_heading_when_missing(self) -> None:
        snapshot = flatten_document("doc-1", sample_document())
        requests = build_update_live_notes_requests(snapshot, "## Notes\n- Item")

        self.assertEqual(requests[0]["insertText"]["location"]["index"], 33)
        self.assertIn(LIVE_NOTES_TITLE, requests[0]["insertText"]["text"])
        self.assertEqual(
            requests[1]["updateParagraphStyle"]["paragraphStyle"]["namedStyleType"],
            "HEADING_1",
        )

    def test_formats_append_meeting_notes(self) -> None:
        text = format_meeting_notes_append(
            title="Demo Doc",
            notes=[{"title": "目前結論", "detail": "- 先做 Google Docs MVP"}],
            actions=[{"title": "Create OAuth client", "owner": "Eva", "state": "Draft"}],
            transcript=[{"speaker_label": "Self", "text": "We should append notes."}],
        )

        self.assertIn("# emeet Meeting Notes", text)
        self.assertIn("Source document: Demo Doc", text)
        self.assertIn("### 目前結論", text)
        self.assertIn("Owner: Eva", text)
        self.assertIn("Self", text)

    def test_utf16_code_units_counts_non_bmp_characters(self) -> None:
        self.assertEqual(utf16_code_units("a😀b"), 4)


def sample_document():
    return {
        "title": "Demo Doc",
        "revisionId": "rev-1",
        "body": {
            "content": [
                {
                    "startIndex": 1,
                    "endIndex": 14,
                    "paragraph": {
                        "paragraphStyle": {"namedStyleType": "HEADING_1"},
                        "elements": [
                            {
                                "startIndex": 1,
                                "endIndex": 14,
                                "textRun": {"content": "Project Plan\n"},
                            }
                        ],
                    },
                },
                {
                    "startIndex": 14,
                    "endIndex": 24,
                    "paragraph": {
                        "paragraphStyle": {"namedStyleType": "NORMAL_TEXT"},
                        "elements": [
                            {
                                "startIndex": 14,
                                "endIndex": 24,
                                "textRun": {"content": "TODO item\n"},
                            }
                        ],
                    },
                },
                {
                    "startIndex": 24,
                    "endIndex": 34,
                    "paragraph": {
                        "paragraphStyle": {"namedStyleType": "NORMAL_TEXT"},
                        "elements": [
                            {
                                "startIndex": 24,
                                "endIndex": 34,
                                "textRun": {"content": "Body text\n"},
                            }
                        ],
                    },
                },
            ]
        },
    }


def repeated_document():
    return {
        "title": "Repeated",
        "revisionId": "rev-2",
        "body": {
            "content": [
                {
                    "startIndex": 1,
                    "endIndex": 18,
                    "paragraph": {
                        "paragraphStyle": {"namedStyleType": "NORMAL_TEXT"},
                        "elements": [
                            {
                                "startIndex": 1,
                                "endIndex": 18,
                                "textRun": {"content": "alpha beta alpha\n"},
                            }
                        ],
                    },
                }
            ]
        },
    }


if __name__ == "__main__":
    unittest.main()
