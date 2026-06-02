# MeetingAssistantPrototype

macOS App 原型，用來測試兩個會議助理最重要的輸入來源：

- 麥克風：`AVAudioEngine`
- 系統音訊：`ScreenCaptureKit` 的 `.audio` stream output
- 本機逐字稿：把麥克風音訊轉成 16 kHz mono PCM16，送到 backend websocket

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
uvicorn meeting_backend.main:app --host 127.0.0.1 --port 8765
```

App 目前固定連到：

```text
ws://127.0.0.1:8765/v1/transcribe/ws
```

在 App 裡按 `Connect STT` 會自動開始麥克風擷取，並把音訊串流到 backend。若 backend 使用 `mock` provider，會先看到假的 partial/final transcript；若使用 `faster-whisper` provider，會跑本機開源模型。
