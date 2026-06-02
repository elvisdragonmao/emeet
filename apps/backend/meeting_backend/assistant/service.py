import json
import re
import shutil
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

from meeting_backend.assistant.models import (
    AssistantProviderDescriptor,
    AssistantRequest,
    AssistantResult,
    AssistantTranscriptLine,
)
from meeting_backend.assistant.prompts import build_messages
from meeting_backend.assistant.schema import canonical_assistant_payload
from meeting_backend.config import Settings


THINKING_LEVELS = {"none", "low", "medium", "high", "xhigh"}


def list_provider_descriptors(settings: Settings) -> Dict[str, Any]:
    return {
        "defaults": {
            "provider": settings.assistant_provider,
            "model": settings.assistant_model,
            "thinking": settings.assistant_thinking,
        },
        "providers": [
            mock_descriptor(settings).to_dict(),
            ollama_descriptor(settings).to_dict(),
            openai_compatible_descriptor(settings).to_dict(),
            codex_cli_descriptor(settings).to_dict(),
            github_copilot_cli_descriptor(settings).to_dict(),
        ],
    }


def generate_assistant_response(settings: Settings, request: AssistantRequest) -> AssistantResult:
    provider = normalize_provider(request.provider or settings.assistant_provider)
    model = request.model or settings.assistant_model
    thinking = normalize_thinking(request.thinking or settings.assistant_thinking)
    started_at = time.monotonic()
    raw_text = dispatch_provider(settings, request, provider, model, thinking)
    parsed = parse_assistant_json(raw_text)
    payload = canonical_assistant_payload(parsed, raw_text)
    latency_ms = int((time.monotonic() - started_at) * 1000)

    return AssistantResult(
        provider=provider,
        model=model,
        thinking=thinking,
        latency_ms=latency_ms,
        drafts=payload["drafts"],
        notes=payload["notes"],
        actions=payload["actions"],
        raw_text=raw_text,
    )


def dispatch_provider(
    settings: Settings,
    request: AssistantRequest,
    provider: str,
    model: str,
    thinking: str,
) -> str:
    if provider == "mock":
        return mock_completion(request, model, thinking)

    messages = build_messages(request)
    if provider == "ollama":
        return ollama_completion(settings, model, messages, request, thinking)

    if provider == "openai-compatible":
        return openai_compatible_completion(settings, model, messages, request, thinking)

    if provider == "codex-cli":
        return codex_cli_completion(settings, model, messages, thinking)

    if provider == "github-copilot-cli":
        return github_copilot_cli_completion(settings, model, messages, thinking)

    raise ValueError("unsupported assistant provider: {}".format(provider))


def mock_completion(request: AssistantRequest, model: str, thinking: str) -> str:
    latest = latest_transcript_text(request.transcript)
    if request.action == "follow_up_questions":
        payload = {
            "drafts": [
                {
                    "title": "釐清目標",
                    "detail": "你希望我們優先確認目標、時程，還是決策標準？",
                    "badge": "AI",
                    "icon_name": "questionmark.bubble",
                },
                {
                    "title": "確認下一步",
                    "detail": "下一步由誰負責，預計什麼時間前可以回覆或完成？",
                    "badge": thinking,
                    "icon_name": "arrowshape.turn.up.right",
                },
                {
                    "title": "補齊風險",
                    "detail": "目前有沒有任何限制、依賴或風險，是我們需要先確認的？",
                    "badge": model,
                    "icon_name": "exclamationmark.triangle",
                },
            ],
            "notes": [],
            "actions": [],
        }
    elif request.action == "meeting_notes":
        final_count = sum(1 for line in request.transcript if line.is_final)
        payload = {
            "drafts": [],
            "notes": [
                {
                    "title": "討論主題與內容",
                    "detail": "- 已根據最近 {} 段逐字稿整理。\n- 最新討論內容：{}".format(final_count, latest),
                },
                {
                    "title": "目前結論",
                    "detail": "- 逐字稿尚未提供明確決策時，維持草稿狀態。\n- 只保留 transcript 中已說出的結論。",
                },
                {
                    "title": "待討論事項",
                    "detail": "- 補齊尚未確認的時程、範圍與決策標準。\n- 確認是否需要更多資料或 demo 檢查清單。",
                },
                {
                    "title": "未解決問題",
                    "detail": "- 責任歸屬是否明確？\n- 是否有風險、限制或依賴尚未確認？",
                },
            ],
            "actions": [
                {
                    "title": "確認下一步與負責人",
                    "owner": "Unassigned",
                    "state": "Draft",
                },
                {
                    "title": "Review latest transcript evidence",
                    "owner": "Self",
                    "state": "Review",
                },
            ],
        }
    else:
        payload = {
            "drafts": [
                {
                    "title": "先對齊問題",
                    "detail": "我先確認一下，你剛剛的重點是「{}」，對嗎？".format(latest),
                    "badge": "AI",
                    "icon_name": "quote.bubble",
                },
                {
                    "title": "保守回覆",
                    "detail": "我可以先給一個初步方向，細節我會再確認後補上，避免現在講錯。",
                    "badge": thinking,
                    "icon_name": "checkmark.seal",
                },
            ],
            "notes": [
                {"title": "最新脈絡", "detail": latest},
            ],
            "actions": [
                {"title": "Review AI suggestion before speaking", "owner": "Self", "state": "Draft"},
            ],
        }

    return json.dumps(payload, ensure_ascii=False)


