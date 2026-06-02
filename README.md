# Meeting Assistant Capstone

一個原生 macOS App 會議輔助工具，在會議進行中擷取麥克風與系統音訊，產生即時逐字稿，整理會議筆記與下一步行動，並在需要時用 AI 產生「我現在可以怎麼回」和「還可以追問什麼」。

目前原型採用本地優先的混合式架構：

- macOS App：SwiftUI + AppKit + AVFoundation + ScreenCaptureKit。
- STT backend：Python FastAPI，透過 WebSocket 收 16 kHz mono PCM16 音訊。
- STT provider：`mock`、`faster-whisper`、`mlx-whisper`。
- Assistant provider：`mock`、Ollama、OpenAI-compatible endpoint、Codex CLI、GitHub Copilot CLI。
- AI 輸入：目前只把逐字稿文字丟給 assistant，不直接把原始音訊丟給 LLM。

## Project Layout

```text
.
├── apps/
│   ├── backend/
│   │   └── meeting_backend/             # FastAPI STT + assistant backend
│   └── macos/
│       └── MeetingAssistantPrototype/   # SwiftUI macOS App 原型
├── docs/
│   ├── research/
│   │   ├── raw-reports/                 # 原始 deep research 報告
│   │   ├── translated/                  # 中文翻譯整理版
│   │   └── notes/                       # 研究筆記版
│   └── slides/                          # 簡報與展示素材
├── AGENTS.md                            # 專題需求與協作背景
├── package.json                         # Node/簡報工具設定
└── pnpm-lock.yaml
```

## End-to-End Flow

```text
Microphone / System Audio
        |
        v
macOS capture services
        |
        v
16 kHz mono PCM16 conversion
        |
        v
100 ms binary WebSocket audio frames
        |
        v
FastAPI transcription session
        |
        v
speech-window segmentation + STT provider
        |
        v
transcript.final events
        |
        v
SwiftUI transcript state
        |
        +--> Meeting notes / next actions draft
        |
        +--> Assistant button request
                 |
                 v
          preprompt + recent transcript
                 |
                 v
          selected AI provider
                 |
                 v
          JSON drafts / notes / actions
```

核心設計是把「音訊小封包」、「語音段落」、「逐字稿事件」和「AI 建議」分開。音訊可以每 100 ms 送一次，但 AI 不應該每 100 ms 被呼叫；目前 AI 是由按鈕觸發，使用最近的逐字稿作為上下文。

## macOS Audio Pipeline

App 目前有兩條音訊來源，並且刻意分開處理：

- 麥克風：`AVAudioEngine` + input tap，來源標記為 `microphone`，UI 顯示為 `Self`。
- 系統音訊：`ScreenCaptureKit` 的 `.audio` stream output，來源標記為 `system`，UI 顯示為 `Other`。

分開來源的理由是會議助理需要知道「自己說的」和「對方說的」大概來自哪裡。這不是完整 speaker diarization，但對 MVP 已經比把全部音訊混成一軌更可控。

音訊格式轉換流程：

1. 麥克風由 `PCM16AudioConverter` 使用 `AVAudioConverter` 轉成 16 kHz、mono、PCM16 little-endian。
2. 系統音訊由 `SampleBufferPCM16AudioConverter` 先把多聲道混成 mono，再線性重取樣到 16 kHz，最後轉 PCM16。
3. `TranscriptionWebSocketClient` 把 PCM16 buffer 聚合成 3,200 bytes 一包，也就是 16,000 samples/sec * 2 bytes / 10 = 約 100 ms。
4. 麥克風和系統音訊各自開一條 WebSocket session，送到同一個 backend endpoint。

WebSocket 連線開始時，client 先送：

```json
{
  "type": "session.start",
  "session_id": "macos-microphone-...",
  "source": "microphone",
  "sample_rate": 16000,
  "channels": 1,
  "sample_width": 2
}
```

