# Technical Spec: Local LLM / Agent Provider Integration

## 1. Objective

Implement a local-first provider integration layer for our app.

The app must support two integration strategies:

1. **Local server provider mode**

   * Detect and call local LLM servers such as Ollama, LM Studio, vLLM, llama.cpp, and OpenAI-compatible localhost endpoints.
   * Use these providers for chat, text generation, structured JSON generation, lightweight code generation, and model-backed app features.
   * These providers usually do not edit files or run shell commands by themselves.

2. **CLI non-interactive agent mode**

   * Detect and invoke locally installed agent CLIs such as Claude Code, Codex CLI, Gemini CLI, GitHub Copilot CLI, Cursor CLI, OpenCode, Aider, and Continue CLI.
   * Use these providers for multi-step coding tasks, file editing, repository analysis, test execution, artifact generation, and design-to-code workflows.
   * These providers may access filesystem, shell, network, and MCP tools, so they require a stricter permission and sandbox model.

The app must not extract, inspect, copy, or reuse hidden provider credentials, OAuth tokens, browser cookies, IDE extension storage, or keychain secrets. Authentication must remain owned by the provider’s official local app or CLI.

---

## 2. Non-goals

Do not implement any of the following:

* Do not read credentials from provider config directories.
* Do not scrape browser sessions, extension storage, or OAuth tokens.
* Do not proxy user subscription access through our backend.
* Do not expose a hosted API backed by the user’s local subscription.
* Do not auto-run unknown MCP servers without user approval.
* Do not grant unrestricted filesystem or shell access by default.
* Do not mutate the user’s project directly without previewing diffs.

---

## 3. High-level architecture

```text
App UI
  ↓
Provider Discovery
  ↓
Provider Registry
  ↓
Task Router
  ↓
Provider Adapter Layer
  ├─ Local Server Adapter
  │   ├─ Ollama
  │   ├─ LM Studio
  │   ├─ vLLM
  │   ├─ llama.cpp / llama-cpp-python
  │   └─ Generic OpenAI-compatible localhost
  │
  └─ CLI Agent Adapter
      ├─ Claude Code
      ├─ Codex CLI
      ├─ Gemini CLI
      ├─ GitHub Copilot CLI
      ├─ Cursor CLI
      ├─ OpenCode
      ├─ Aider
      └─ Continue CLI
  ↓
Permission Manager
  ↓
Workspace Sandbox
  ↓
Diff / Artifact Review
```

---

## 4. Provider abstraction

Create a common provider interface.

```ts
export type ProviderKind =
  | "local_server"
  | "cli_agent";

export type Capability =
  | "chat"
  | "streaming"
  | "json_output"
  | "tool_calling"
  | "vision"
  | "embeddings"
  | "file_read"
  | "file_write"
  | "shell"
  | "mcp"
  | "repo_context"
  | "artifact_generation";

export type RiskLevel = "low" | "medium" | "high";

export type ProviderDescriptor = {
  id: string;
  label: string;
  kind: ProviderKind;
  installed: boolean;
  available: boolean;
  version?: string;
  endpoint?: string;
  binaryPath?: string;
  models?: string[];
  capabilities: Capability[];
  riskLevel: RiskLevel;
  authMode: "none" | "provider_owned" | "user_supplied_local_key" | "unknown";
  notes?: string[];
};

export type ProviderDetectionResult = {
  provider: ProviderDescriptor;
  errors?: string[];
  warnings?: string[];
};
```

---

## 5. Task abstraction

Every integration must consume the same task object.

```ts
export type AgentTaskKind =
  | "chat"
  | "summarize"
  | "rewrite"
  | "generate_json"
  | "code_review"
  | "code_edit"
  | "test_fix"
  | "design_to_code"
  | "artifact_generation";

export type PermissionProfile = {
  filesystem: "none" | "workspace_read" | "workspace_write" | "project_read" | "project_write";
  shell: "none" | "approval_required" | "allowlist_only" | "auto";
  network: "none" | "localhost_only" | "internet_with_approval" | "internet";
  mcp: "none" | "approval_required" | "configured_only";
  secrets: "never";
};

export type AgentTask = {
  id: string;
  kind: AgentTaskKind;
  prompt: string;
  workspacePath: string;
  projectPath?: string;
  inputFiles?: string[];
  expectedOutputs?: string[];
  permissionProfile: PermissionProfile;
  timeoutMs: number;
  metadata?: Record<string, unknown>;
};
```

---

## 6. Provider selection rules

Use local server providers for:

* normal chat
* summarization
* rewriting
* classification
* JSON extraction
* simple code generation
* offline/local-only model inference

Use CLI agent providers for:

* multi-file code edits
* repo-aware changes
* test execution
* bug fixing
* migration tasks
* design-to-code generation
* artifact generation
* tool use
* MCP use
* shell-assisted workflows

Default routing:

