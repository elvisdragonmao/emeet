# MeetingAssistantPrototype

macOS App 原型，用來測試兩個會議助理最重要的輸入來源：

- 麥克風：`AVAudioEngine`
- 系統音訊：`ScreenCaptureKit` 的 `.audio` stream output

```text
MeetingAssistantPrototype/
├── Package.swift
├── Sources/
│   └── MeetingAssistantPrototype/
│       ├── App/
│       ├── Audio/
│       ├── ScreenCapture/
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
