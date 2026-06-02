# SwiftUI 輕量會議助理架構與介面設計 筆記

## 重點整理
- 這篇的主要結論是：macOS 會議助理不應該只做成單一主視窗、單一選單列 app 或永遠置頂 overlay，而是混合式介面。
- 最合理的介面組合是主要工作區視窗、MenuBarExtra、會議中的浮動伴隨面板。
- 主要工作區負責歷史、完整逐字稿、筆記、設定、匯出；選單列負責狀態和快速控制；浮動面板負責會議當下的低干擾輔助。
- 會議中 UI 是次要注意力介面，不是主舞台，所以要安靜、短、可掃視。
- 浮動面板不該塞滿完整聊天紀錄，應只顯示最近幾行逐字稿、一到兩張建議卡片、少量明確動作。
- 展開工作區可以用三欄：左邊逐字稿，中間建議與筆記，右邊 AI 聊天。
- 「What should I say?」、「Follow-up questions」、「摘要目前主題」、「擷取行動項目」、「解釋這段」應該是穩定 intent，不只是隨便換 prompt 的按鈕。
- 技術難點不是 SwiftUI 畫面，而是 macOS 權限、音訊擷取、視窗層級、跨 Spaces 行為和長時間效能。
- macOS 13+ 可以當第一版基準，因為有 MenuBarExtra 和 SMAppService；macOS 15+ 可改善 SwiftUI 浮動視窗；macOS 26+ 才有較新的 SpeechAnalyzer/SpeechTranscriber 和 Apple 裝置端模型路徑。
- AVAudioEngine 適合麥克風擷取，但 input bus 一次只能裝一個 tap，所以音訊服務要集中擁有，再分流給 STT、波形、錄音、VAD。
- 遠端會議聲音需要 ScreenCaptureKit 或 Core Audio taps，這會牽涉系統音訊或螢幕錄製權限。
- 全域快捷鍵最好用專門的快捷鍵註冊，不要一開始就走原始 event tap，因為那會引入 Input Monitoring 或 Accessibility 權限。
- SwiftUI 可以負責大部分 UI，AppKit 主要用在 NSPanel、非啟用浮動面板、跨 Space 行為等細節。
- 即時轉錄 UI 容易因為太頻繁更新而卡，逐字稿狀態要避免反覆重算大型陣列。

## 對專題的影響
- 第一版不能只做一個漂亮主視窗，因為會議當下使用者其實需要的是小而即時的面板。
- 產品 demo 可以用「選單列啟動、浮動面板輔助、主視窗看完整紀錄」這個流程，會比較像真的 macOS App。
- 會議中面板的功能密度要克制，否則 AI 助理本身會變成干擾。
- 權限 onboarding 很重要，使用者要先知道為什麼要麥克風、系統音訊、可能的語音辨識權限。
- 如果只能取得麥克風，App 仍要能降級運作，只是遠端參與者轉錄品質會受影響。
- 兩個指定按鈕應該放在浮動面板核心區，不要藏在聊天框裡。
- 完整 AI 聊天框可以放在展開工作區或浮動面板的展開狀態，不應該搶會議中的主要注意力。
- 實作上要先把 audio service、transcription provider、assistant provider 抽開，UI 才能換模型或換 STT。
- 若要支援中文和英文，浮動面板不能用過窄固定高度，否則 CJK 文字容易爆版。

## 可以採用的做法
- App 架構採「一般 macOS app + MenuBarExtra + 浮動 NSPanel」，不要預設做純 agent app。
- 主要視窗保留 Dock 可發現性，等功能成熟後再提供隱藏 Dock icon 或純選單列模式。
- 浮動面板初版尺寸控制在小工具感，內容包含狀態列、最近一句問題、建議回覆、兩個主要按鈕、目前主題和一個行動候選。
- 建議卡片以短句為主，附上複製、釘選、重產生、送到聊天框這類明確動作。
- 預設動作是複製，不要直接替使用者送出訊息到 Zoom、Meet 或 Slack。
- 主工作區用三欄設計：逐字稿來源、建議/筆記工作區、AI 聊天探索區。
- macOS 版本策略可分層：13+ 基準版、15+ 改善浮動視窗、26+ 再接 Apple 新語音與 Foundation Models。
- 用 SwiftUI 建主要 UI、設定、工具列、列表、狀態；用 AppKit 管 NSPanel 與必要視窗行為。
- 全域快捷鍵可用 KeyboardShortcuts 這類成熟套件，App 內快捷鍵用 SwiftUI `.keyboardShortcut`。
- 音訊擷取服務做成單一 owner，從 AVAudioEngine tap 分流出 AsyncStream 給 STT、VAD、錄音和 UI。
- STT 與助理模型定義成 protocols，像 `TranscriptionProvider`、`AssistantProvider`、`AssistantIntent`。
- 延遲和效能用 Logger、OSLog、signpost 量測，不要只靠 print 和主觀感覺。
- 本機資料可先用 SwiftData 或 SQLite/GRDB，視是否需要大量搜尋和明確 schema 決定。
- 無障礙上，建議卡片應該可用鍵盤操作，且整張卡片有清楚 accessibility label 和 actions。
- 在地化上，靜態 UI 用 String Catalogs，模型回覆語言另外做設定，不要強迫跟 UI 語言相同。

## 風險與待確認
- 遠端參與者音訊擷取是最大平台風險，要實測 Zoom、Meet、Teams、藍牙耳機、多螢幕和全螢幕。
- ScreenCaptureKit 和 Core Audio taps 的權限體驗要做清楚，不然使用者會覺得 App 在監控。
- 浮動面板跨 Space、全螢幕、置頂層級不一定每種情境都完美，需要實測。
- 純 overlay/HUD 看起來吸引人，但容易侵入、脆弱，也可能破壞 macOS 使用習慣。
- 如果逐字稿 delta 更新太頻繁，SwiftUI 可能卡在 layout 和 state diff。
- 「插入到目前 app」會牽涉 Accessibility 自動化權限，第一版不要當核心功能。
- macOS 26+ 的 Apple 原生新能力很有吸引力，但不適合當第一版唯一依賴。
- CJK、長英文單字、不同字體大小和 VoiceOver 都要測，否則面板可能在 demo 時爆版。
- 需要決定 App 是 App Store 發佈、校內展示或獨立發佈，因為權限、套件和更新機制會受影響。