```ts
export function selectProvider(task: AgentTask, providers: ProviderDescriptor[]) {
  if (
    task.kind === "code_edit" ||
    task.kind === "test_fix" ||
    task.kind === "design_to_code" ||
    task.kind === "artifact_generation"
  ) {
    return providers.find(
      p => p.kind === "cli_agent" && p.available && p.capabilities.includes("file_write")
    );
  }

  if (task.kind === "generate_json") {
    return providers.find(
      p => p.kind === "local_server" && p.available && p.capabilities.includes("json_output")
    );
  }

  return providers.find(
    p => p.kind === "local_server" && p.available && p.capabilities.includes("chat")
  );
}
```

---

# Part A: Local Server Provider Mode

## 7. Local server provider contract

Local server providers are HTTP servers running on localhost or a user-configured local network endpoint.

Implement this interface:

```ts
export type LocalServerProviderConfig = {
  id: string;
  label: string;
  baseUrl: string;
  apiStyle:
    | "ollama_native"
    | "openai_compatible"
    | "anthropic_compatible"
    | "custom";
  defaultHeaders?: Record<string, string>;
  requiresApiKey: boolean;
};

export type LocalChatRequest = {
  model: string;
  messages: Array<{
    role: "system" | "user" | "assistant" | "tool";
    content: string;
  }>;
  temperature?: number;
  maxTokens?: number;
  stream?: boolean;
  responseFormat?: "text" | "json";
};

export type LocalChatResponse = {
  text: string;
  raw: unknown;
  model?: string;
  usage?: {
    inputTokens?: number;
    outputTokens?: number;
    totalTokens?: number;
  };
};
```

---

## 8. Local server discovery

Probe known localhost endpoints with short timeouts.

Default probes:

```ts
const LOCAL_SERVER_CANDIDATES = [
  {
    id: "ollama",
    label: "Ollama",
    baseUrl: "http://127.0.0.1:11434",
    probePath: "/api/tags",
    apiStyle: "ollama_native",
  },
  {
    id: "lmstudio",
    label: "LM Studio",
    baseUrl: "http://127.0.0.1:1234/v1",
    probePath: "/models",
    apiStyle: "openai_compatible",
  },
  {
    id: "vllm",
    label: "vLLM",
    baseUrl: "http://127.0.0.1:8000/v1",
    probePath: "/models",
    apiStyle: "openai_compatible",
  },
  {
    id: "llama_cpp",
    label: "llama.cpp / llama-cpp-python",
    baseUrl: "http://127.0.0.1:8080/v1",
    probePath: "/models",
    apiStyle: "openai_compatible",
  },
  {
    id: "generic_openai_local",
    label: "Generic OpenAI-compatible Local Server",
    baseUrl: "http://127.0.0.1:5000/v1",
    probePath: "/models",
    apiStyle: "openai_compatible",
  },
] as const;
```

Probe function:

```ts
export async function probeHttpJson(url: string, timeoutMs = 1000) {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(url, {
      method: "GET",
      signal: controller.signal,
    });

    if (!res.ok) {
      return { ok: false, status: res.status };
    }

    const json = await res.json().catch(() => null);
    return { ok: true, status: res.status, json };
  } catch (err) {
    return { ok: false, error: String(err) };
  } finally {
    clearTimeout(t);
  }
}
```

---

## 9. Ollama integration

### Detection

Probe:

```http
GET http://127.0.0.1:11434/api/tags
```

Expected response contains a `models` array.

### List models

```ts
export async function listOllamaModels(baseUrl = "http://127.0.0.1:11434") {
  const res = await fetch(`${baseUrl}/api/tags`);
  if (!res.ok) throw new Error(`Ollama model listing failed: ${res.status}`);
  const json = await res.json();
  return (json.models ?? []).map((m: any) => m.name);
}
```

### Chat

```http
POST http://127.0.0.1:11434/api/chat
```

Payload:

```json
{
  "model": "llama3.2",
  "messages": [
    {
      "role": "user",
      "content": "Explain this codebase."
    }
  ],
  "stream": false
}
```

Implementation:

```ts
export async function ollamaChat(req: LocalChatRequest, baseUrl = "http://127.0.0.1:11434") {
  const res = await fetch(`${baseUrl}/api/chat`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model: req.model,
      messages: req.messages,
      stream: req.stream ?? false,
      format: req.responseFormat === "json" ? "json" : undefined,
      options: {
        temperature: req.temperature,
        num_predict: req.maxTokens,
      },
    }),
  });

  if (!res.ok) throw new Error(`Ollama chat failed: ${res.status}`);

  if (req.stream) {
    return res.body;
  }

  const json = await res.json();
  return {
    text: json.message?.content ?? json.response ?? "",
    raw: json,
    model: req.model,
  };
}
```

### Permissions

Ollama is low risk by default:

```ts
const OLLAMA_PERMISSIONS: PermissionProfile = {
  filesystem: "none",
  shell: "none",
  network: "localhost_only",
  mcp: "none",
  secrets: "never",
};
```

Do not expose arbitrary file paths to Ollama unless explicitly selected by the user.

---

## 10. LM Studio integration

### Detection

Default OpenAI-compatible endpoint:

```http
GET http://127.0.0.1:1234/v1/models
```

