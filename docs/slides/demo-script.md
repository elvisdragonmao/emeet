# Demo

今天我要 demo 的是我的畢業專題 emeet：一個 macOS 原生的即時會議輔助工具。

現在畫面上是 macOS App 的主工作區。左邊是音訊輸入狀態，中間是逐字稿，右邊是 AI assistant 和會議筆記。

我按下 `Start Meeting` 之後，App 會開始接收兩種聲音：第一個是我的麥克風，第二個是系統音訊，也就是線上會議裡對方的聲音。

這裡可以看到音量 meter 有反應。系統會把兩條聲音分開送到 backend，所以逐字稿可以用 `Self` 和 `Other` 來區分大概是我說的，還是對方說的。

### 0:45 模擬會議對話



接著假設對方問我：

> 這個工具和一般會後摘要產品最大的差異是什麼？如果 demo 現場辨識不穩定，你要怎麼處理？

現在可以看到中間逐字稿開始出現內容。這些 transcript event 不是只存在 UI，它們也會被 backend 記錄起來，後面 AI 生成建議和筆記時都會以這些 final transcript 作為依據。

### 1:20 What should I say?

這時候如果我一時不知道怎麼回答，我可以按右邊的 `What should I say?`。

這個按鈕不會讓 AI 自動替我發言，而是根據最近的逐字稿，產生幾個自然、保守、可以直接說出口的回答建議。

我可以挑其中一個來回答，例如：

> 我們和一般會後摘要工具的差異，是這個工具專注在會議當下。它會把逐字稿即時轉成下一句可以說的話、可以追問的問題，以及穩定更新的會議筆記。就算現場 STT 有雜訊，我也保留 source-based transcript、手動觸發 AI 建議，以及匯出紀錄作為 demo 備案。

這裡的設計重點是：AI 是我的會議副駕，不是自動代替我說話。

### 1:55 Follow-up questions

接著我再按 `Follow-up questions`。

這個功能會根據目前對話，幫我產生可以繼續追問的問題。比如它可能會建議我問：

> 你比較在意 demo 的即時性、準確度，還是會後整理的完整度？

或是：

> 你希望這個工具在真實會議中優先解決哪一種痛點：聽不清楚、來不及回覆，還是會後忘記 action items？

這類問題可以讓對話不要停住，也可以幫我把需求、風險和下一步釐清得更明確。

### 2:25 Meeting Notes 和 Next Actions

右邊下面是 Meeting Notes 和 Next Actions。

這裡不是每 100 ms 就呼叫 LLM，因為那樣成本高，也容易被不穩定的 partial transcript 影響。目前的做法是每 30 秒，用 final transcript 低頻整理一次，所以筆記比較穩定。

你可以看到它會整理出目前討論重點，例如 demo 流程、產品差異、風險處理，也會產生下一步行動，例如確認 demo 腳本、準備備用音訊、測試 provider 切換。

### 2:55 Export

會議結束後，我可以按 `Export`，把這次會議的逐字稿、AI 建議、會議筆記和下一步行動匯出成 Markdown。

這對畢業專題 demo 很重要，因為它不只展示即時互動，也展示會議結束後可以留下可讀、可分享、可追蹤的紀錄。

### 3:15 Provider / Model 切換

最後我想補一個這個專題的架構重點：右邊這裡可以切換 provider 和 model。

也就是說，這個工具不是綁死在單一模型上。它可以接本機 Ollama、OpenAI-compatible server，也保留 Codex CLI、GitHub Copilot CLI 這類 experimental provider。UI 只吃統一後的 JSON 結果，像是 drafts、notes 和 actions，所以 provider 可以替換，介面不用重寫。

### 3:40 收尾

總結來說，這個專題不是要做另一個完整的會議平台，而是做一個私密、低摩擦、macOS 原生、模型可選的即時會議副駕。

它把目前通話中的聲音轉成可信的逐字稿事件，再把逐字稿轉成下一句可以說的話、可以追問的問題、會議筆記和下一步行動。

我接下來會說明它背後的技術架構：音訊擷取、WebSocket 傳輸、STT 分段、assistant provider abstraction，以及本機 SQLite 儲存。

## 對話範例

如果需要請同學或自己播放一段固定內容，可以用下面這段。

**Self**

> 我們今天想確認畢業專題 demo 的流程，包含逐字稿、AI 回覆建議、會議筆記和匯出功能。

**Other**

> 這個工具和一般會後摘要產品最大的差異是什麼？如果 demo 現場辨識不穩定，你要怎麼處理？

**Self after `What should I say?`**

> 我們和一般會後摘要工具的差異，是這個工具專注在會議當下。它會把逐字稿即時轉成下一句可以說的話、可以追問的問題，以及穩定更新的會議筆記。就算現場 STT 有雜訊，我也保留 source-based transcript、手動觸發 AI 建議，以及匯出紀錄作為 demo 備案。

**Follow-up question**

> 你比較在意 demo 的即時性、準確度，還是會後整理的完整度？

**Other**

> 我比較在意它是不是能真的幫助會議當下的回應，而不是只有會後整理。

**Self**

> 這也是我第一版 MVP 的重點，所以我把主要互動放在 `What should I say?` 和 `Follow-up questions`，讓使用者在會議中主動觸發 AI，而不是讓 AI 自動插話。

## 30 秒短版

如果時間很短，可以改用這版。

大家好，我今天 demo 的是 emeet，一個 macOS 原生的即時會議輔助工具。它會同時接收麥克風和系統音訊，產生 `Self` / `Other` 逐字稿，並把逐字稿轉成三種即時輔助：下一句可以怎麼說、可以追問什麼，以及會議筆記和下一步行動。

我按下 `Start Meeting` 後，這裡會看到音訊 meter 和即時逐字稿。當對方問我問題時，我可以按 `What should I say?` 取得自然的回覆建議；也可以按 `Follow-up questions` 讓對話繼續推進。右邊的 Meeting Notes 會每 30 秒根據 final transcript 自動整理，最後可以匯出成 Markdown。

這個專題的重點不是做另一個會後摘要平台，而是一個私密、低摩擦、模型可選的即時會議副駕。
