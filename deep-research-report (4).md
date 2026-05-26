# macOS 會議助理的音訊分塊與即時處理策略研究報告

## 執行摘要

對於 macOS 會議助理這類產品，最穩健的初始架構不是「把音訊每隔固定幾秒丟進 AI」，而是把系統拆成三層：第一層用 macOS 原生音訊管線擷取麥克風與會議音訊；第二層用串流 STT 持續產生 **partial / volatile** 與 **finalized** 逐字稿；第三層再以「穩定文字事件」而不是原始音訊事件，驅動回覆建議、會議筆記、行動項目與互動式聊天。Apple 在最新 SpeechAnalyzer / SpeechTranscriber 設計裡就明確區分了可即時顯示但會改動的 volatile results 與 final results，並提供 finalize 流程；AWS、Google、Azure、Deepgram 也都在官方文件中區分 interim/partial 與 final 事件。這個分層能把低延遲需求與高準確需求解耦，是本題最重要的架構結論。citeturn38view0turn9view0turn26view0turn9view1turn27search7

如果只回答「多久送一次 AI」：**送往 STT 的音訊封包**建議維持在約 **100 ms** 左右，並控制在 **50–200 ms** 的範圍內；AWS 官方明確建議 PCM 串流 chunk 設為 50–200 ms，Google 也警告過大或過於爆量的 chunk 會降低 VAD timeout 的準確性，而串流辨識本身只支援 gRPC。**送往 LLM 的上下文更新**則不應跟音訊封包同頻，而應採 **混合觸發**：在偵測到穩定子句/句子邊界時立即更新，若對方長時間連續發言則以 **6–10 秒心跳更新**補齊；**會議筆記 / action items** 則以 **30–60 秒** 或 **8–12 個 finalized utterances** 為一輪更新。對回覆建議而言，30 秒更新幾乎一定過慢；對筆記整理而言，30–60 秒通常可接受。citeturn32view0turn12view2turn9view5turn23search0turn23search1

VAD 的選型上，若你要一個可今天就上線、CPU 成本低、效果又比傳統門檻法穩定很多的方案，**Silero VAD** 是最好的預設值；如果你極度在意依賴少、原生 C/C++ 易整合，**WebRTC VAD** 仍是極佳的 fallback。近期一篇比較 WebRTC、Silero 與 RMS 的研究指出，Silero 在該測試集上明顯優於 WebRTC，而 hysteresis 對 WebRTC 有幫助、對 Silero 幫助不大；Silero 官方實作本身也提供 threshold、min_silence_duration_ms、speech_pad_ms 等可直接拿來調參的欄位。若你需要高品質重疊語音處理、較強的 nearline diarization / segmentation，pyannote 更強，但它更重，不適合作為最前線低延遲 gate。citeturn22view1turn20search10turn20search1turn6search1turn21search4turn21academia20

若產品目標包含「當下能看、之後要準」，最佳策略不是在所有功能上追求同一種 latency，而是做 **雙軌輸出**：**顯示層**依賴 partial/volatile transcript，讓 UI 快速更新；**儲存層與筆記層**只在 final 或高穩定度條件成立時 commit。這點也符合多家 STT 官方介面：Google 會在 interim 結果提供 `stability`，AWS 會提供 `IsPartial` 與每詞 `Stable` 標記，Azure 的 `Recognizing` 只給文字估計與 offset/duration，而 `Recognized` 才是完成 utterance 後的最終結果；Deepgram 則把 `is_final` 與 `speech_final` 分開。你的資料結構必須原生支援「同一時間軸片段被修訂」這件事。citeturn26view0turn15view1turn9view1turn27search1turn27search3

在 macOS 上，建議把 **麥克風** 與 **系統/會議音訊** 儘量分流擷取：麥克風可用 AVAudioEngine input tap，若涉及喇叭回授與語音通話場景，Apple 的 voice processing APIs 內建 echo cancellation、noise suppression、automatic gain control；系統/會議音訊則可用 ScreenCaptureKit 擷取，官方文件與 WWDC 內容指出其可提供高品質低 CPU overhead 的 screen/audio capture，支援設定 audio sample rate 與 channel count，並可達 48 kHz stereo。若支援 macOS 15 以上，ScreenCaptureKit 也有 `captureMicrophone` 屬性可用。對外傳輸前，再在本機 downmix / resample 成 16 kHz 或 24 kHz mono PCM16 給雲端 STT，或直接餵給 Apple SpeechAnalyzer / 本機 Whisper 管線。citeturn37view0turn34view0turn35search0turn35search11turn35search13turn29search14

## 延遲目標與設計原則

人類對話的換手極快。跨語言會話研究顯示，turn transition 的平均 gap 大約在 **200 ms** 左右，而較一般性的綜述也指出日常會話的 median latency 常低於 **300 ms**。這意味著，如果你的系統是在對方完全講完後，才把最後一大段文字送進 LLM、再等模型生成建議，那麼多半趕不上使用者要回話的時機。對會議助理而言，真正可行的做法是：**在對方說話期間，就用 partial transcript 預先滾動生成候選建議；在句界或 endpoint 出現時，只做輕量 rerank、補完與 UI 更新。** 這個原則比任何單一 chunk 大小更重要。citeturn23search0turn23search1turn23search14turn27search7turn38view0