Some LM Studio native APIs may also be available, but use OpenAI-compatible mode first because it gives us one common implementation path.

### Chat

```http
POST http://127.0.0.1:1234/v1/chat/completions
```

Payload:

```json
{
  "model": "local-model",
  "messages": [
    {
      "role": "user",
      "content": "Generate a JSON schema."
    }
  ],
  "temperature": 0.2,
  "stream": false
}
```

Implementation uses the generic OpenAI-compatible adapter.

### Permissions

LM Studio server can bind to localhost or network. Treat `127.0.0.1` as medium-low risk and any non-localhost host as medium/high risk.

```ts
function classifyEndpointRisk(baseUrl: string): RiskLevel {
  const url = new URL(baseUrl);

  if (url.hostname === "127.0.0.1" || url.hostname === "localhost") return "low";
  if (url.hostname.startsWith("192.168.") || url.hostname.startsWith("10.")) return "medium";

  return "high";
}
```

Warn the user if the endpoint is not localhost.

---

## 11. vLLM integration

### Detection

Default OpenAI-compatible endpoint:

```http
GET http://127.0.0.1:8000/v1/models
```

### Chat

Use generic OpenAI-compatible endpoint:

```http
POST http://127.0.0.1:8000/v1/chat/completions
```

### Notes

vLLM is commonly used by technical users or local server deployments. It may have an API key depending on how the user launched the server.

Support optional local API key configuration:

```ts
type LocalAuthConfig = {
  apiKey?: string;
  headerName?: "Authorization" | "x-api-key";
};
```

For OpenAI-compatible vLLM:

```ts
headers: {
  "content-type": "application/json",
  ...(apiKey ? { authorization: `Bearer ${apiKey}` } : {}),
}
```

### Permissions

vLLM is model inference only unless custom tool/function execution is implemented elsewhere. Default:

```ts
{
  filesystem: "none",
  shell: "none",
  network: "localhost_only",
  mcp: "none",
  secrets: "never"
}
```

---

## 12. llama.cpp / llama-cpp-python integration

### Detection

Probe common endpoints:

```http
GET http://127.0.0.1:8080/v1/models
GET http://127.0.0.1:8000/v1/models
```

### Chat

Use OpenAI-compatible:

```http
POST /v1/chat/completions
```

### Embeddings

If supported by the running server:

```http
POST /v1/embeddings
```

### Permissions

Same as vLLM. Treat it as local inference only.

---

## 13. Generic OpenAI-compatible local adapter

Implement one adapter for LM Studio, vLLM, llama.cpp, and custom local servers.

```ts
export async function openAICompatibleChat(
  req: LocalChatRequest,
  baseUrl: string,
  apiKey?: string
): Promise<LocalChatResponse | ReadableStream<Uint8Array> | null> {
  const res = await fetch(`${baseUrl.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(apiKey ? { authorization: `Bearer ${apiKey}` } : {}),
    },
    body: JSON.stringify({
      model: req.model,
      messages: req.messages,
      temperature: req.temperature,
      max_tokens: req.maxTokens,
      stream: req.stream ?? false,
      response_format:
        req.responseFormat === "json"
          ? { type: "json_object" }
          : undefined,
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`OpenAI-compatible chat failed: ${res.status} ${body}`);
  }

  if (req.stream) {
    return res.body;
  }

  const json = await res.json();

  return {
    text: json.choices?.[0]?.message?.content ?? "",
    raw: json,
    model: json.model ?? req.model,
    usage: {
      inputTokens: json.usage?.prompt_tokens,
      outputTokens: json.usage?.completion_tokens,
      totalTokens: json.usage?.total_tokens,
    },
  };
}
```

---

# Part B: CLI Non-interactive Agent Mode

## 14. CLI provider contract

CLI providers are local executables invoked through child processes.

```ts
export type CliProviderConfig = {
  id: string;
  label: string;
  binaryNames: string[];
  versionArgs: string[];
  runArgsTemplate: string[];
  supportsStreaming: boolean;
  supportsJsonOutput: boolean;
  supportsFileWrite: boolean;
  supportsShell: boolean;
  supportsMcp: boolean;
  defaultRiskLevel: RiskLevel;
};

export type CliRunOptions = {
  cwd: string;
  prompt: string;
  timeoutMs: number;
  env?: Record<string, string>;
  permissionProfile: PermissionProfile;
  outputFormat?: "text" | "json" | "stream-json";
};
```

---

## 15. CLI detection

Use `which` on macOS/Linux and `where.exe` on Windows.

```ts
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export async function findBinary(binaryName: string): Promise<string | null> {
  const locator = process.platform === "win32" ? "where.exe" : "which";

  try {
    const { stdout } = await execFileAsync(locator, [binaryName], {
      timeout: 3000,
    });

    return stdout.split(/\r?\n/)[0]?.trim() || null;
  } catch {
    return null;
  }
}