def ollama_completion(
    settings: Settings,
    model: str,
    messages: List[Dict[str, str]],
    request: AssistantRequest,
    thinking: str,
) -> str:
    url = settings.assistant_ollama_base_url.rstrip("/") + "/api/chat"
    payload: Dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": False,
        "options": {
            "temperature": request.temperature,
            "num_predict": request.max_tokens,
        },
    }
    if thinking != "none":
        payload["think"] = thinking

    try:
        response = post_json(url, payload, timeout_ms=settings.assistant_timeout_ms)
    except RuntimeError:
        payload.pop("think", None)
        response = post_json(url, payload, timeout_ms=settings.assistant_timeout_ms)

    return str(response.get("message", {}).get("content") or response.get("response") or "")


def openai_compatible_completion(
    settings: Settings,
    model: str,
    messages: List[Dict[str, str]],
    request: AssistantRequest,
    thinking: str,
) -> str:
    url = settings.assistant_openai_base_url.rstrip("/") + "/chat/completions"
    headers = {}
    if settings.assistant_api_key:
        headers["Authorization"] = "Bearer {}".format(settings.assistant_api_key)

    payload: Dict[str, Any] = {
        "model": model,
        "messages": messages,
        "temperature": request.temperature,
        "max_tokens": request.max_tokens,
        "stream": False,
    }
    if thinking != "none":
        payload["reasoning_effort"] = thinking

    try:
        response = post_json(url, payload, headers=headers, timeout_ms=settings.assistant_timeout_ms)
    except RuntimeError:
        payload.pop("reasoning_effort", None)
        response = post_json(url, payload, headers=headers, timeout_ms=settings.assistant_timeout_ms)

    choices = response.get("choices") or []
    if not choices:
        return ""
    message = choices[0].get("message") or {}
    return str(message.get("content") or choices[0].get("text") or "")


def codex_cli_completion(
    settings: Settings,
    model: str,
    messages: List[Dict[str, str]],
    thinking: str,
) -> str:
    binary = shutil.which("codex")
    if not binary:
        raise RuntimeError("codex CLI is not installed")

    prompt = cli_prompt(messages, model, thinking)
    with tempfile.NamedTemporaryFile(prefix="meeting-assistant-codex-", suffix=".txt") as output:
        command = build_codex_exec_command(binary, model, thinking, output.name)
        completed = run_command(command, prompt, settings.assistant_timeout_ms)
        output.seek(0)
        text = output.read().decode("utf-8", errors="replace").strip()
        return text or completed.stdout.strip()


def build_codex_exec_command(
    binary: str,
    model: str,
    thinking: str,
    output_path: str,
    help_text: Optional[str] = None,
) -> List[str]:
    help_text = help_text if help_text is not None else codex_exec_help(binary)
    command = [binary, "exec"]

    if "--skip-git-repo-check" in help_text:
        command.append("--skip-git-repo-check")
    if "--ephemeral" in help_text:
        command.append("--ephemeral")
    if "--sandbox" in help_text:
        command.extend(["--sandbox", "read-only"])
    if "--ask-for-approval" in help_text:
        command.extend(["--ask-for-approval", "never"])
    if "--output-last-message" in help_text:
        command.extend(["--output-last-message", output_path])
    if "--color" in help_text:
        command.extend(["--color", "never"])
    if model and "--model" in help_text:
        command.extend(["--model", model])
    if thinking != "none" and "--config" in help_text:
        command.extend(["-c", 'model_reasoning_effort="{}"'.format(thinking)])

    command.append("-")
    return command