因此，建議將產品延遲目標拆成四個不同服務等級。**即時字幕**以「越早越好」為主，partial 更新應以數百毫秒級的節奏持續滾動；**回覆建議**若是主動畫面上的「可能怎麼回」，應該在穩定語意邊界後 **500–1000 ms** 內完成第一次可用更新，最好在對方仍在發話時就預先計算；**按鈕式請求**例如「What should I say?」可接受稍慢，但仍應盡量壓在 **1–2.5 秒** 內；**筆記 / action items** 可接受較高延遲，通常 **15–60 秒** 都在合理範圍，會議結束後再做一次高品質整合即可。前兩者是 conversation-critical path，後兩者不是。前者應以 partial + stable boundary 為主，後者應以 finalized transcript 為主。這些時間目標不是某一家 API 的硬規格，而是根據人類 turn-taking、STT interim/final 行為與會議助理使用情境推導出的工程目標。citeturn23search0turn23search1turn9view0turn26view0turn9view1turn27search1

下圖是最建議的整體資料流：把音訊擷取、串流辨識、逐字稿狀態管理、建議生成與摘要生成分開，讓每層可以各自做不同頻率的更新與不同品質等級的 commit。這個分層同時符合 Apple 新 SpeechAnalyzer 的結果模型、雲端 STT 的 interim/final 模型，以及 Whisper-Streaming 這類本機串流轉寫實作對「confirmed/unconfirmed」的分離。citeturn38view0turn17view1turn27search7turn26view0

```mermaid
flowchart LR
    A[麥克風 AVAudioEngine / VoiceProcessing] --> B[本機格式統一<br/>48k/44.1k -> 16k mono PCM16]
    A2[會議/系統音訊 ScreenCaptureKit] --> B
    B --> C[VAD + 句界/語意邊界]
    B --> D[串流 STT]
    C --> D
    D --> E[Partial / Volatile 緩衝]
    D --> F[Finalized Segment Store]
    E --> G[即時字幕 UI]
    E --> H[預先生成回覆候選]
    F --> I[滾動摘要 / 行動項目]
    F --> J[互動式 Chat 檢索上下文]
    H --> K[回覆建議 UI]
    I --> L[Meeting Notes UI]
    J --> M[使用者按鈕與 Chat Box]
```

## 分塊策略比較

如果把「分塊」拆開看，實際上有三種不同層級：**傳輸分塊**、**辨識分塊**、**語意分塊**。傳輸分塊是你多久送一次音訊封包；辨識分塊是 STT 何時產生 partial / final；語意分塊才是你何時把上下文送進 LLM。工程上最常犯的錯是把三者綁成同一個節奏。AWS 官方建議 PCM 音訊以 50–200 ms chunk 傳送；Google 串流辨識限定 gRPC，並警告若音訊 chunk 太大或送得過快會使 voice activity timeout 的測量不準；Deepgram 與 AWS 也都把終點偵測建立在 pause / VAD / word timing 之上，而不是要求你每 5 秒切一次句。這些都指向同一結論：**對 STT，先維持小而均勻的 transport chunks；對 LLM，再用較高層的文字事件節流。** citeturn32view0turn12view2turn9view5turn9view2turn9view0

| 策略 | 典型觸發 | 優點 | 缺點 | 結論 | 主要依據 |
|---|---|---|---|---|---|
| 固定 5 秒 | 每累積 5 秒文字或音訊就送 LLM | 實作簡單；長談話不會餓死 UI | 常在詞中切斷；語意邊界差； token 與重算成本偏高 | 可作 fallback 心跳，但不應是唯一策略 | AWS 建議 transport chunk 小而均勻；Whisper-Streaming 指出 content-unaware segmentation 會造成邊界品質差。 citeturn32view0turn17view1 |
| 固定 10 秒 | 每 10 秒送一次 | 更省 token / API 成本 | 對回覆建議通常偏慢；討論主題常已換檔 | 不適合即時回覆建議，可用於低頻摘要 | 人類 turn gap 極短；STT interim/final 支援更細粒度邊界。 citeturn23search0turn26view0turn9view0 |
| 固定 30 秒 | 每 30 秒送一次 | 成本最低 | 幾乎不適合 conversational suggestion；只適合粗摘要 | 不建議用於 reply suggestions | Whisper-Streaming 明指先錄長段再處理會導致高延遲與差的 segment boundary。 citeturn17view1 |
| 句子邊界 | punctuation + 穩定文字 + 短停頓 | 跟語意最對齊；最適合建議/問答 | 依賴 STT punctuation 與穩定度；長句會拖延 | 最適合 LLM 更新，但要有 heartbeat 補充 | Semantic VAD 以標點/語意輔助 endpoint，可顯著降延遲；多家 STT 都提供 interim/final 與 time offsets。 citeturn24view0turn26view0turn9view1turn15view1 |
| 純 VAD endpoint | silence gap 達閾值即送 | 速度快；不需等待完整句號 | 可能切到半句；噪音場景易誤判 | 適合 trigger「可能講完了」，不適合直接當最終語意塊 | Deepgram endpointing 完全依賴音訊 VAD；噪音環境會失靈。 citeturn11view1turn9view2 |
| 混合式 | 句界優先；若無句界則 6–10 秒 heartbeat；按 utterance_end / speech_final 立即刷新 | latency、品質、成本三者最均衡 | 實作較複雜 | **最推薦的產品策略** | 綜合 Apple volatile/final、AWS/Google/Deepgram 邊界訊號與人類 turn-taking 特性。 citeturn38view0turn15view1turn26view0turn11view0turn23search1 |