之後才送 binary PCM16 音訊 frame。App 也會定期送 `client.ping`，用 `server.pong` 估算 backend round-trip latency。

## Speech Segmentation and STT

後端入口是：

```text
ws://127.0.0.1:8765/v1/transcribe/ws
```

`TranscriptionSession` 會解析 `session.start`，建立對應的 STT provider，然後持續接收 binary PCM16 frames。

目前有兩種 STT 行為：

- `mock`：不跑模型，固定依 `partial_interval_ms` 和 `final_interval_ms` 回傳假逐字稿，用來測 UI 和 WebSocket。
- `faster-whisper` / `mlx-whisper`：使用 speech-window segmenter 切段，切完一段後才送模型，回傳 `transcript.final`。

真實 STT provider 的切段邏輯在 `SpeechWindowSegmenter`：

- 先用 PCM16 RMS 做簡單 speech detection。
- 還沒聽到 speech 前，前置 silence 會被忽略。
- 聽到 speech 後開始累積 audio window。
- 累積至少 `MEETING_BACKEND_SEGMENT_MIN_MS` 後，如果尾端 silence 超過 `MEETING_BACKEND_SEGMENT_SILENCE_MS`，就 finalize。
- 如果一直沒有 silence，超過 `MEETING_BACKEND_SEGMENT_MAX_MS` 會強制切段。
- session 結束時會 flush 尚未送出的 speech segment。

預設參數：

```text
MEETING_BACKEND_SEGMENT_MIN_MS=800
MEETING_BACKEND_SEGMENT_SILENCE_MS=700
MEETING_BACKEND_SEGMENT_MAX_MS=12000
MEETING_BACKEND_VAD_RMS_THRESHOLD=0.012
```

STT provider 的處理方式：

- `faster-whisper`：把 PCM16 bytes 轉成 float32 numpy array，呼叫 WhisperModel `transcribe()`，目前 `beam_size=1`，並關閉 provider 內建 VAD，因為前面已經先做 segmenting。
- `mlx-whisper`：把該 speech window 寫成暫存 WAV，再呼叫 `mlx_whisper.transcribe()`，適合 Apple Silicon demo。

逐字稿事件會長這樣：

```json
{
  "type": "transcript.final",
  "segment_id": "seg_macos-microphone-..._0001",
  "source": "microphone",
  "speaker_hint": "self",
  "start_ms": 0,
  "end_ms": 2400,
  "text": "逐字稿內容",
  "revision": 1,
  "is_final": true,
  "confidence": 0.0,
  "provider": "mlx-whisper"
}
```

SwiftUI 端用 `segment_id` 更新或新增 transcript line。UI 目前最多保留最近 24 行，Assistant request 會取最近 16 行當上下文。

## AI Assistant Pipeline

Assistant 目前由右側按鈕觸發：

- `What should I say?`
- `Follow-up questions`

按下按鈕後，macOS App 會把最近逐字稿送到：

```http
POST /v1/assistant/respond
```

request 形狀：

```json
{
  "action": "what_should_i_say",
  "provider": "ollama",
  "model": "llama3.2",
  "thinking": "medium",
  "transcript": [
    {
      "source": "system",
      "source_label": "Other",
      "speaker_hint": "other",
      "start_ms": 1200,
      "end_ms": 4200,
      "text": "對方剛剛問的問題",
      "is_final": true
    }
  ]
}
```

後端會依 UI 選到的 provider dispatch：

- `mock`：本地固定回覆，方便 demo。
- `ollama`：呼叫 `http://127.0.0.1:11434/api/chat`。
- `openai-compatible`：呼叫 `/chat/completions`，可接 LM Studio、vLLM、llama.cpp、OpenAI API 等相容端點。
- `codex-cli`：執行 `codex exec`，使用 read-only sandbox、ephemeral session、approval disabled。
- `github-copilot-cli`：透過 `gh copilot` 呼叫。

Provider、model、thinking 都可以在 App 裡選。App 會先呼叫：

```http
GET /v1/assistant/providers
```