def codex_exec_help(binary: str) -> str:
    completed = subprocess.run(
        [binary, "exec", "--help"],
        text=True,
        capture_output=True,
        timeout=5,
        check=False,
    )
    return "{}\n{}".format(completed.stdout, completed.stderr)


def github_copilot_cli_completion(
    settings: Settings,
    model: str,
    messages: List[Dict[str, str]],
    thinking: str,
) -> str:
    gh_binary = shutil.which("gh")
    if not gh_binary:
        raise RuntimeError("GitHub CLI is not installed")

    prompt = cli_prompt(messages, model, thinking)
    command = [gh_binary, "copilot", "-p", prompt]
    completed = run_command(command, "", settings.assistant_timeout_ms)
    return completed.stdout.strip()


def cli_prompt(messages: List[Dict[str, str]], model: str, thinking: str) -> str:
    content = "\n\n".join("{}:\n{}".format(message["role"], message["content"]) for message in messages)
    return (
        "You are being used as a meeting assistant provider. "
        "Model setting: {model}. Thinking setting: {thinking}. "
        "Return JSON only.\n\n{content}"
    ).format(model=model, thinking=thinking, content=content)


def run_command(command: List[str], prompt: str, timeout_ms: int) -> subprocess.CompletedProcess:
    completed = subprocess.run(
        command,
        input=prompt,
        text=True,
        capture_output=True,
        cwd=tempfile.gettempdir(),
        timeout=max(1, timeout_ms / 1000),
        check=False,
    )
    if completed.returncode != 0:
        raise RuntimeError((completed.stderr or completed.stdout or "CLI provider failed").strip())
    return completed


def mock_descriptor(settings: Settings) -> AssistantProviderDescriptor:
    return AssistantProviderDescriptor(
        id="mock",
        label="Mock Assistant",
        kind="local_server",
        installed=True,
        available=True,
        models=["mock-conversation"],
        capabilities=["chat", "json_output"],
        risk_level="low",
        auth_mode="none",
        notes=["Deterministic local fallback for UI and transport tests."],
    )


def ollama_descriptor(settings: Settings) -> AssistantProviderDescriptor:
    models, error = list_ollama_models(settings.assistant_ollama_base_url, probe_timeout_ms(settings))
    available = error == ""
    return AssistantProviderDescriptor(
        id="ollama",
        label="Ollama",
        kind="local_server",
        installed=available,
        available=available,
        endpoint=settings.assistant_ollama_base_url,
        models=models,
        capabilities=["chat", "json_output"],
        risk_level=endpoint_risk(settings.assistant_ollama_base_url),
        auth_mode="none",
        notes=[] if available else [error or "Ollama endpoint is not reachable."],
    )


def openai_compatible_descriptor(settings: Settings) -> AssistantProviderDescriptor:
    models, error = list_openai_compatible_models(
        settings.assistant_openai_base_url,
        settings.assistant_api_key,
        probe_timeout_ms(settings),
    )
    available = error == ""
    return AssistantProviderDescriptor(
        id="openai-compatible",
        label="OpenAI-compatible",
        kind="local_server",
        installed=available,
        available=available,
        endpoint=settings.assistant_openai_base_url,
        models=models,
        capabilities=["chat", "json_output"],
        risk_level=endpoint_risk(settings.assistant_openai_base_url),
        auth_mode="user_supplied_local_key" if settings.assistant_api_key else "none",
        notes=[] if available else [error or "OpenAI-compatible endpoint is not reachable."],
    )


def codex_cli_descriptor(settings: Settings) -> AssistantProviderDescriptor:
    binary = shutil.which("codex") or ""
    installed = binary != ""
    models = ["gpt-5.5", "gpt-5.4", "gpt-5.4-mini"]
    if normalize_provider(settings.assistant_provider) == "codex-cli" and settings.assistant_model:
        models.insert(0, settings.assistant_model)
    return AssistantProviderDescriptor(
        id="codex-cli",
        label="Codex CLI",
        kind="cli_agent",
        installed=installed,
        available=installed,
        binary_path=binary,
        models=dedupe(models),
        capabilities=["chat", "repo_context"],
        risk_level="medium",
        auth_mode="provider_owned",
        notes=[
            "Runs codex exec in read-only sandbox with approvals disabled.",
            "Authentication stays inside Codex CLI.",
        ],
    )