就本題的核心問題——**要多久把內容送進 AI**——我的建議是：

第一，**送進 STT 的音訊**：維持 **100 ms** 左右的小封包，並保持均勻節奏；這落在 AWS 官方建議的 50–200 ms 內，也能避免 Google 所警告的大 chunk 對 timeout/endpointing 精度的傷害。第二，**送進回覆建議 LLM 的文字**：不是每 100 ms 送，而是在 **穩定子句/句子邊界** 立即送一次；若對方持續長篇發言、遲遲沒有句界，則用 **6–10 秒心跳更新**一次。第三，**送進 notes / action items LLM 的文字**：以 **30–60 秒** 或 **8–12 個 finalized 段落** 做增量摘要。第四，**使用者按下「What should I say?」** 時，不要只送最後一句，而是送 **最近 1–3 分鐘 finalized transcript + 目前未完成問題的 partial transcript + rolling summary + 已決議事項 / 開放問題**。這樣既能保住語境，也不會把整場會議原文重送給模型。citeturn32view0turn12view2turn9view0turn11view0turn38view0

## VAD 與語意邊界

在 VAD 上，主流工程觀點仍然是「用 acoustic VAD 決定 start/stop」，代表性方案是 WebRTC VAD 與各雲 STT 的內建 endpointing。這條路徑的優勢是成熟、快、工程成本低。WebRTC VAD 的硬限制非常清楚：只接受 16-bit mono PCM，支援 8/16/32/48 kHz，frame 必須是 10/20/30 ms，並提供 0–3 的 aggressiveness mode；WebRTC 原始碼也明確顯示它有針對不同 frame length 與 mode 的不同門檻。這代表它非常適合做前線 gate，但不擅長理解語意是否「說完」。citeturn6search1turn6search11

較新的主流替代方案是 **Silero VAD**。它仍舊夠輕量，但比 WebRTC 更接近現代神經式 VAD：官方 repo 宣稱一個 30+ ms chunk 在單 CPU thread 上小於 1 ms 即可處理，模型很小，支援 8k/16k，並直接暴露 `threshold`、`min_speech_duration_ms`、`min_silence_duration_ms`、`speech_pad_ms` 等參數。2026 年一篇針對真實數位音訊流的比較實驗指出，在其測試集上 Silero 顯著優於 WebRTC，而對 WebRTC 加上 hysteresis 有小幅好處，對 Silero 則幾乎沒顯著收益。這個結果雖然來自小型資料集，不能視為放諸四海皆準，但足以支持「Silero 作為預設，WebRTC 作為 fallback」的工程選擇。citeturn20search1turn20search10turn22view1

較非主流但很值得納入視野的觀點，是 **不要把 endpoint 完全建立在 silence 上**。Semantic VAD 這條研究路線直接把 punctuation prediction 與語意訊號加入 endpoint 判定；其 2023 Interspeech 論文聲稱，相較於傳統尾端 silence-based segmentation，可在後端 CER 幾乎不惡化的情況下，把平均 latency 降低 **53.3%**。Deepgram 的官方文件也間接支持這個方向：它區分了 audio-based endpointing 與以 word timings 為基礎的 `utterance_end_ms`，並明言如果要更快偵測 final result 內部的 gap，client-side 分析往往比純 server-side `utterance_end` 更快。換句話說，**只靠聲學靜音切點是夠用但不是最佳；語意邊界與詞時間戳才是更高階的 trigger。** citeturn24view0turn11view0turn11view1

| VAD / 邊界方案 | 運作方式 | 強項 | 弱項 | 建議用途 | 主要依據 |
|---|---|---|---|---|---|
| WebRTC VAD | 傳統統計式 VAD；10/20/30 ms frame；mode 0–3 | 超輕量、原生整合容易、可寫成純前線 gate | 噪音 / 音樂 / 非典型會議環境較易誤判 | fallback、低依賴部署、前線喚醒與粗 endpoint | citeturn6search1turn6search11 |
| Silero VAD | 輕量神經 VAD；可調 threshold 與 silence/pad | 準確度與魯棒性普遍較佳；CPU 成本仍低 | 仍需模型依賴；與 WebRTC 相比較重 | **預設首選** | citeturn20search1turn20search10turn22view1 |
| pyannote VAD / segmentation | 以 segmentation pipeline 做 speech activity / overlap-aware segmentation | 在重疊語音與 diarization 場景更強，可做 nearline 強化 | 模型重、即時性與部署複雜度較高 | 近即時後處理、會後校正、diarization 強化 | citeturn21search4turn21academia20turn22view0 |
| 純 server endpointing | 由 STT provider 根據 pause/VAD 決定 speech_final | 工程最簡單 | 噪音下可能卡住或過早切斷 | 可作 baseline，但不應是唯一邊界來源 | citeturn9view2turn11view1 |
| 語意邊界 | punctuations + word timings + stability + pause | 最接近「真的說完一個意思」 | 需更多 metadata 與 client logic | **回覆建議、問答、精準切句的首選** | citeturn24view0turn26view0turn15view1 |