export async function getCliVersion(binaryPath: string, args: string[] = ["--version"]) {
  try {
    const { stdout, stderr } = await execFileAsync(binaryPath, args, {
      timeout: 5000,
    });

    return (stdout || stderr).trim();
  } catch {
    return undefined;
  }
}
```

---

## 16. CLI process runner

All CLI adapters must use a shared process runner.

```ts
import { spawn } from "node:child_process";

export type CliEvent =
  | { type: "started"; providerId: string; command: string[] }
  | { type: "stdout"; text: string }
  | { type: "stderr"; text: string }
  | { type: "exit"; code: number | null }
  | { type: "error"; error: string };

export async function runCliProcess(opts: {
  providerId: string;
  binaryPath: string;
  args: string[];
  cwd: string;
  timeoutMs: number;
  env?: Record<string, string>;
  onEvent?: (event: CliEvent) => void;
}) {
  return new Promise<{ stdout: string; stderr: string; code: number | null }>((resolve, reject) => {
    const child = spawn(opts.binaryPath, opts.args, {
      cwd: opts.cwd,
      env: {
        ...process.env,
        ...opts.env,
      },
      stdio: ["ignore", "pipe", "pipe"],
      shell: false,
    });

    let stdout = "";
    let stderr = "";

    const timeout = setTimeout(() => {
      child.kill("SIGTERM");

      setTimeout(() => {
        if (!child.killed) child.kill("SIGKILL");
      }, 3000);
    }, opts.timeoutMs);

    opts.onEvent?.({
      type: "started",
      providerId: opts.providerId,
      command: [opts.binaryPath, ...opts.args],
    });

    child.stdout.on("data", chunk => {
      const text = chunk.toString();
      stdout += text;
      opts.onEvent?.({ type: "stdout", text });
    });

    child.stderr.on("data", chunk => {
      const text = chunk.toString();
      stderr += text;
      opts.onEvent?.({ type: "stderr", text });
    });

    child.on("error", err => {
      clearTimeout(timeout);
      opts.onEvent?.({ type: "error", error: String(err) });
      reject(err);
    });

    child.on("close", code => {
      clearTimeout(timeout);
      opts.onEvent?.({ type: "exit", code });

      if (code === 0) {
        resolve({ stdout, stderr, code });
      } else {
        reject(new Error(`CLI exited with code ${code}\n${stderr}`));
      }
    });
  });
}
```

---

## 17. Workspace sandbox model

Before invoking any CLI agent:

1. Create a task-specific workspace.
2. Copy only selected user files into the workspace.
3. Initialize git if necessary.
4. Run the CLI inside that workspace.
5. Capture changed files.
6. Show diff before applying changes to the real project.

```ts
export async function prepareWorkspace(task: AgentTask) {
  const workspacePath = task.workspacePath;

  // Implementation requirements:
  // - mkdir workspacePath
  // - copy selected input files
  // - write task prompt to .ourapp/task.md
  // - write permission profile to .ourapp/permissions.json
  // - git init
  // - git add .
  // - git commit -m "baseline"

  return workspacePath;
}
```

Diff extraction:

```bash
git status --porcelain
git diff -- . ':!.ourapp'
```

The app must never auto-apply generated changes to the user’s project unless the user explicitly accepts the diff.

---

## 18. Shell permission model

Classify shell operations.

```ts
const BLOCKED_COMMAND_PATTERNS = [
  /\brm\s+-rf\b/,
  /\bsudo\b/,
  /\bchmod\s+777\b/,
  /\bcurl\b.*\|\s*(sh|bash)/,
  /\bwget\b.*\|\s*(sh|bash)/,
  /\bdd\s+if=/,
  /\bmkfs\b/,
  /\bgit\s+push\b/,
  /\bnpm\s+publish\b/,
  /\bdocker\s+run\b.*--privileged/,
  /\bssh\b/,
  /\bscp\b/,
];

const APPROVAL_REQUIRED_PATTERNS = [
  /\bnpm\s+install\b/,
  /\bpnpm\s+install\b/,
  /\byarn\s+install\b/,
  /\bpip\s+install\b/,
  /\bpoetry\s+add\b/,
  /\bbrew\s+install\b/,
  /\bdocker\s+run\b/,
  /\bgit\s+commit\b/,
];

export function classifyShellCommand(command: string) {
  if (BLOCKED_COMMAND_PATTERNS.some(r => r.test(command))) {
    return "blocked";
  }

  if (APPROVAL_REQUIRED_PATTERNS.some(r => r.test(command))) {
    return "approval_required";
  }

  return "allowed";
}
```

If a CLI provider supports its own allow/deny tool flags, pass our permission profile into those flags. If it does not, rely on workspace isolation and post-run diff review.

---

## 19. Network permission model

Default network policy:

```ts
const DEFAULT_NETWORK_POLICY = {
  localServerProviders: "localhost_only",
  cliAgents: "internet_with_approval",
};
```

Implementation requirements:

* For local server providers, only probe localhost by default.
* For CLI providers, show a clear UI warning when the task may use internet.
* Do not pass secrets through environment variables unless explicitly configured by the user for that provider.
* Do not forward app-level credentials to provider CLIs.
* Do not proxy CLI network traffic.

Optional stricter implementation:

* Run CLI tasks in a container.
* Disable outbound network by default.
* Allow only localhost or a user-approved allowlist.
* Mount workspace read-write and everything else read-only or not mounted.

---

# Provider-specific CLI Integrations

## 20. Claude Code adapter

### Detection

Binary names:

```text
claude
```

Version:

```bash
claude --version
```

### Non-interactive invocation

Use print/headless mode:

```bash
claude -p "<prompt>"
```

Recommended structured output:

```bash
claude -p "<prompt>" --output-format json
```

Recommended permission-constrained invocation:

```bash
claude -p "<prompt>" \
  --allowedTools "Read,Edit,Write,Bash(git status),Bash(git diff),Bash(npm test)" \
  --output-format json
