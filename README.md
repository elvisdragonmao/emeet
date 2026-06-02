# Meeting Assistant Capstone

這個 repo 是畢業專題「macOS 會議輔助工具」的工作區，目標是做出一個能錄製會議脈絡、產生即時逐字稿、整理會議筆記，並提供 AI 回應建議的 macOS App。

## Project Layout

```text
.
├── apps/
│   └── macos/
│       └── MeetingAssistantPrototype/   # macOS App 原型
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

## Technical Direction

第一版建議走原生 macOS App，而不是 Electron。這個題目的核心風險在 macOS 權限、麥克風、ScreenCaptureKit、低延遲音訊處理與未來浮動面板；SwiftUI + AppKit + AVFoundation 能直接碰到平台 API，之後接逐字稿和 AI provider 也比較乾淨。

建議 MVP 順序：

1. 麥克風擷取與音波/音量確認。
2. ScreenCaptureKit 螢幕錄製權限與畫面預覽。
3. 麥克風音訊與系統/會議音訊分路處理。
4. 即時逐字稿 provider protocol。
5. AI assistant provider protocol，支援自帶 API key 與模型選擇。
6. 會議筆記、行動項目、對話輔助按鈕。