建議的初始參數如下，這些是**工程起始值**，不是標準答案。若用 **Silero**，可從 **high threshold 0.50、low threshold 0.35、start hold 120–160 ms、stop silence 500–700 ms、pre-roll 150 ms、post-roll 200 ms** 起跑；若環境有大量鍵盤聲、背景音樂或風扇噪音，可把 high threshold 提到 0.55、low threshold 提到 0.40。若用 **WebRTC**，建議先用 **20 ms frames + aggressiveness mode 2**，再以 **160 ms 連續 speech 才開始、600 ms silence 才結束** 的 hysteresis state machine 包住；當噪音很多時再試 mode 3。若你已經使用雲端 STT，也仍建議保留**本地 client-side VAD / boundary layer**，因為它能讓 UI 與 LLM 在 provider 還沒發 final 之前就先進入預備狀態。這些值應透過實驗再調，但作為第一版足夠合理。支持它們的不是單一來源，而是 WebRTC / Silero 的可調參數設計、雲端 STT 的 endpointing 行為，以及 Semantic VAD 對「靜音不是唯一邊界訊號」的證據。citeturn20search10turn6search1turn22view1turn24view0turn11view1

## 逐字稿狀態模型與滾動摘要

資料模型的核心原則是：**partial 與 final 必須分倉；顯示態與儲存態不能共用同一份可變字串。** 這不是純粹的程式風格問題，而是 STT API 本身的事件語義要求。Apple SpeechTranscriber 會輸出 volatile 與 final 結果，WWDC 範例甚至直接把 `volatileTranscript` 與 `finalizedTranscript` 分開維護；Google 的 `StreamingRecognitionResult` 會在 interim 時提供 `isFinal=false` 與 `stability`；AWS 會回傳 `IsPartial`，並可標記詞級別 `Stable`；Azure 的 `Recognizing` 與 `Recognized` 事件也分別對應可改動估計與 utterance 完成後的 final。這些 API 的共通點是：**你不能假設先看到的文字就是最後會留下來的文字。** citeturn38view0turn26view0turn15view1turn9view1

建議的 storage pattern 是 **event-sourced transcript log + mutable active hypotheses**。也就是說，對每個 channel / speaker / source 維護一個 `active_partial`，它可以被新事件覆蓋；另一方面，所有 finalized segments 以 immutable append-only 方式寫入 `segments[]`。如果 provider 允許更強的 metadata，例如 Google 的 `stability`、AWS 的 `Stable`、Deepgram 的 `is_final` / `speech_final` 與 word timings，就把它們保存在 segment metadata 裡，因為這些欄位之後對 UI 呈現、再次摘要、以及錯誤回溯都很重要。若因斷線或 stream rotate 導致某段 partial 尚未收到 final，就用 `soft_committed=false` 與 `reconciliation_state=pending` 保留，等新的 provider session 或回補批次識別完成後再 reconcile。這比直接「把 partial 接到全文」穩健得多。citeturn26view0turn15view1turn27search11turn31search11

下面的 JSON schema 是適合第一版產品的實務範例：

```json
{
  "event_type": "transcript.partial",
  "stream_id": "meeting-2026-05-25-a",
  "source": "system_audio",
  "channel": 1,
  "speaker_hint": "remote_unknown",
  "segment_id": "seg-active-001",
  "revision": 7,
  "start_ms": 912340,
  "end_ms": 916980,
  "text": "I think we should probably ship",
  "tokens": [
    { "t": "I", "start_ms": 912340, "end_ms": 912480 },
    { "t": "think", "start_ms": 912500, "end_ms": 912790 },
    { "t": "we", "start_ms": 912820, "end_ms": 912940 },
    { "t": "should", "start_ms": 912960, "end_ms": 913220 },
    { "t": "probably", "start_ms": 913260, "end_ms": 913710 },
    { "t": "ship", "start_ms": 913760, "end_ms": 914040 }
  ],
  "provider": {
    "name": "google-stt",
    "is_final": false,
    "stability": 0.78
  },
  "boundary": {
    "vad_state": "speech",
    "pause_after_ms": 180,
    "semantic_boundary": false
  },
  "display": {
    "render": true,
    "persist": false
  }
}
```

```json
{
  "event_type": "transcript.final",
  "stream_id": "meeting-2026-05-25-a",
  "source": "system_audio",
  "channel": 1,
  "speaker_id": "spk_remote_2",
  "segment_id": "seg-004218",
  "supersedes_active_segment_id": "seg-active-001",
  "start_ms": 912340,
  "end_ms": 917420,
  "text": "I think we should probably ship this next week.",
  "words": [
    { "word": "I", "start_ms": 912340, "end_ms": 912480, "confidence": 0.99 },
    { "word": "think", "start_ms": 912500, "end_ms": 912790, "confidence": 0.97 },
    { "word": "we", "start_ms": 912820, "end_ms": 912940, "confidence": 0.98 },
    { "word": "should", "start_ms": 912960, "end_ms": 913220, "confidence": 0.96 },
    { "word": "probably", "start_ms": 913260, "end_ms": 913710, "confidence": 0.91 },
    { "word": "ship", "start_ms": 913760, "end_ms": 914040, "confidence": 0.95 },
    { "word": "this", "start_ms": 914060, "end_ms": 914250, "confidence": 0.95 },
    { "word": "next", "start_ms": 914280, "end_ms": 914510, "confidence": 0.94 },
    { "word": "week", "start_ms": 914540, "end_ms": 914890, "confidence": 0.95 }
  ],
  "provider": {
    "name": "google-stt",
    "is_final": true,
    "speech_final": null
  },
  "boundary": {
    "commit_reason": "semantic_boundary_or_provider_final",
    "pause_after_ms": 620,
    "topic_boundary": false
  },
  "display": {
    "render": true,
    "persist": true
  }
}
```

