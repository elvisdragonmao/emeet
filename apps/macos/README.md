# macOS App

建議技術棧：

- SwiftUI：主要視窗、設定、狀態畫面。
- AppKit：浮動 NSPanel、視窗層級、跨 Space 細節。
- AVFoundation / AVAudioEngine：麥克風擷取、音量與音波分析。
- ScreenCaptureKit：螢幕錄製與系統音訊方向的 PoC。

原型應優先驗證平台能力，再拆出正式模組。第一個 milestone 是「能要求權限、開始/停止錄製、看到麥克風音波」。