def github_copilot_cli_descriptor(settings: Settings) -> AssistantProviderDescriptor:
    binary = shutil.which("gh") or ""
    installed = binary != ""
    return AssistantProviderDescriptor(
        id="github-copilot-cli",
        label="GitHub Copilot CLI",
        kind="cli_agent",
        installed=installed,
        available=installed,
        binary_path=binary,
        models=["copilot-default"],
        capabilities=["chat"],
        risk_level="medium",
        auth_mode="provider_owned",
        notes=[
            "Runs through gh copilot. It may prompt to install Copilot CLI on first use.",
            "Authentication stays inside GitHub CLI / Copilot CLI.",
        ],
    )


def list_ollama_models(base_url: str, timeout_ms: int) -> Tuple[List[str], str]:
    try:
        response = get_json(base_url.rstrip("/") + "/api/tags", timeout_ms=timeout_ms)
        return [str(model.get("name")) for model in response.get("models", []) if model.get("name")], ""
    except Exception as error:
        return [], str(error)


def list_openai_compatible_models(base_url: str, api_key: str, timeout_ms: int) -> Tuple[List[str], str]:
    headers = {}
    if api_key:
        headers["Authorization"] = "Bearer {}".format(api_key)
    try:
        response = get_json(base_url.rstrip("/") + "/models", headers=headers, timeout_ms=timeout_ms)
        models = response.get("data") or response.get("models") or []
        names = []
        for model in models:
            if isinstance(model, str):
                names.append(model)
            elif model.get("id"):
                names.append(str(model["id"]))
        return names, ""
    except Exception as error:
        return [], str(error)


def get_json(url: str, headers: Optional[Dict[str, str]] = None, timeout_ms: int = 1000) -> Dict[str, Any]:
    request = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(request, timeout=max(0.1, timeout_ms / 1000)) as response:
        return json.loads(response.read().decode("utf-8"))


def post_json(
    url: str,
    payload: Dict[str, Any],
    headers: Optional[Dict[str, str]] = None,
    timeout_ms: int = 20_000,
) -> Dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    request_headers = {"Content-Type": "application/json"}
    request_headers.update(headers or {})
    request = urllib.request.Request(url, data=body, headers=request_headers, method="POST")

    try:
        with urllib.request.urlopen(request, timeout=max(0.1, timeout_ms / 1000)) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError("{} returned {}: {}".format(url, error.code, detail))


def parse_assistant_json(text: str) -> Dict[str, Any]:
    stripped = text.strip()
    if not stripped:
        return {}

    try:
        parsed = json.loads(stripped)
        return parsed if isinstance(parsed, dict) else {}
    except json.JSONDecodeError:
        match = re.search(r"\{.*\}", stripped, re.DOTALL)
        if not match:
            return {}
        try:
            parsed = json.loads(match.group(0))
            return parsed if isinstance(parsed, dict) else {}
        except json.JSONDecodeError:
            return {}


def latest_transcript_text(lines: List[AssistantTranscriptLine]) -> str:
    for line in reversed(lines):
        text = line.text.strip()
        if text:
            return text[:80]
    return "目前還沒有逐字稿"


def normalize_provider(provider: str) -> str:
    normalized = provider.strip().lower()
    aliases = {
        "openai": "openai-compatible",
        "lmstudio": "openai-compatible",
        "vllm": "openai-compatible",
        "llama.cpp": "openai-compatible",
        "copilot": "github-copilot-cli",
        "github-copilot": "github-copilot-cli",
        "codex": "codex-cli",
    }
    return aliases.get(normalized, normalized or "mock")


def normalize_thinking(thinking: str) -> str:
    normalized = thinking.strip().lower()
    return normalized if normalized in THINKING_LEVELS else "medium"


def dedupe(values: List[str]) -> List[str]:
    result = []
    seen = set()
    for value in values:
        if value and value not in seen:
            result.append(value)
            seen.add(value)
    return result


def endpoint_risk(base_url: str) -> str:
    try:
        parsed = urllib.parse.urlparse(base_url)
    except Exception:
        return "high"

    host = (parsed.hostname or "").lower()
    if host in {"127.0.0.1", "localhost", "::1"}:
        return "low"
    if host.startswith("192.168.") or host.startswith("10."):
        return "medium"
    return "high"


def probe_timeout_ms(settings: Settings) -> int:
    return min(settings.assistant_timeout_ms, 1000)