```

Use stricter defaults for our app:

```ts
const CLAUDE_DEFAULT_ALLOWED_TOOLS = [
  "Read",
  "Edit",
  "Write",
  "Bash(git status)",
  "Bash(git diff)",
  "Bash(npm test)",
  "Bash(pnpm test)",
  "Bash(yarn test)",
];
```

### Adapter implementation

```ts
export async function runClaudeCode(task: AgentTask, binaryPath = "claude") {
  const allowedTools = buildClaudeAllowedTools(task.permissionProfile);

  const args = [
    "-p",
    buildAgentPrompt(task),
    "--output-format",
    "json",
  ];

  if (allowedTools.length > 0) {
    args.push("--allowedTools", allowedTools.join(","));
  }

  return runCliProcess({
    providerId: "claude_code",
    binaryPath,
    args,
    cwd: task.workspacePath,
    timeoutMs: task.timeoutMs,
  });
}

function buildClaudeAllowedTools(profile: PermissionProfile) {
  const tools: string[] = ["Read"];

  if (profile.filesystem === "workspace_write" || profile.filesystem === "project_write") {
    tools.push("Edit", "Write");
  }

  if (profile.shell !== "none") {
    tools.push(
      "Bash(git status)",
      "Bash(git diff)",
      "Bash(npm test)",
      "Bash(pnpm test)",
      "Bash(yarn test)"
    );
  }

  return tools;
}
```

### Permissions

Risk: high.

Default:

```ts
{
  filesystem: "workspace_write",
  shell: "approval_required",
  network: "internet_with_approval",
  mcp: "configured_only",
  secrets: "never"
}
```

Never use broad permission-bypass modes in normal app flows. If a user explicitly asks for unrestricted execution, require a separate confirmation and run only inside a disposable container or temporary workspace.

---

## 21. OpenAI Codex CLI adapter

### Detection

Binary names:

```text
codex
```

Version:

```bash
codex --version
```

### Non-interactive invocation

Use:

```bash
codex exec "<prompt>"
```

Recommended workspace invocation:

```bash
codex exec --cd "<workspacePath>" "<prompt>"
```

### Avoid dangerous flags

Do not use these in normal app flows:

```bash
--dangerously-bypass-approvals-and-sandbox
--yolo
```

These should only be available behind an explicit advanced setting and only inside an isolated runner.

### Adapter implementation

```ts
export async function runCodexCli(task: AgentTask, binaryPath = "codex") {
  const args = [
    "exec",
    "--cd",
    task.workspacePath,
    buildAgentPrompt(task),
  ];

  return runCliProcess({
    providerId: "codex_cli",
    binaryPath,
    args,
    cwd: task.workspacePath,
    timeoutMs: task.timeoutMs,
  });
}
```

### Permissions

Risk: high.

Default:

```ts
{
  filesystem: "workspace_write",
  shell: "approval_required",
  network: "internet_with_approval",
  mcp: "configured_only",
  secrets: "never"
}
```

Rely on:

* Codex CLI’s own sandbox/approval behavior.
* Our workspace sandbox.
* Our diff review.
* No provider token inspection.

---

## 22. Gemini CLI adapter

### Detection

Binary names:

```text
gemini
```

Version:

```bash
gemini --version
```

### Non-interactive invocation

Use prompt mode:

```bash
gemini -p "<prompt>"
```

Structured output when supported:

```bash
gemini -p "<prompt>" --output-format json
```

Streaming JSON when supported:

```bash
gemini -p "<prompt>" --output-format stream-json
```

### Adapter implementation

```ts
export async function runGeminiCli(task: AgentTask, binaryPath = "gemini") {
  const args = [
    "-p",
    buildAgentPrompt(task),
    "--output-format",
    "json",
  ];

  return runCliProcess({
    providerId: "gemini_cli",
    binaryPath,
    args,
    cwd: task.workspacePath,
    timeoutMs: task.timeoutMs,
  });
}
```

### Permissions

Risk: high if filesystem or shell tools are enabled.

Default:

```ts
{
  filesystem: "workspace_write",
  shell: "approval_required",
  network: "internet_with_approval",
  mcp: "configured_only",
  secrets: "never"
}
```

---

## 23. GitHub Copilot CLI adapter

### Detection

Binary names:

```text
copilot
```

Version:

```bash
copilot --version
```

### Invocation

Copilot CLI has its own command structure and tool permission controls. Implement the adapter conservatively.

Example permission flags:

```bash
copilot --allow-tool='Read' --deny-tool='Bash(rm *)'
```

Exact tool names may vary by installed Copilot CLI version and configured MCP tools, so detection should not assume a fixed complete tool list.

### Adapter strategy

1. Detect Copilot CLI.
2. Confirm user wants to use it.
3. Run only inside workspace sandbox.
4. Prefer deny rules for dangerous tools.
5. Do not pass broad auto-approval unless the user explicitly opts in.
6. Capture stdout/stderr and file diffs.

Example:

```ts
export async function runCopilotCli(task: AgentTask, binaryPath = "copilot") {
  const args = [
    "--deny-tool",
    "Bash(rm *)",
    "--deny-tool",
    "Bash(sudo *)",
    "--deny-tool",
    "Bash(git push *)",
    buildAgentPrompt(task),
  ];

  return runCliProcess({
    providerId: "github_copilot_cli",
    binaryPath,
    args,
    cwd: task.workspacePath,
    timeoutMs: task.timeoutMs,
  });
}
```

### Permissions

Risk: high.

Default:

```ts
{
  filesystem: "workspace_write",
  shell: "approval_required",
  network: "internet_with_approval",
  mcp: "approval_required",
  secrets: "never"
}
```

Do not use blanket allow-all tool behavior by default.

---

## 24. Cursor CLI adapter

### Detection

Binary names:

```text
cursor
```

Version:

```bash
cursor --version
```

### Invocation

Cursor CLI supports agent usage from the command line and headless/automation workflows. Because command options may evolve, implement adapter discovery defensively:

```bash
cursor --help
cursor agent --help
```

Potential invocation shapes:

```bash
cursor agent "<prompt>"
cursor agent --print "<prompt>"
cursor --headless "<prompt>"
```

Do not hardcode one mode without checking the installed version’s help output.

### Adapter strategy

```ts
export async function detectCursorCli(binaryPath = "cursor") {
  const help = await getHelp(binaryPath, ["--help"]);
  const agentHelp = await getHelp(binaryPath, ["agent", "--help"]).catch(() => "");

  return {
    supportsAgentSubcommand: agentHelp.includes("agent"),
    help,
    agentHelp,
  };
}
```

Run command should be selected from detected supported syntax.

### Permissions

Risk: high.

Default:

```ts
{
  filesystem: "workspace_write",
  shell: "approval_required",
  network: "internet_with_approval",
  mcp: "configured_only",
  secrets: "never"
}
```

---

## 25. OpenCode adapter

### Detection

Binary names:

```text
opencode
```

Version:

```bash
opencode --version
```

### Non-interactive invocation

Use run mode:

```bash
opencode run "<prompt>"
```

### Server mode

OpenCode may also expose a headless server mode:

```bash
opencode serve
```

If server mode is used, require authentication/password when available and bind to localhost only.

### Adapter implementation

```ts
export async function runOpenCode(task: AgentTask, binaryPath = "opencode") {
  const args = [
    "run",
    buildAgentPrompt(task),
  ];

  return runCliProcess({
    providerId: "opencode",
    binaryPath,
    args,
    cwd: task.workspacePath,
    timeoutMs: task.timeoutMs,
  });
}
```

### Permissions

Risk: high.

Default:

```ts
{
  filesystem: "workspace_write",
  shell: "approval_required",
  network: "internet_with_approval",
  mcp: "configured_only",
  secrets: "never"
}
```

---

## 26. Aider adapter

### Detection

Binary names:

```text
aider
```

Version:

```bash
aider --version
```

### Scripting invocation

Aider supports scripting with `--message`.

Example:

```bash
aider --message "Add tests for the auth module" src/auth.ts
```

Use it when the app knows the exact files to edit.

### Adapter implementation

```ts
export async function runAider(task: AgentTask, binaryPath = "aider") {
  const files = task.inputFiles ?? [];

  const args = [
    "--message",
    buildAgentPrompt(task),
    ...files,
  ];

  return runCliProcess({
    providerId: "aider",
    binaryPath,
    args,
    cwd: task.workspacePath,
    timeoutMs: task.timeoutMs,
  });
}
```

### Permissions

Risk: medium/high depending on file scope.

Default:

```ts
{
  filesystem: "workspace_write",
  shell: "none",
  network: "internet_with_approval",
  mcp: "none",
  secrets: "never"
}
```

Aider should only receive explicit files unless the user grants repo-wide context.

---

## 27. Continue CLI adapter

### Detection

Binary names:

```text
cn
continue
```

Version:

```bash
cn --version
```

or:

```bash
continue --version
```

### Invocation

Continue CLI is a terminal-based coding agent. Detect exact commands through:

```bash
cn --help
```

Potential use:

```bash
cn "<prompt>"
```

or command-specific headless mode depending on installed version.

### Adapter strategy

Use help-based command detection instead of hardcoding unsupported flags.

```ts
export async function runContinueCli(task: AgentTask, binaryPath = "cn") {
  const help = await getHelp(binaryPath, ["--help"]);

  const args = help.includes("--message")
    ? ["--message", buildAgentPrompt(task)]
    : [buildAgentPrompt(task)];

  return runCliProcess({
    providerId: "continue_cli",
    binaryPath,
    args,
    cwd: task.workspacePath,
    timeoutMs: task.timeoutMs,
  });
}
```

### Permissions

Risk: high.

Default:

```ts
{
  filesystem: "workspace_write",
  shell: "approval_required",
  network: "internet_with_approval",
  mcp: "configured_only",
  secrets: "never"
}
```

---

# Permission Control Requirements

## 28. Provider permission matrix

| Provider           | Filesystem          | Shell             | Network           | MCP               | Default Risk |
| ------------------ | ------------------- | ----------------- | ----------------- | ----------------- | ------------ |
| Ollama             | none                | none              | localhost only    | none              | low          |
| LM Studio          | none                | none              | localhost only    | none              | low/medium   |
| vLLM               | none                | none              | localhost only    | none              | low/medium   |
| llama.cpp          | none                | none              | localhost only    | none              | low          |
| Claude Code        | workspace write     | approval required | approval required | configured only   | high         |
| Codex CLI          | workspace write     | approval required | approval required | configured only   | high         |
| Gemini CLI         | workspace write     | approval required | approval required | configured only   | high         |
| GitHub Copilot CLI | workspace write     | approval required | approval required | approval required | high         |
| Cursor CLI         | workspace write     | approval required | approval required | configured only   | high         |
| OpenCode           | workspace write     | approval required | approval required | configured only   | high         |
| Aider              | explicit files only | none by default   | approval required | none              | medium/high  |
| Continue CLI       | workspace write     | approval required | approval required | configured only   | high         |

---

## 29. Permission profiles

Implement three built-in profiles.

### Safe profile

Use for default app actions.

```ts
export const SAFE_PROFILE: PermissionProfile = {
  filesystem: "workspace_write",
  shell: "none",
  network: "localhost_only",
  mcp: "none",
  secrets: "never",
};
```

### Agent profile

Use for normal coding-agent tasks.

```ts
export const AGENT_PROFILE: PermissionProfile = {
  filesystem: "workspace_write",
  shell: "approval_required",
  network: "internet_with_approval",
  mcp: "configured_only",
  secrets: "never",
};
```

### Isolated automation profile

Use for advanced automation only inside a disposable container or VM.

```ts
export const ISOLATED_AUTOMATION_PROFILE: PermissionProfile = {
  filesystem: "workspace_write",
  shell: "auto",
  network: "internet",
  mcp: "configured_only",
  secrets: "never",
};
```

Never use `ISOLATED_AUTOMATION_PROFILE` on the user’s real project directory.

---

## 30. Prompt wrapper

All CLI tasks must include an instruction wrapper.

```ts
export function buildAgentPrompt(task: AgentTask) {
  return `
You are running inside a controlled local workspace.

Task:
${task.prompt}

Workspace rules:
1. Only read and write files inside the current workspace.
2. Do not access user home directories.
3. Do not read secrets, tokens, credentials, cookies, keychains, or environment files unless explicitly included in the task input.
4. Do not run destructive commands.
5. Do not push to remote repositories.
6. Do not publish packages.
7. Do not install dependencies unless necessary and allowed by the permission profile.
8. Prefer producing a minimal diff.
9. At the end, summarize:
   - files changed
   - commands run
   - assumptions
   - remaining risks

Permission profile:
${JSON.stringify(task.permissionProfile, null, 2)}

Expected outputs:
${(task.expectedOutputs ?? []).map(x => `- ${x}`).join("\n") || "- No specific output file required."}
`.trim();
}
```

---

## 31. Artifact generation contract

For design-to-code or generated app workflows, require a manifest.

The agent must create:

```text
artifact/manifest.json
```

Manifest schema:

```ts
export type ArtifactManifest = {
  type: "web_app" | "html" | "react" | "vue" | "svelte" | "static";
  entry: string;
  files: string[];
  previewCommand?: string;
  buildCommand?: string;
  testCommand?: string;
  summary: string;
};
```

Example:

```json
{
  "type": "react",
  "entry": "artifact/src/App.tsx",
  "files": [
    "artifact/package.json",
    "artifact/src/App.tsx",
    "artifact/src/styles.css"
  ],
  "previewCommand": "pnpm dev",
  "buildCommand": "pnpm build",
  "summary": "Generated a responsive dashboard prototype."
}
```

The app must preview artifacts inside a sandboxed iframe or isolated preview server.

---

## 32. Diff review requirement

After every CLI agent run:

1. Capture changed files.
2. Generate diff.
3. Display diff to user.
4. Allow per-file accept/reject.
5. Apply accepted changes only.

```ts
export type DiffReviewResult = {
  changedFiles: string[];
  acceptedFiles: string[];
  rejectedFiles: string[];
  applied: boolean;
};
```

Never auto-apply changes to the original project.

---

## 33. MCP handling

If a CLI provider supports MCP:

* Do not auto-import MCP server configs silently.
* Show server name, command, args, cwd, and env keys.
* Hide env values.
* Require user approval before enabling each MCP server.
* Prefer project-local MCP config over global config.
* Bind HTTP MCP servers to localhost only.
* Reject unknown remote MCP servers by default.

MCP permission object:

```ts
export type McpServerPermission = {
  serverName: string;
  transport: "stdio" | "http";
  command?: string;
  args?: string[];
  url?: string;
  allowedTools: string[];
  deniedTools: string[];
  enabled: boolean;
};
```

---

## 34. UI requirements

Provider settings UI must show:

* Provider name
* Provider type
* Binary path or base URL
* Detected version
* Available models
* Capabilities
* Risk level
* Auth status if detectable without reading secrets
* Permission profile
* Last run logs
* Disable/remove button

Task execution UI must show:

* Selected provider
* Workspace path
* Permission profile
* Live stdout/stderr stream
* Commands requested or run, if detectable
* Files changed
* Final diff
* Apply/reject controls

---

## 35. Security requirements

Hard requirements:

* Use `spawn` or `execFile`, not shell string interpolation.
* Do not run child processes with `shell: true`.
* Escape or pass all arguments as argument arrays.
* Use timeouts.
* Kill long-running processes.
* Never pass app secrets to provider environment.
* Redact logs before displaying or storing them.
* Store per-task logs under the task workspace.
* Do not store provider credentials.
* Do not read provider credential files.
* Do not scan browser or IDE extension storage.
* Do not follow symlinks outside workspace when applying diffs.
* Normalize paths and reject path traversal.
* Require confirmation for network or shell escalation.

Path safety:

```ts
import path from "node:path";

