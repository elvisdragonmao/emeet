import json
import os
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
)
from meeting_backend.assistant.prompts import build_messages
from meeting_backend.assistant.schema import canonical_assistant_payload
from meeting_backend.config import DEFAULT_ASSISTANT_PROVIDER, DEFAULT_ASSISTANT_THINKING, Settings


THINKING_LEVELS = {"none", "low", "medium", "high", "xhigh"}
OPENAI_COMPATIBLE_CANDIDATE_URLS = [
    "http://127.0.0.1:1234/v1",
    "http://127.0.0.1:8000/v1",
    "http://127.0.0.1:8080/v1",
    "http://127.0.0.1:5000/v1",
    "http://127.0.0.1:4000/v1",
]
OPENAI_COMPATIBLE_MODEL_ENDPOINTS: Dict[str, str] = {}


def list_provider_descriptors(settings: Settings) -> Dict[str, Any]:
    return {
        "defaults": {
            "provider": settings.assistant_provider,
            "model": settings.assistant_model,
            "thinking": settings.assistant_thinking,
        },
        "providers": [
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
    document_edit_plan = canonical_document_edit_plan(parsed) if request.action == "document_edit_plan" else None
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
        document_edit_plan=document_edit_plan,
    )


def dispatch_provider(
    settings: Settings,
    request: AssistantRequest,
    provider: str,
    model: str,
    thinking: str,
) -> str:
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
    base_url = OPENAI_COMPATIBLE_MODEL_ENDPOINTS.get(model, settings.assistant_openai_base_url)
    url = base_url.rstrip("/") + "/chat/completions"
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
    with tempfile.NamedTemporaryFile(prefix="emeet-codex-", suffix=".txt") as output:
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
        "You are being used as the emeet assistant provider. "
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


def ollama_descriptor(settings: Settings) -> AssistantProviderDescriptor:
    models, error, discovery_notes = discover_ollama_models(
        settings.assistant_ollama_base_url,
        probe_timeout_ms(settings),
    )
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
        notes=discovery_notes if available else [error or "Ollama endpoint is not reachable."],
    )


def openai_compatible_descriptor(settings: Settings) -> AssistantProviderDescriptor:
    models, error, discovery_notes = discover_openai_compatible_models(
        settings,
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
        notes=discovery_notes if available else [error or "OpenAI-compatible endpoint is not reachable."],
    )


def codex_cli_descriptor(settings: Settings) -> AssistantProviderDescriptor:
    binary = shutil.which("codex") or ""
    installed = binary != ""
    models = [read_codex_config_model(), "cli-default"]
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
        capabilities=["chat", "text_output"],
        risk_level="low",
        auth_mode="provider_owned",
        notes=[
            "Runs codex exec with read-only sandbox, ephemeral session, and text output capture.",
            "Authentication stays inside Codex CLI.",
            "Model list is not a stable machine-readable CLI API; use configured, default, or manual model.",
            "Codex CLI does not take a risk-level parameter; this provider only returns text for this app.",
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
        models=["cli-default"],
        capabilities=["chat"],
        risk_level="medium",
        auth_mode="provider_owned",
        notes=[
            "Runs through gh copilot. It may prompt to install Copilot CLI on first use.",
            "Authentication stays inside GitHub CLI / Copilot CLI.",
            "Model list is not exposed as a stable machine-readable CLI API.",
        ],
    )


def discover_ollama_models(base_url: str, timeout_ms: int) -> Tuple[List[str], str, List[str]]:
    models, error = list_ollama_models(base_url, timeout_ms)
    if models:
        return models, "", ["verified_local:http_models_endpoint"]

    cli_models, cli_error = list_ollama_models_cli(timeout_ms)
    if cli_models:
        return cli_models, "", ["verified_local:provider_cli_text"]

    return [], "{}; {}".format(error, cli_error).strip("; "), []


def list_ollama_models(base_url: str, timeout_ms: int) -> Tuple[List[str], str]:
    try:
        response = get_json(base_url.rstrip("/") + "/api/tags", timeout_ms=timeout_ms)
        return [str(model.get("name")) for model in response.get("models", []) if model.get("name")], ""
    except Exception as error:
        return [], str(error)