滾動摘要建議採 **雙層或三層摘要**，不要只有一個 meeting summary。會議助理真正需要的通常是三種上下文：第一種是 **最近 1–3 分鐘 raw finalized transcript**，用來支援按鈕與 chat box 的近場語境；第二種是 **當前議題 rolling summary**，長度控制在約 150–300 tokens，維持最近決策、爭點、待答問題；第三種是 **整場會議摘要**，以較低頻更新，保留大方向、已決議事項與 action items。這樣做可以避免每次按鈕都把整場逐字稿重送出去，也能避免摘要過度壓縮而喪失最新語境。這種設計與 Apple Call Summarization、Notes/Voice Memos 的 transcript→summary 分層思路一致，也符合 Whisper-Streaming / streaming STT 在 confirmed text 上逐步建立穩定上下文的運作邏輯。citeturn38view0turn17view1

可用的 incremental summary schema 例如：

```json
{
  "summary_state": {
    "meeting_id": "meeting-2026-05-25-a",
    "updated_at_ms": 923000,
    "window_start_ms": 840000,
    "window_end_ms": 923000,
    "current_topic": "release planning",
    "rolling_summary_short": "團隊傾向下週發版，但仍有 QA 風險與文件未完成問題。",
    "rolling_summary_long": "本段聚焦發布時程，產品主張下週上線，工程認為需視 QA 與 migration checklist 完成度而定。",
    "open_questions": [
      "QA checklist 是否能在週三前完成？",
      "migration rollback plan 是否已經審核？"
    ],
    "decisions": [
      "暫定以下週為目標發版週"
    ],
    "action_items": [
      {
        "id": "ai-17",
        "owner": "QA lead",
        "task": "在週三前完成 regression checklist",
        "due_hint": "this Wednesday",
        "evidence_segment_ids": ["seg-004201", "seg-004218"]
      }
    ]
  }
}
```

對按鈕操作而言，最實用的 batching 規則是：

**「What should I say?」**：`最近 60–180 秒 finalized transcript` + `當前未完成問題的 partial transcript` + `rolling_summary_short` + `使用者角色/目標`。  
**「Follow-up questions」**：同上，但提示詞偏重 `open_questions`、`未閉合議題`、`尚未確認的風險`。  
**互動式 chat box**：優先檢索 `finalized segments` 與 `rolling summaries`，必要時再回看最近 active partial。  

這樣會比「只送最後一句」穩定得多，也比「每次送整場 transcript」便宜且更快。它是工程上的綜合建議，而不是特定 API 的要求。被引用的官方證據主要支持 partial/final 雙態與時間戳的必要性。citeturn38view0turn26view0turn15view1turn9view1

## macOS 實作架構與串流協定

在 macOS 上，最值得善用的是 Apple 自家兩套能力：**AVAudioEngine / voice processing** 與 **ScreenCaptureKit / SpeechAnalyzer**。針對本題的 meeting assistant，建議基礎 capture 架構為：麥克風路徑使用 `AVAudioEngine.inputNode.installTap(...)` 或更底層的 voice processing I/O；如果你的 app 需要處理本機喇叭回放進入麥克風的回授，Apple 的 voice processing APIs 內建 echo cancellation、noise suppression、automatic gain control，並建議用於 VoIP 類場景。系統或應用程式音訊則由 ScreenCaptureKit 擷取；WWDC 22 明確說明 ScreenCaptureKit 可擷取 screen 與 audio content，支援 sample rate 與 channel count，並且可將音訊配置成 48 kHz stereo。對模型而言，再在本機統一轉成單聲道 PCM16 即可。citeturn34view0turn38view0turn37view0

Apple 最新的 SpeechAnalyzer / SpeechTranscriber 尤其適合做 **local-first STT**。WWDC25 的內容指出，SpeechAnalyzer 透過 async sequence 回傳按音訊時間軸排序的結果；SpeechTranscriber 提供 `.volatileResults` 與 `result.isFinal`；它有 `bestAvailableAudioFormat` 可對齊分析格式，也有 `finalizeAndFinishThroughEndOfInput()` 可在停止時沖刷最後結果。Apple 並明言這套新 STT 模型是為長格式錄音、會議與 live transcription 這類低延遲高準確場景設計，且在裝置上運行，支援部分語言並可用 AssetInventory 下載模型。對不支援語言/裝置，則有 DictationTranscriber fallback。若你的第一版想優先保護隱私、降低雲端成本、在 macOS 上深度整合，這是最值得優先試的 STT 路徑。citeturn38view0

