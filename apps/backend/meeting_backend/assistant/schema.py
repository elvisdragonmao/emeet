from typing import Any, Dict, List


class SchemaValidationError(ValueError):
    pass


ASSISTANT_RESPONSE_SCHEMA: Dict[str, Any] = {
    "type": "object",
    "required": ["drafts", "notes", "actions"],
    "properties": {
        "drafts": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["title", "detail", "badge", "icon_name"],
                "properties": {
                    "title": {"type": "string"},
                    "detail": {"type": "string"},
                    "badge": {"type": "string"},
                    "icon_name": {"type": "string"},
                },
            },
        },
        "notes": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["title", "detail"],
                "properties": {
                    "title": {"type": "string"},
                    "detail": {"type": "string"},
                },
            },
        },
        "actions": {
            "type": "array",
            "items": {
                "type": "object",
                "required": ["title", "owner", "state"],
                "properties": {
                    "title": {"type": "string"},
                    "owner": {"type": ["string", "null"]},
                    "state": {"type": "string"},
                },
            },
        },
    },
}


def validate_assistant_payload(payload: Dict[str, Any]) -> None:
    validate_json_schema(payload, ASSISTANT_RESPONSE_SCHEMA)


def validate_json_schema(value: Any, schema: Dict[str, Any], path: str = "$") -> None:
    expected_type = schema.get("type")
    if expected_type is not None and not matches_type(value, expected_type):
        raise SchemaValidationError(
            "{} expected {}, got {}".format(path, expected_type, type(value).__name__)
        )

    if schema.get("type") == "object":
        if not isinstance(value, dict):
            raise SchemaValidationError("{} expected object".format(path))

        for key in schema.get("required", []):
            if key not in value:
                raise SchemaValidationError("{} missing required key {}".format(path, key))

        properties = schema.get("properties", {})
        for key, child_schema in properties.items():
            if key in value:
                validate_json_schema(value[key], child_schema, "{}.{}".format(path, key))
        return

    if schema.get("type") == "array":
        if not isinstance(value, list):
            raise SchemaValidationError("{} expected array".format(path))

        item_schema = schema.get("items")
        if item_schema:
            for index, item in enumerate(value):
                validate_json_schema(item, item_schema, "{}[{}]".format(path, index))


def matches_type(value: Any, expected_type: Any) -> bool:
    if isinstance(expected_type, list):
        return any(matches_type(value, item) for item in expected_type)

    if expected_type == "object":
        return isinstance(value, dict)
    if expected_type == "array":
        return isinstance(value, list)
    if expected_type == "string":
        return isinstance(value, str)
    if expected_type == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected_type == "number":
        return (isinstance(value, int) or isinstance(value, float)) and not isinstance(value, bool)
    if expected_type == "boolean":
        return isinstance(value, bool)
    if expected_type == "null":
        return value is None

    return True


def canonical_assistant_payload(parsed: Dict[str, Any], raw_text: str) -> Dict[str, List[Dict[str, str]]]:
    try:
        validate_assistant_payload(parsed)
    except SchemaValidationError:
        pass

    payload = {
        "drafts": normalize_drafts(parsed.get("drafts"), raw_text),
        "notes": normalize_notes(parsed.get("notes")),
        "actions": normalize_actions(parsed.get("actions")),
    }
    validate_assistant_payload(payload)
    return payload


def normalize_drafts(value: Any, raw_text: str) -> List[Dict[str, str]]:
    if isinstance(value, list) and value:
        drafts = [
            {
                "title": str(item.get("title") or "AI Suggestion"),
                "detail": str(item.get("detail") or item.get("text") or ""),
                "badge": str(item.get("badge") or "AI"),
                "icon_name": str(item.get("icon_name") or item.get("iconName") or "sparkles"),
            }
            for item in value
            if isinstance(item, dict)
        ]
        if drafts:
            return drafts

    return [
        {
            "title": "AI Suggestion",
            "detail": raw_text.strip() or "No assistant response was generated.",
            "badge": "AI",
            "icon_name": "sparkles",
        }
    ]


def normalize_notes(value: Any) -> List[Dict[str, str]]:
    if not isinstance(value, list):
        return []

    return [
        {
            "title": str(item.get("title") or "Note"),
            "detail": str(item.get("detail") or item.get("text") or ""),
        }
        for item in value
        if isinstance(item, dict)
    ]


def normalize_actions(value: Any) -> List[Dict[str, str]]:
    if not isinstance(value, list):
        return []

    return [
        {
            "title": str(item.get("title") or "Next action"),
            "owner": str(item.get("owner") or "Unassigned"),
            "state": str(item.get("state") or "Draft"),
        }
        for item in value
        if isinstance(item, dict)
    ]
