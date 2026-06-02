# Apple Silicon 即時會議助理技術可行性 筆記

## 重點整理
- 這篇的結論是：Apple Silicon 上做即時 macOS 會議助理是可行的，但要把「即時」拆成不同層級，不是一個單一數字。
- 會議中最重要的不是完整答案多漂亮，而是第一個有用片段能不能在對話節奏內出現。
- UI 互動要幾乎立刻回饋，目標大約 50 到 100 ms 內。
- 即時字幕的第一段部分文字理想上約 300 到 700 ms 可見，通常 1.5 秒內還算可接受。
- 回覆輔助的第一個有用片語最好在 0.8 到 1.5 秒內出現，超過 2 秒就比較像事後建議。
- 會議筆記和行動項目不需要跟 turn-taking 一樣快，可以每 30 到 90 秒或主題邊界更新。
- STT 最好分 hypothesis 和 confirmed：不穩定文字拿來顯示即時感，穩定文字拿來做筆記、行動項目和搜尋。
- Apple SpeechAnalyzer/SpeechTranscriber 是很有潛力的 Apple-native STT 路線，但受 macOS 版本限制。
- WhisperKit 和 whisper.cpp 是 Apple Silicon 上很強的本機 STT 選項，尤其適合隱私、離線和長會議。
- 本機 LLM 可以做短建議，但要用小型量化模型，因為生成速度受記憶體頻寬限制很明顯。
- M1 Air 等級可以跑短 prompt 和短輸出，但不適合重型 agent；M2 Pro、M3 Max 會舒服很多。
- M3 Pro 不一定在生成上比 M2 Pro 好，因為 decode 很吃記憶體頻寬。
- 長會議 slowdown 的主要原因不是晶片本身，而是上下文一直長、queue 無界、prompt 越來越大、網路抖動累積。
- 雲端模型品質高，但會引入網路延遲和資料外送；適合明確按鈕觸發、fallback 或較重的筆記生成。
- GitHub Copilot/Codex 不應被當成本機會議模型後端，它們偏開發者和 coding workflow。

## 對專題的影響
- 「即時」這個詞不能隨便用，最好在專題中明確定義字幕、建議、筆記三種延遲目標。
- MVP 應該先追求 p95 可用，而不是只展示一次很快的 demo。
- 「What should I say?」要走最快路徑：短上下文、短 prompt、短輸出、串流顯示。
- 「Follow-up questions」可以用稍微多一點的摘要脈絡，但仍要限制輸出數量。
- 互動式聊天框不應直接吃整場會議全文，應建立在穩定逐字稿、rolling summaries 和筆記 state 上。
- 本機模型可作隱私模式或網路不穩 fallback，但高品質自然回覆可能仍要雲端模型補強。
- 若目標硬體包含 M1/M2 消費級筆電，必須嚴格限制本機 LLM 的模型大小、上下文長度和輸出長度。
- 長時間會議要當成 90 分鐘以上的 soak run 來測，不然 demo 看起來正常，實際會議可能越跑越慢。
- 需要把量測框架做進系統，才能知道瓶頸在音訊、STT、LLM、網路還是 UI。

## 可以採用的做法
- 架構拆成三條 pipeline：字幕 pipeline、輔助 pipeline、筆記 pipeline。
- 字幕 pipeline：音訊擷取、VAD、降噪、串流 STT、hypothesis 顯示、confirmed commit。
- 輔助 pipeline：觀察最近對話、偵測問題或按鈕、用短 prompt 產生可說出口的建議。
- 筆記 pipeline：只吃 confirmed transcript，以 30 到 90 秒窗口做階層式摘要和行動項目。
- 第一版採 local-first STT，例如 Apple Speech 路線、WhisperKit 或 whisper.cpp，再接雲端/本機 LLM。
- 本機 LLM 先用 1B 到 3B 或量化 7B 以下模型，並把回答限制成短句。
- 雲端 LLM 用在更高品質改寫、複雜分析、會後筆記、明確按鈕觸發。
- 對音訊 buffer 設定有界 queue，不要讓 backlog 在長會議中無限成長。
- 保持 websocket 或供應商連線溫熱，但要準備網路變差時切回本機 STT 或本機短建議。
- 對每個階段打 signpost：audio capture、STT first partial、STT final、question detected、LLM first token、first useful phrase、UI displayed。
- benchmark 指標至少包含 p50、p95、p99，不只看平均。
- 90 分鐘壓力測試要看延遲是否漂移、記憶體是否成長、queue depth 是否增加、耗電和熱是否上升。
- release gate 可以設：p95 caption partial < 1.5 秒、p95 first useful suggestion < 2 秒、沒有 >100 ms 主執行緒 stall。
- 如果要展示隱私能力，就做 local-only mode：本機 STT、本機簡短建議、本機筆記、本機儲存。

## 風險與待確認
- Apple 新語音 API 的公開 benchmark 不一定足夠，專題要自己測目標硬體和語言。
- WhisperKit、whisper.cpp 的速度和準確率會受模型大小、語言、噪音、重疊說話影響。
- 本機 LLM 的品質可能不足以處理細膩社交語境，特別是中文、混合語言、專業術語會議。
- 雲端模型雖快，但真實延遲取決於 Wi-Fi、RTT、jitter、供應商端負載和 reconnect。
- 工具呼叫可能造成串流停頓，不適合放在「What should I say?」的熱路徑。
- 長上下文很容易讓 prompt prefill 和 KV cache 成本上升，必須有摘要和裁切策略。
- 不同 Apple Silicon SKU 的表現不只看世代，還要看記憶體頻寬、散熱和 RAM。
- 無風扇或輕薄筆電長時間跑本機模型可能熱降頻。
- 若專題宣稱 real-time，最好用實測數據支持，不要只用供應商宣傳資料。