另一方面，若你需要供使用者切換不同外部 STT 或需要更成熟的雲端串流能力，則應做 **provider adapter**，把 STT 與 LLM 徹底解耦。Google Cloud 的串流 STT 是 **gRPC only**，可送 voice activity events 與 timeout，interim 結果有 `isFinal` 與 `stability`；AWS Transcribe 支援 **HTTP/2** 與 **WebSocket**，串流格式支援 PCM/FLAC/Ogg-Opus，且明確推薦 lossless；Deepgram 的 STT 則是 **WebSocket** 為核心，並提供 `endpointing`、`speech_final`、`utterance_end_ms`、`Finalize` message；Azure Speech 主路徑則是 **Speech SDK**，即時辨識可得到 `Recognizing` / `Recognized` 事件，原生輸入格式是 mono 16-bit PCM 8k/16k，也可透過 GStreamer 支援 OPUS/OGG、FLAC 等壓縮格式。這些 provider 應只透過標準化 adapter 暴露出統一事件：`partial`、`final`、`utterance_end`、`error`、`flush_complete`。citeturn9view5turn12view2turn28search0turn32view0turn14view4turn14view5turn27search1turn27search11turn14view2turn14view3

| STT 選項 | 協定 / 介面 | 典型輸入 | Partial / Final 模型 | 優勢 | 風險或限制 | 主要依據 |
|---|---|---|---|---|---|---|
| Apple SpeechAnalyzer / SpeechTranscriber | 本機 API，音訊以 analyzer input stream 餵入 | 由 `bestAvailableAudioFormat` 決定，AVAudioPCMBuffer 先轉換 | `.volatileResults` + `result.isFinal`；支援 finalize | on-device、隱私佳、適合長格式與 live transcription | 語言覆蓋有限，需管理 model install | citeturn38view0 |
| Google Cloud STT | gRPC 雙向串流 | 一般建議 lossless，LINEAR16 / FLAC | `isFinal` + `stability`；有 VAD events/timeouts | 官方 metadata 豐富；語音活動事件清楚 | gRPC only；長串流需處理 stream rotation | citeturn9view5turn26view0turn12view2turn31search0turn14view4 |
| AWS Transcribe | HTTP/2 或 WebSocket | PCM16 / FLAC / Ogg-Opus | `IsPartial`，可開 `Stable` | chunk 建議清楚；partial stabilization 對 subtitle UX 友善 | 高穩定度會犧牲少量準確度 | citeturn28search0turn32view0turn15view0turn15view1 |
| Deepgram Streaming | WebSocket | `linear16`、`opus`、`ogg-opus` 等 | `is_final`、`speech_final`、`utterance_end_ms`、`Finalize` | endpointing/gap detection 工具完整；client/server 邊界彈性大 | `utterance_end_ms` 依賴 interim results；噪音場景仍需 client logic | citeturn14view5turn27search1turn11view0turn27search11 |
| Azure Speech | Speech SDK（平台 SDK 為主） | mono PCM16 8k/16k；壓縮格式可透過 GStreamer | `Recognizing` / `Recognized` | SDK 路徑成熟；final 有 word-level timestamps | `Recognizing` 階段沒有 per-word timestamps | citeturn14view2turn14view3turn9view1 |
| 本機 Whisper 類 | 無固定網路協定；由本地程序處理 | 本機音訊 buffer | 需自行做 confirmed / unconfirmed | 隱私強、可離線；Apple Silicon 生態成熟 | 原始 Whisper 非真串流；naive chunking 容易切壞邊界 | citeturn17view0turn17view1turn18search0turn19search0 |

對編碼與網路的結論也很直接。Google 與 AWS 都建議 lossless 音訊，Google 明白指出 lossy codec 可能降低辨識準確度，尤其是有背景噪音時；AWS 與 Azure 也都把 16-bit mono PCM 視為預設實務格式。這代表若網路不是主要瓶頸，**上行到雲端 STT 的安全預設應是 16 kHz mono PCM16**。若你真的要跨弱網路情境，才考慮 Opus/Ogg-Opus，但應預期額外編碼成本與可能的準確度折損。對 macOS 端來說，ScreenCaptureKit 可先以高品質取樣取得系統音訊，再在本地 downmix / resample；這通常比直接要求 capture source 就輸出低品質 STT 格式更穩。citeturn14view4turn10search5turn32view0turn14view2turn37view0

若你考慮本機 Whisper 路線，必須注意「原始 Whisper 很強，但不是為低延遲串流設計」。OpenAI Whisper 論文本身強調它是基於大規模弱監督資料訓練的強健 ASR 模型；但 Whisper-Streaming 論文明確指出，很多天真的 real-time 實作會先收滿長片段再跑，因此 latency 大、segment boundary 品質差。該論文的 LocalAgreement-2 做法在英語 ESIC 長語音上報告約 **3.3 秒** 平均 latency；以 1 秒 MinChunkSize 時，英語 WER 約比 offline 高 **2%**。如果你要提供「高準確本機模式」，比較合理的是：**用 Whisper / faster-whisper / whisper.cpp 做 near-real-time finalized transcript**，並讓 UI 仍由較快的 partial STT 承擔。不要用單一 naive Whisper chunking 同時解決所有需求。citeturn17view0turn17view1turn18search0turn19search0

下面這張時序圖對第一版實作尤其重要：即時 UI、穩定 commit、回覆建議與摘要更新不應共用同一個 trigger。

```mermaid
sequenceDiagram
    participant Audio as Audio Capture
    participant STT as Streaming STT
    participant Store as Transcript Store
    participant LLM1 as Reply Suggestion LLM
    participant LLM2 as Notes/Summary LLM
    participant UI as UI

    Audio->>STT: 100ms audio packets
    STT-->>Store: partial / volatile result
    Store-->>UI: live caption update

    Note over STT,Store: pause >= 600ms 或 semantic boundary
    STT-->>Store: final result / stable boundary
    Store-->>LLM1: latest topic window + current question
    LLM1-->>UI: reply suggestions

    Note over Store,LLM2: every 30–60s or 8–12 final segments
    Store-->>LLM2: rolling finalized context
    LLM2-->>UI: notes / action items update
```