取得可用 provider、models、auth mode 和 endpoint risk。

## Is There a Preprompt?

有。現在的 preprompt 在 backend 的 `build_messages()` 裡，分成 system message 和 user message。

system preprompt 的重點是：

- 你是即時會議助理。
- 只能使用 transcript context。
- 不要編造事實。
- 只回 JSON。
- JSON 必須包含 `drafts`、`notes`、`actions`。
- `drafts` item 需要 `title`、`detail`、`badge`、`icon_name`。
- `notes` item 需要 `title`、`detail`。
- `actions` item 需要 `title`、`owner`、`state`。

user message 會放：

- `Action`：例如 `what_should_i_say` 或 `follow_up_questions`。
- `Thinking setting requested by user`：例如 `none`、`low`、`medium`、`high`、`xhigh`。
- 任務說明。
- 最近 16 行 transcript context。
- `Return compact JSON only.`

不同 action 會有不同任務說明：

- `what_should_i_say`：產生 2 到 3 句自然、簡短、可直接說出口的回覆。若逐字稿不是明顯英文，優先用口語中文。
- `follow_up_questions`：產生 3 個實用追問，聚焦目標、限制、責任歸屬或時程。
- `meeting_notes`：根據逐字稿整理會議筆記與下一步。

目前這是簡化版 prompt contract。下一階段應該把輸出 schema 版本化，例如 `suggested_reply_v1`、`follow_up_questions_v1`、`meeting_notes_v1`，再加 JSON Schema validation、重試和 evidence segment ids，降低模型格式漂移與幻覺風險。

## Meeting Notes and Next Actions

目前 App 有兩層筆記邏輯：

- 本地 draft：每收到一個 final transcript line，就用該段文字更新「最新重點」與「Review transcript segment」。
- 自動整理：`Connect STT` 後，右側 Meeting Notes 會顯示 30 秒圓形倒數；倒數到 0 時，用最近 16 段 final transcript 呼叫 `/v1/assistant/respond` 的 `meeting_notes` action。
- AI response：如果 auto summary 或按鈕請求回傳 `notes` / `actions`，UI 會用 provider 回來的內容取代本地 draft。

目前的低頻增量管線：

- 即時字幕：跟 STT event 走，越快越好。
- 回覆建議：由 `What should I say?` 和 `Follow-up questions` 按鈕觸發。
- 會議筆記：每 30 秒自動整理一次，只使用 final transcript，避免 partial transcript 把筆記帶歪。
- 會後整理：仍可再用較高品質模型重整 decisions、action items、risks、open questions。

## Model and Provider Strategy

這個專題的模型策略不是綁死單一 API，而是建立 provider abstraction：

- STT provider 負責把 audio segment 轉 transcript。
- Assistant provider 負責把 transcript context 轉成 structured JSON。
- UI 不直接依賴特定模型的輸出格式，而是吃 backend normalize 過的 `drafts`、`notes`、`actions`。

推薦 MVP 組合：

- Apple Silicon demo：`mlx-whisper` + `large-v3-turbo`。
- 快速 UI 測試：`mock` STT + `mock` assistant。
- 本機 LLM：`ollama` assistant。
- 外部或相容端點：`openai-compatible` assistant。

Codex CLI 和 GitHub Copilot CLI 目前被當成 assistant provider 實驗路線。它們適合展示「可串自己的 agent / API」，但正式會議話術預設仍應優先用低延遲 chat provider，因為 CLI agent 啟動成本和行為邊界比較不適合高頻即時回覆。

## Privacy and Data Boundaries

目前原型的資料邊界：

- 原始音訊只送到 backend STT WebSocket。
- Assistant API 只接收逐字稿文字與 metadata，不接收音訊。
- 若 provider 是本機 `mock`、`ollama` 或 localhost OpenAI-compatible endpoint，文字留在本機服務。
- 若 provider 指向外部 API，逐字稿文字會送出本機。
- API key 由 backend environment 提供，macOS App 不直接保存 key。