def list_ollama_models_cli(timeout_ms: int) -> Tuple[List[str], str]:
    binary = shutil.which("ollama")
    if not binary:
        return [], "ollama CLI is not installed"

    try:
        completed = subprocess.run(
            [binary, "list"],
            text=True,
            capture_output=True,
            timeout=max(1, timeout_ms / 1000),
            check=False,
        )
    except Exception as error:
        return [], str(error)

    if completed.returncode != 0:
        return [], (completed.stderr or completed.stdout or "ollama list failed").strip()

    models = []
    for index, line in enumerate(completed.stdout.splitlines()):
        stripped = line.strip()
        if not stripped or index == 0 and stripped.lower().startswith("name"):
            continue
        model = stripped.split()[0]
        if model:
            models.append(model)
    return dedupe(models), ""


def discover_openai_compatible_models(
    settings: Settings,
    api_key: str,
    timeout_ms: int,
) -> Tuple[List[str], str, List[str]]:
    discovered_models: List[str] = []
    notes = []
    errors = []
    for base_url in openai_compatible_candidate_urls(settings.assistant_openai_base_url):
        models, error = list_openai_compatible_models(base_url, api_key, timeout_ms)
        if models:
            discovered_models.extend(models)
            remember_openai_compatible_model_endpoints(base_url, models)
            notes.append("verified_local:http_models_endpoint:{}".format(base_url))
        elif error:
            errors.append("{}: {}".format(base_url, error))

    lmstudio_models, lmstudio_error = list_lmstudio_models_cli(timeout_ms)
    if lmstudio_models:
        discovered_models.extend(lmstudio_models)
        notes.append("known_to_tool:lmstudio_cli")
    elif lmstudio_error:
        errors.append("lms: {}".format(lmstudio_error))

    if discovered_models:
        return dedupe(discovered_models), "", notes
    return [], "; ".join(errors), []


def remember_openai_compatible_model_endpoints(base_url: str, models: List[str]) -> None:
    for model in models:
        OPENAI_COMPATIBLE_MODEL_ENDPOINTS.setdefault(model, base_url)


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


def openai_compatible_candidate_urls(configured_base_url: str) -> List[str]:
    configured = configured_base_url.rstrip("/")
    candidates = [configured] if configured else []
    if not configured or endpoint_risk(configured) == "low":
        candidates.extend(OPENAI_COMPATIBLE_CANDIDATE_URLS)
    return dedupe([candidate.rstrip("/") for candidate in candidates if candidate])


def list_lmstudio_models_cli(timeout_ms: int) -> Tuple[List[str], str]:
    binary = shutil.which("lms")
    if not binary:
        return [], "LM Studio CLI is not installed"

    try:
        completed = subprocess.run(
            [binary, "ls", "--llm", "--json"],
            text=True,
            capture_output=True,
            timeout=max(1, timeout_ms / 1000),
            check=False,
        )
    except Exception as error:
        return [], str(error)

    if completed.returncode != 0:
        return [], (completed.stderr or completed.stdout or "lms ls failed").strip()

    try:
        parsed = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        return [], str(error)

    models = []
    if isinstance(parsed, list):
        for item in parsed:
            if not isinstance(item, dict):
                continue
            model = item.get("path") or item.get("modelKey") or item.get("name")
            if model:
                models.append(str(model))
    return dedupe(models), ""


def read_codex_config_model(path: str = "~/.codex/config.toml") -> str:
    try:
        with open(expand_user_path(path), "r", encoding="utf-8") as config:
            for line in config:
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or not stripped.startswith("model"):
                    continue
                key, _, value = stripped.partition("=")
                if key.strip() != "model":
                    continue
                return value.strip().strip('"').strip("'")
    except OSError:
        return ""
    return ""


def expand_user_path(path: str) -> str:
    return os.path.expanduser(path)


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


def canonical_document_edit_plan(parsed: Dict[str, Any]) -> Dict[str, Any]:
    intent = str(parsed.get("intent") or "").strip() or "replace_text"
    valid_intents = {
        "replace_text",
        "append_meeting_notes",
        "rewrite_paragraph_containing_anchor",
        "insert_under_heading",
    }
    if intent not in valid_intents:
        intent = "replace_text"

    return {
        "intent": intent,
        "find": str(parsed.get("find") or ""),
        "replace": str(parsed.get("replace") or ""),
        "reason": str(parsed.get("reason") or ""),
        "requires_user_confirmation": bool(parsed.get("requires_user_confirmation", True)),
    }


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
    return aliases.get(normalized, normalized or DEFAULT_ASSISTANT_PROVIDER)


def normalize_thinking(thinking: str) -> str:
    normalized = thinking.strip().lower()
    return normalized if normalized in THINKING_LEVELS else DEFAULT_ASSISTANT_THINKING


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
    return min(settings.assistant_timeout_ms, 500)