具體到第一版參數，我會建議直接這樣落地：

**音訊擷取**：麥克風與系統音訊分流；本地保留高品質 buffer，但 STT 路徑統一為 mono PCM16。  
**STT transport**：約 **100 ms** 一包。  
**VAD**：Silero ONNX 預設；high 0.50 / low 0.35；start 120–160 ms；stop 500–700 ms；pre-roll 150 ms；post-roll 200 ms。WebRTC fallback 用 20 ms frame、mode 2。  
**reply suggestions**：在 sentence / stable clause boundary 立即刷新；若無邊界就每 **6–10 秒** 心跳更新。  
**notes / action items**：每 **30–60 秒** 或 **8–12 finalized segments** 更新一次。  
**按鈕批次**：`最近 1–3 分鐘 finalized` + `rolling summary` + `當前 partial 問題` + `會議角色/目標`。  
**停止流程**：先 stop capture，再呼叫 provider flush / finalize；Apple 用 `finalizeAndFinishThroughEndOfInput()`，Deepgram 用 `Finalize` message。citeturn38view0turn27search11turn32view0turn20search10turn6search1

## 測試計畫與評估指標

測試不應只做 ASR 準確率，因為這個產品真正賣點是「即時建議是否來得及、筆記是否可靠、chat 是否拿到正確上下文」。建議把實驗拆成四組 ablation。第一組是 **chunking ablation**：比較固定 5 秒、固定 10 秒、VAD-only、sentence-boundary、hybrid 五種策略，看它們對字幕穩定度、建議延遲與筆記品質的影響。第二組是 **VAD ablation**：WebRTC mode 1/2/3、Silero threshold 0.45/0.50/0.55、min_silence 300/500/700/1000 ms 的組合。第三組是 **STT event policy ablation**：partial only、final only、partial+stability gate、partial stabilization on/off。第四組是 **provider ablation**：Apple on-device、選定的雲端 STT、以及可選的本機 Whisper finalized pass。這些比較最終會直接決定 UX，而不只是 model score。這是本報告的建議性設計，不是特定文獻規範；不過其合理性建立在官方 API 都暴露 partial/final、邊界與 word timing 的事實之上。citeturn38view0turn26view0turn15view1turn9view1

建議的核心量測指標如下。**STT 層**：final transcript 的 WER / CER；time-to-first-partial；speech-end-to-final-commit latency；partial churn rate，亦即某段文字從第一次顯示到 final 為止被改寫了多少字或 token。**建議層**：boundary-to-first-suggestion latency、使用者點擊率、人工評分的 relevance / actionability / tone appropriateness，以及 hallucination / grounding error rate。**筆記層**：summary factuality、action item precision / recall、owner / due-date extraction accuracy、note freshness lag。**系統層**：CPU、記憶體、網路上行、丟包 / 掉 frame、reconnect 後遺失字數。這些指標組合起來，才會反映產品的真實成功條件。citeturn17view1turn23search1turn26view0turn15view1

若要量化「建議多快才算可用」，最值得做的不是只看平均 latency，而是看 **boundary hit rate**：有多少次在對方明顯釋出 turn（停頓、問句、點名你回答）後，系統能在使用者實際開始說話前，已經給出至少一個可用候選。由於人類對話的換手 gap 非常短，這個指標會比平均 latency 更貼近使用者主觀感受。另一個非常重要的指標是 **partial regret**：系統因為過早使用 partial transcript 而生成錯誤建議的比例。若 partial regret 太高，代表你應該把「即時預算」與「最終顯示」再多切開一層，例如先只在背景計算，等穩定度超過門檻再公開顯示。citeturn23search0turn23search1turn26view0turn15view1

一個可操作的 benchmark 套件應至少包含三種會議資料：**安靜單講者螢幕分享**、**多人快速對話與插話**、**混合噪音與遠距收音**。如果產品打算支援本機與雲端兩種 STT，還要再做 **斷網 / 高延遲 / provider timeout** 測試。Google 官方要求 streaming session 最長約 5 分鐘，且音訊必須以接近 real time 的速率送出；Deepgram 官方也提醒斷線後若要回補音訊，最多只能以 **1.25x real-time** 補流，否則 live delay 會快速累積。這意味著你的測試計畫必須包含**長會議 stream rotation** 與 **reconnect strategy**；不測這兩項，長會議產品通常會在真實使用情境中失敗。citeturn31search0turn31search11

### 未決問題與限制

本報告刻意把焦點放在 **macOS 音訊處理策略、STT 事件模型與 LLM 更新節奏**，而不是某一個特定商業 STT/LLM 的最新定價或專屬功能清單。原因是你的產品需求本質上更像「架構設計問題」而不是「單一 provider 選型問題」。仍然存在的開放問題包括：Apple on-device STT 對多語會議與 speaker diarization 的實際表現、你的目標語言組合、是否需要完全離線模式、以及 GitHub Copilot/Codex 這類 BYO API 在你想用的部署模型下是否支援你要的互動模式。這些不影響本報告的整體結論，但會影響最終 provider 組合與 prompt 設計。citeturn38view0turn28search21