export function assertInsideWorkspace(workspacePath: string, candidatePath: string) {
  const resolvedWorkspace = path.resolve(workspacePath);
  const resolvedCandidate = path.resolve(workspacePath, candidatePath);

  if (
    resolvedCandidate !== resolvedWorkspace &&
    !resolvedCandidate.startsWith(resolvedWorkspace + path.sep)
  ) {
    throw new Error(`Path escapes workspace: ${candidatePath}`);
  }

  return resolvedCandidate;
}
```

---

## 36. Logging and redaction

Redact likely secrets before showing logs.

```ts
export function redactSecrets(text: string) {
  return text
    .replace(/sk-[A-Za-z0-9_\-]{20,}/g, "sk-REDACTED")
    .replace(/ghp_[A-Za-z0-9_]{20,}/g, "ghp_REDACTED")
    .replace(/github_pat_[A-Za-z0-9_]{20,}/g, "github_pat_REDACTED")
    .replace(/xox[baprs]-[A-Za-z0-9-]{20,}/g, "xox-REDACTED")
    .replace(/AKIA[0-9A-Z]{16}/g, "AKIA_REDACTED")
    .replace(/(?<=api[_-]?key["'=:\s]{0,10})[A-Za-z0-9_\-]{16,}/gi, "REDACTED");
}
```

---

## 37. Acceptance criteria

### Local server providers

* Detect Ollama if `http://127.0.0.1:11434/api/tags` is available.
* Detect LM Studio if `http://127.0.0.1:1234/v1/models` is available.
* Detect vLLM if configured OpenAI-compatible endpoint responds to `/v1/models`.
* Detect llama.cpp / llama-cpp-python if configured OpenAI-compatible endpoint responds to `/v1/models`.
* List models when supported.
* Send non-streaming chat request.
* Support streaming response where possible.
* Support JSON output request where provider supports it.
* Never access filesystem or shell.

### CLI providers

* Detect installed CLI binaries through PATH.
* Show binary path and version when available.
* Run tasks inside a temporary workspace.
* Invoke non-interactive/headless mode where supported.
* Capture stdout and stderr.
* Enforce timeout.
* Generate diff after run.
* Require user review before applying changes.
* Do not read provider credentials.
* Do not use broad permission-bypass flags by default.

### Permission system

* Default local server task uses `SAFE_PROFILE`.
* Default CLI agent task uses `AGENT_PROFILE`.
* Dangerous shell commands are blocked or require approval.
* Files outside workspace cannot be modified.
* Symlink escape is rejected.
* Network escalation requires explicit user approval.
* MCP servers require explicit user approval.

---

## 38. Suggested implementation order

Phase 1:

1. Provider registry
2. Local server detection
3. Ollama adapter
4. Generic OpenAI-compatible adapter
5. Workspace sandbox
6. Diff review

Phase 2:

1. Codex CLI adapter
2. Claude Code adapter
3. Gemini CLI adapter
4. OpenCode adapter
5. Shared CLI runner
6. Permission profiles

Phase 3:

1. Cursor CLI adapter
2. GitHub Copilot CLI adapter
3. Aider adapter
4. Continue CLI adapter
5. MCP import UI
6. Containerized execution option

Phase 4:

1. Artifact manifest support
2. Sandboxed preview server
3. Per-provider benchmark
4. User-configurable provider routing
5. Advanced permission policies