未來若要做正式產品，會議前需要明確告知錄音、轉寫、模型處理、保存期限與刪除方式。高敏感場景應預設 local-first、短 TTL、可見 recording/assistant-on 指示，並允許會後刪除。

## Run the Prototype

啟動 backend：

```bash
cd apps/backend
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -e ".[stt]"
MEETING_BACKEND_PROVIDER=mock ./scripts/dev.sh
```

Apple Silicon 本機 STT demo：

```bash
cd apps/backend
source .venv/bin/activate
python -m pip install -e ".[mlx-whisper]"
MEETING_BACKEND_PROVIDER=mlx-whisper \
MEETING_BACKEND_MODEL=large-v3-turbo \
./scripts/dev.sh
```

Ollama assistant demo：

```bash
cd apps/backend
source .venv/bin/activate
MEETING_BACKEND_ASSISTANT_PROVIDER=ollama \
MEETING_BACKEND_ASSISTANT_MODEL=llama3.2 \
./scripts/dev.sh
```

OpenAI-compatible assistant demo：

```bash
cd apps/backend
source .venv/bin/activate
MEETING_BACKEND_ASSISTANT_PROVIDER=openai-compatible \
MEETING_BACKEND_ASSISTANT_OPENAI_BASE_URL=http://127.0.0.1:1234/v1 \
MEETING_BACKEND_ASSISTANT_MODEL=local-model \
./scripts/dev.sh
```

Build macOS App：

```bash
cd apps/macos/MeetingAssistantPrototype
./Scripts/build-app.sh
open .build/app/MeetingAssistantPrototype.app
```

第一次測試需要 macOS 權限：

- Microphone：麥克風權限。
- Screen Recording：ScreenCaptureKit 擷取系統音訊需要螢幕錄製權限，授權後通常要重開 App。

App 預設連到：

```text
ws://127.0.0.1:8765/v1/transcribe/ws
```

也可以用環境變數改 endpoint：

```text
MEETING_BACKEND_WS_URL=ws://127.0.0.1:8765/v1/transcribe/ws
MEETING_BACKEND_HOST=127.0.0.1
MEETING_BACKEND_PORT=8765
```

## Validation

後端測試：

```bash
cd apps/backend
source .venv/bin/activate
python -m pip install -e ".[stt]"
python -m pytest
```

可以用 test client 對 backend 做 WebSocket smoke test：

```bash
cd apps/backend
source .venv/bin/activate
MEETING_BACKEND_PROVIDER=mock ./scripts/dev.sh
python scripts/send_test_audio.py
```

## Current Limitations

- 真實 STT provider 目前以 speech window 輸出 `transcript.final`，還不是完整 token-level streaming partial。
- RMS VAD 很輕量，但不如 Silero/WebRTC VAD 穩，噪音環境需要再調參或替換。
- `speaker_hint` 目前只根據來源推斷 `self` / `other`，不是完整 speaker diarization。
- Assistant prompt 目前是簡化 JSON contract，還沒有正式 JSON Schema validator。
- 會議聊天框還未成為獨立路由；目前優先完成兩個按鈕和筆記/action drafts。
- 長會議的 rolling summary、SQLite append-only event log、evidence segment ids 還在規劃階段。

## Next Technical Steps

1. 把 transcript event 存成 append-only meeting event log。
2. 加入 SQLite schema，保存 sessions、transcript segments、assistant suggestions、notes、actions。
3. 把 assistant 輸出改成版本化 schema，加入 validator 與 retry。
4. 增加 rolling summary，避免每次把整場逐字稿丟給模型。
5. 將 `What should I say?`、`Follow-up questions`、`meeting_notes`、`chat` 拆成獨立 prompt/template。
6. 測試 Zoom、Google Meet、Teams 的系統音訊擷取穩定性。
7. 加入 latency metrics：capture-to-final、backend RTT、button-to-suggestion、notes refresh latency。