## 隱私安全與優先參考資料

這類產品的隱私邊界非常敏感，因為它同時碰到 **麥克風、螢幕/系統音訊、逐字稿、會議摘要、外部 API 金鑰**。在 macOS 端，至少要正確處理麥克風授權、Screen Recording 授權與網路傳輸安全。Apple 文件明言，在 macOS 10.14 之後，相機與麥克風需要明確授權；ScreenCaptureKit 第一次執行時也會要求 Screen Recording 權限；App Transport Security 則是 Apple 平台預設的網路安全基線，用來提高 privacy 與 data integrity。從產品策略上看，**預設應採 local-first**：能在本機完成的 STT 先在本機做；若要把資料送到外部 API，優先送 **finalized text 或精簡摘要**，只在使用者明確選擇時才送原始音訊。citeturn29search11turn29search3turn29search2turn29search6turn38view0

外部 API 金鑰的處理，不應放在 plist、明文設定檔、或可輕易導出的 user defaults。Apple 文件把 keychain 視為儲存小型敏感資訊（密碼、金鑰）的最佳位置，並指出 keychain 項目會被加密儲存在磁碟上。對「使用者自帶 API key」的 meeting assistant，最務實的做法是：**key 存 Keychain；app 內只保留短期 session token / in-memory client；若未必要 proxy，盡量直接由用戶端連 provider；若一定要經你的 server，則 server 僅持有加密後 secrets，並讓使用者可明確切換資料流向。** 這些屬於成熟的本地安全實務。citeturn30search2turn30search1turn30search0

就產品資料治理而言，至少要實作四件事。第一，**錄音與轉錄顯示中的顯著告知**，不要讓使用者對「系統音訊是否被擷取」有誤解。第二，**來源標記**，例如麥克風、系統音訊、chat box 上下文、LLM 生成內容，彼此要能區分。第三，**最小傳送原則**，回覆建議通常不需要整場 raw audio；多數情況只要最近 1–3 分鐘 finalized transcript + rolling summary。第四，**可刪除性與可審計性**，至少要能刪 transcript、刪 notes、清空 summaries，並知道哪些內容被送到哪一個 provider。Apple 對 App Privacy 的整體方向，就是強調以 architecture 與 permission design 建立信任；這點在此類產品尤其關鍵。citeturn29search15turn29search2turn29search3turn30search2

以下是我認為最值得優先閱讀、且對實作最直接有用的參考來源；全部都是本報告實際依據：

**Apple 與 macOS 基礎**
1. Apple WWDC25《Bring advanced speech-to-text to your app with SpeechAnalyzer》：SpeechAnalyzer / SpeechTranscriber、volatile/final 結果、模型安裝、finalize 流程。citeturn38view0  
2. Apple WWDC22《Meet ScreenCaptureKit》：如何擷取螢幕與音訊、sample rate / channel count、低 CPU overhead。citeturn37view0  
3. Apple WWDC23《What’s new in voice processing》：voice processing、AEC、noise suppression、AGC、macOS voice activity detection。citeturn34view0  
4. Apple 安全文件：ATS、media capture authorization、Keychain。citeturn29search2turn29search6turn29search11turn30search2  

**串流 STT 官方文件**
5. Google Cloud Speech-to-Text：StreamingRecognize、Voice activity events/timeouts、StreamingRecognitionResult。citeturn9view5turn12view2turn26view0turn31search0  
6. Amazon Transcribe：streaming best practices、partial results stabilization、HTTP/2 / WebSocket。citeturn32view0turn15view0turn28search0  
7. Deepgram：endpointing、utterance_end、interim results、Finalize、recovery after connection errors。citeturn11view0turn11view1turn27search1turn27search11turn31search11  
8. Azure Speech：Recognizing/Recognized、audio input stream、compressed audio via GStreamer。citeturn9view1turn14view2turn14view3  

**開源與研究**
9. Whisper 論文《Robust Speech Recognition via Large-Scale Weak Supervision》。citeturn17view0  
10. Whisper-Streaming 論文《Turning Whisper into Real-Time Transcription System》：content-aware streaming、3.3s latency、WER trade-off。citeturn17view1  
11. Faster-Whisper repo：與原始 Whisper 的速度/記憶體改進。citeturn18search0  
12. whisper.cpp repo：Apple Silicon / Metal 最佳化。citeturn19search0  
13. Silero VAD repo 與參數說明。citeturn20search1turn20search10  
14. WebRTC VAD 介面與原始閾值實作。citeturn6search1turn6search11  
15. Semantic VAD 論文：把 punctuation / semantics 納入 endpointing，報告可降低平均 latency。citeturn24view0  
16. 2026 年 VAD 比較研究：Silero、WebRTC、window size、hysteresis。citeturn22view1  

綜合以上，我最推薦的第一版產品路線是：**macOS 分流擷取 + local-first 或 adapter-based streaming STT + partial/final 雙態 transcript store + hybrid boundary trigger + 回覆建議與筆記分頻更新**。在這個框架下，你可以很容易再接上使用者自帶的 LLM API，例如 GitHub Copilot/Codex 或其他 provider，而且不必把整個音訊與 UI 架構重做一遍。這是目前從官方文件、學術研究與成熟開源實作綜合起來，最穩健、最可落地的答案。citeturn38view0turn37view0turn32view0turn26view0turn17view1turn20search10