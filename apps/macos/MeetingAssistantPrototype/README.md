# MeetingAssistantPrototype

macOS App 原型，用來測試兩個會議助理最重要的輸入來源：

- 麥克風：`AVAudioEngine`
- 系統音訊：`ScreenCaptureKit` 的 `.audio` stream output
- 本機逐字稿：把麥克風音訊轉成 16 kHz mono PCM16，送到 backend websocket
- 會議助理工作台：即時逐字稿、`What should I say?`、`Follow-up questions`、會議筆記與下一步行動區塊

```text
MeetingAssistantPrototype/
├── Package.swift
├── Sources/
│   └── MeetingAssistantPrototype/
│       ├── App/
│       ├── Audio/
│       ├── ScreenCapture/
│       ├── Transcription/
│       └── UI/
├── Support/
│   └── Info.plist
├── Scripts/
│   └── build-app.sh
└── Tests/
```

## Build

```bash
cd apps/macos/MeetingAssistantPrototype
./Scripts/build-app.sh
open .build/app/MeetingAssistantPrototype.app
```

如果 `xcodebuild` 仍指向 Command Line Tools，可以先用：

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

第一次測試需要授權：

- Microphone：對麥克風說話後，Microphone 波形應該會動。
- Screen Recording：授權後可能要重開 App；播放 YouTube、音樂或會議聲音後，System Audio 波形應該會動。

## Local transcription

先啟動 backend：

```bash
cd ../../backend
. .venv/bin/activate
./scripts/dev.sh
```

App 預設連到：

```text
ws://127.0.0.1:8765/v1/transcribe/ws
```

在 App 裡按 `Connect STT` 會自動開始麥克風擷取，並把音訊串流到 backend。若 backend 使用 `mock` provider，會先看到假的 partial/final transcript；若使用 `faster-whisper` provider，會跑本機開源模型。

右側的 action buttons 目前先產生本地 placeholder draft，尚未串接 LLM provider。後續可把按鈕事件接到獨立的 assistant backend route。

Apple Silicon 本機 demo 建議用 MLX backend：

```bash
cd ../../backend
. .venv/bin/activate
python -m pip install -e ".[mlx-whisper]"
MEETING_BACKEND_PROVIDER=mlx-whisper MEETING_BACKEND_MODEL=large-v3-turbo ./scripts/dev.sh
```

App 也會讀取環境變數來切換 backend endpoint：

```bash
MEETING_BACKEND_PORT=9000 .build/app/MeetingAssistantPrototype.app/Contents/MacOS/MeetingAssistantPrototype
```

可用的 client-side env：

```text
MEETING_BACKEND_WS_URL=ws://127.0.0.1:8765/v1/transcribe/ws
MEETING_BACKEND_HOST=127.0.0.1
MEETING_BACKEND_PORT=8765
```
