# macOS 會議助理即時逐字稿系統深度研究報告

## 執行摘要

在你給定的假設下——**目標 macOS 版本未指定、可假設 M1/M2 可用、網路條件未指定**——最穩健的結論不是單押某一個方案，而是採用**本機優先、雲端增強、可離線降級的混合式架構**。理由很直接：Apple 原生路徑與 WhisperKit 都能把**隱私、離線可用性、網路韌性、長期成本**控制得很好；OpenAI Realtime 則在**串流事件模型、雲端開發體驗、與後續 AI 功能整合**上很強，但雲端依賴與公開基準透明度仍是重要變數。Apple 最新 `SpeechAnalyzer` / `SpeechTranscriber` 明確支援**volatile partial** 與 **final** 結果、可回傳 `audioTimeRange`、模型透過 `AssetInventory` 下載且**不占用 app 內記憶體空間**；WhisperKit 則提供 Apple Silicon 原生的 on-device 管線、麥克風串流、本地 OpenAI 相容伺服器、SSE 串流、字詞/片段時間戳，以及新近加入的 `SpeakerKit` 做本地 diarization。OpenAI `gpt-realtime-whisper` 官方則明確支援**delta 事件**與**completed final 事件**、可調整延遲/準確率權衡，但官方文件同時提醒：若你需要 confidence、timestamps 或 diarization，必須逐模型/逐端點驗證支援狀態並準備 fallback。citeturn39view0turn8view0turn9view0turn9view1turn36view2turn41view1turn17search4

如果你的第一優先是**產品可靠性與學生專案可做性**，我建議的主路徑是：**AVAudioEngine + Apple Voice Processing 做前處理 → 本機即時轉寫以 WhisperKit 或 Apple SpeechTranscriber 為主 → 將 finalized 段落再送入 LLM 做摘要與建議 → 視使用者同意與網路狀態，選擇性把 finalized 音訊段落送到 OpenAI 做高品質後處理或 diarization**。這樣的分工能把 live caption 的核心能力放在本機，避免所有字幕都被網路品質綁架；雲端只承擔「增強」角色，而不是「單點失效」角色。Apple 的 voice processing API 本身提供回音消除、噪音抑制與自動增益控制，這一層不論你後端接 Apple、本地 Whisper、WhisperKit、或 OpenAI，都值得先做。citeturn6search0turn6search2turn39view0turn36view2turn8view0

從**公開可引用數據**看，英語仍是最容易的情境，而**台灣口音國語與 zh+en code-switching**是你設計裡真正的風險區。WhisperKit 公開基準在 Apple M2 Pro 上，`whisper-large-v3-v20240930/turbo` 的平均 WER 約 **6.14**，`distil-large-v3` 約 **6.77**，`large-v3` 約 **7.63**；但這是英語基準，不等於台灣會議語音。對 zh-TW，ROCLING 2023 的 Whisper 微調研究在 Common Voice zh-TW 上報告：未微調 Hugging Face Whisper `medium` / `large-v2` CER 分別約 **13.4 / 12.7**，微調後都可降到 **8.9**；這更接近「台灣華語讀句」能力，而不是遠場會議音訊。對 Mandarin-English code-switching，針對 Whisper-large-v3 的公開研究在三個資料集上的零樣本平均 MER 約 **33.52**，加 prompt 可到 **21.67**，再加入 speech in-context learning 才能接近 **12.27**；這說明 **zh+en 混講是最不該用直覺估計的區域**。OpenAI 官方則明講 `gpt-4o-transcribe` 與 `gpt-4o-mini-transcribe` 在 FLEURS 與多個 established benchmarks 上 **WER 低於原始 Whisper**，而且在口音、噪音與不同語速下較穩健，但官方公開文字沒有給出可直接引用的 zh-TW 與 zh+en 分語言數字，因此在你的場景裡仍必須自己做實測而不能憑品牌決定。citeturn21search0turn30view0turn27view0turn32view0turn32view1

在**成本**上，OpenAI `gpt-realtime-whisper` 目前公開價格是 **US$0.017/分鐘**，即約 **US$1.02/小時**；`gpt-4o-transcribe` 約 **US$0.006/分鐘**，即 **US$0.36/小時**；`gpt-4o-mini-transcribe` 約 **US$0.003/分鐘**，即 **US$0.18/小時**。因此，若你把 live path 放在 Realtime，而會後再跑一次高品質 file transcription，雲端成本大約是 **US$1.38/小時** 等級。對學生專案，**20 小時/月**大約是 **US$20.4 / 月** 的 live-only 成本，或 **US$27.6 / 月** 的 live+final cleanup 成本；對 **1000 小時/月** 等級產品則約是 **US$1,020 / 月** 或 **US$1,380 / 月**。相較之下，本機轉寫在你已擁有 M1/M2 Mac 的前提下，**邊際雲成本近乎為零**；真正的代價是整合複雜度、模型下載體驗、與裝置電池/熱設計。citeturn8view1turn35search0turn34search5turn34search7

最終建議可以濃縮成一句話：**不要把「即時字幕」與「最終高品質稿」當成同一條管線。** Live path 應追求低延遲、穩定 partial、使用者可立即閱讀； Final path 才追求高品質段落切分、說話者標籤、較準確的標點與後續摘要。這樣你才能同時滿足會議助理最實際的三件事：看得到、跟得上、斷線也不死。citeturn39view0turn9view1turn42view0

## 比較基準與核心選項

下表先把你要求的幾個主要選項，用**實作層面**而不是行銷標籤來比較。

| 方案 | 即時 partial / final | 時間戳 / diarization | macOS 整合性 | 本機資源與硬體 | 成本與隱私 | 核心判斷 |
|---|---|---|---|---|---|---|
| Apple 原生 `SpeechAnalyzer` / `SpeechTranscriber` | 有。WWDC 範例明確展示 **volatile** 與 **final** 結果；final 需在停止時呼叫 finalize，避免重複與遺漏。 | 有 `audioTimeRange`；公開資料中**未見官方宣稱內建 speaker diarization**。 | 非常高。`SpeechAnalyzer.bestAvailableAudioFormat`、`AssetInventory`、`AsyncStream` 都是直接為平台整合設計。 | 模型下載到系統儲存；Apple 明說模型不增加 app 下載體積，也不在 app 記憶體空間內運作。 | 無每小時 API 費；on-device 隱私最佳。 | **若可鎖定較新 OS / 硬體，這是最平台原生、隱私最佳的選項之一。** 但 Apple 沒公開 WER/CER 表，透明度較弱。 citeturn39view0 |
| Apple 傳統 `SFSpeechRecognizer` | 有。`shouldReportPartialResults` 可回報 partial。 | 可回傳轉寫結果；`addsPunctuation` 可要求加標點。公開資料未見內建 diarization。 | 高，但較舊；需處理授權與 on-device 能力檢查。 | 是否完全 on-device 取決於 `supportsOnDeviceRecognition` 與 `requiresOnDeviceRecognition`。 | 可能依語言/裝置而異；官方舊文件仍提醒 Speech framework 常假設需要網路。 | **適合作為舊版/回退路徑**，不建議作為未來主架構核心。 citeturn40search0turn40search1turn40search2turn40search8turn40search20 |
| OpenAI Realtime `gpt-realtime-whisper` | 有。`conversation.item.input_audio_transcription.delta` 與 `completed` 事件是官方主流程。 | 官方 realtime 文件明說：若需要 confidence、timestamps、diarization，必須逐模型/端點確認並準備 fallback。 | 中等。macOS 端自己負責音訊擷取、重採樣、WebSocket/WebRTC。 | 本機只需音訊 buffer；模型算力在雲端。輸入建議 24kHz mono PCM。 | **US$1.02/小時**；資料預設不作訓練，但 abuse logs 預設可保留最長 30 天，企業可申請 ZDR / modified abuse monitoring。 | **很適合做雲端 live captions / AI agent pipeline**，但不應在網路未知時作為唯一字幕引擎。 citeturn8view0turn9view0turn9view1turn8view1turn13view0turn13view1 |
| OpenAI file transcription `gpt-4o-transcribe` / `gpt-4o-transcribe-diarize` | 非 realtime-first；偏 request-response / file workflow。 | `gpt-4o-transcribe-diarize` 支援 `diarized_json` 與 speaker segments；`whisper-1` 支援 `verbose_json` 與 word/segment timestamps。 | 中等。較適合會後清理，而非主 live path。 | 雲端。 | `gpt-4o-transcribe` 約 **US$0.36/小時**；隱私控制同 API 資料政策。 | **很適合當「最終稿 / 會後清理 / speaker labels」路徑**，不適合作唯一 live path。 citeturn35search1turn34search2turn34search3turn34search4turn35search0 |
| `openai/whisper` 參考實作 | 不是天生串流；官方說 `transcribe()` 以 **30 秒 sliding window** 運作。 | Whisper 天生有時間戳 token；但官方 Python 參考實作不是以即時 UI 為主。 | 低到中。Python/FFmpeg 整合，在原生 macOS app 中成本較高。 | 模型大小與記憶體開銷高；官方 README 列 `turbo` 約 809M 參數、約 6GB VRAM，`large` 約 10GB VRAM。 | 本機免費，隱私好。 | **更像基準與研究母體**，不建議直接當原生即時產品引擎。 citeturn36view1turn38view2 |
| WhisperKit | 有。支援檔案轉寫、麥克風串流、本地伺服器 SSE streaming；最新生態還有 `SpeakerKit` 本地 diarization。 | 本地 server 支援 word / segment timestamps；`SpeakerKit` 可補說話者標記。 | 非常高。Swift 套件、Core ML、Apple Silicon 定向最佳化。 | 供應商論文指出 large-v3-turbo 可壓縮到 **0.6GB**，並以 Apple Neural Engine 為主要優化目標。 | 本機隱私好、邊際成本低。 | **若你想做真正的 native macOS app，WhisperKit 是目前最務實的本機主力候選。** citeturn36view2turn41view0turn41view1turn41view4turn17search4turn42view0 |
| faster-whisper | 原生庫本身偏 batch / segment 轉寫；即時多依賴外部 streaming 封裝。 | 支援 `word_timestamps=True` 與 VAD；diarization 需配 WhisperX/其他方案。 | 中等偏低。Python 生態很成熟，但對原生 Swift app 不如 WhisperKit。 | 在 macOS 上 **CTranslate2 Python wheels 不提供 GPU execution**；也就是 Mac 上通常是 CPU 路徑。 | 本機免費，隱私好。 | **很適合伺服器或 Python 工具鏈；對原生 macOS app，它是好後備，不是最佳第一選擇。** citeturn36view0turn37view0turn37view1turn37view4turn36view3turn36view4 |
| 混合式 | 有，可把 local partial 與 cloud final 分離。 | 可用 local timestamps + cloud diarized final，或反過來。 | 最複雜，但也最穩。 | 可依電量/熱/網路切換模型。 | 隱私、成本、準確度三者可調。 | **這是我對會議助理場景的推薦架構。** citeturn39view0turn9view1turn35search1turn17search4 |

有三個關鍵判斷值得單獨強調。第一，**Apple 原生路徑與 WhisperKit 是 macOS app 的一級公民**；它們讓你的 capture、格式轉換、即時 UI、离线 fallback 比較「順手」。第二，**OpenAI Realtime 的價值更多在雲端事件模型與後續 agent 能力，而不只是 ASR 本身**；如果你同時需要「What should I say?」「Follow-up questions」「會議摘要」，雲端管線通常比較容易整合。第三，**faster-whisper 在 macOS 上的最大結構性限制是 CPU-only**；這不是它模型不好，而是它在 Apple 平台的執行路徑天生沒有 WhisperKit 那麼對味。citeturn36view3turn36view4turn36view2turn8view0

## 技術能力與整合分析

從**音訊擷取與前處理**看，無論你最終把音訊送到 Apple、OpenAI、WhisperKit 或 faster-whisper，最值回票價的事情都是先把 capture 層設計好。Apple 的 voice processing API 明確提供 **echo cancellation、noise suppression、automatic gain control**，而且可透過 `AVAudioEngine` 的 voice processing mode 或 `AUVoiceProcessingIO` 取得。對會議助理來說，這一層直接決定遠端喇叭回音、機械鍵盤、風扇噪音與近講/遠講的可用度；它不只是「音訊優化」，而是後端模型成本與錯字率的前置放大器。citeturn6search0turn6search2turn6search3

從**格式與 sample rate**看，Apple 最新 `SpeechTranscriber` 不要求你猜格式，而是由 `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` 告訴你最佳目標格式；WWDC 範例也明說實作上要把不同來源的音訊先轉成這個格式再餵進分析器。OpenAI Realtime 官方則明確建議，若用 `audio/pcm`，就送 **24 kHz mono PCM**。Whisper 官方參考實作則會把輸入重採樣到 **16 kHz**。WhisperKit 對檔案輸入支援 `wav/mp3/m4a/flac`，如果做麥克風串流則由你的 app 自己負責 PCM buffer 管線。這意味著：**capture 層必須內建 resampler / format adapter**，這不該留給各 backend 各自處理。citeturn39view0turn8view0turn29view0turn41view2

從**partial 與 final 合併邏輯**看，Apple 與 OpenAI 兩邊都已經把「UI 不可直接把所有 partial 當真」寫進官方範例/文件。Apple 的做法是同時維護 `volatileTranscript` 與 `finalizedTranscript`，一旦 final 來了就清掉 volatile，否則會產生重複。OpenAI 的做法是以 `item_id` 追蹤 turn，因為不同 speech turns 的 completion 事件排序不保證。你的資料模型因此不應該是「單一字串」，而應該是**segment-oriented、versioned、帶狀態機**：每段至少有 `segmentId / source / state(partial|final) / startTime / endTime / revision`。這樣才能正確做 partial 替換、回溯修正與跨 backend reconcile。citeturn39view0turn9view0turn9view1

從**時間戳與 speaker labels**看，三條路差異很大。Apple 最新 API 可以從 attributed string 的 run 讀到 `audioTimeRange`，很適合做逐段同步高亮，但公開資料裡沒有看到 Apple 內建 speaker diarization 的官方說明。OpenAI realtime-transcription 文件則沒有把 timestamps/diarization 當成保證能力，反而明說你必須驗證支援與準備 fallback。OpenAI file transcription 端則把功能切得很清楚：`whisper-1` 可走 `verbose_json` 和 `timestamp_granularities` 拿 word/segment timestamps；`gpt-4o-transcribe-diarize` 可回 `diarized_json` 與 speaker segments。WhisperKit 的本地 server 支援 word / segment timestamps，而 `SpeakerKit` 則提供本地 diarization。若你的產品真的要在 live 畫面上可靠地顯示「說話者 A/B」，**不要把整件事綁在單一 live ASR 模型身上**；分成 live captions 與 post-turn / post-meeting diarization 會穩得多。citeturn39view0turn9view1turn34search2turn34search3turn34search4turn35search3turn35search11turn41view4turn17search4

從**macOS 整合難度**看，Apple 原生與 WhisperKit 幾乎是兩個最合理的第一選擇。Apple 原生需要 microphone/speech 權限與 model asset 管理；Apple 的教學與搜尋結果都指向你要設定 `NSMicrophoneUsageDescription` 與 `NSSpeechRecognitionUsageDescription`。WhisperKit 則直接以 Swift Package 方式加入，對原生 macOS app 很友善，甚至還提供本地 OpenAI 相容 server 讓你沿用既有 SDK。相對地，faster-whisper 雖然成熟，但它更像是 Python / toolchain / backend-friendly 的方案；如果你的主體是 SwiftUI/AppKit app，維護 Python 執行環境、打包、沙盒、更新與 crash surface 都會比較複雜。citeturn5search0turn5search3turn36view2turn41view0turn36view3

以下放三段**代表性整合範例**。它們刻意寫成「接近可用的 pseudocode」，目的是幫你定義介面，而不是逐字貼上就能編譯。Apple 路徑的關鍵是 `AsyncStream`、`bestAvailableAudioFormat`、`volatile`/`final`；OpenAI 路徑的關鍵是 **24k PCM、delta/completed 事件**；WhisperKit 路徑的關鍵是 **本地模型初始化 + streaming / local server**。相關欄位與事件名稱都對應官方文件與 README。citeturn39view0turn8view0turn9view0turn36view2turn41view1

```swift
// Apple SpeechAnalyzer / SpeechTranscriber pseudo-Swift
import Speech
import AVFAudio

final class AppleLiveTranscriber {
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    func start() async throws {
        let t = SpeechTranscriber(
            locale: Locale(identifier: "zh-TW"),
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        let a = SpeechAnalyzer(modules: [t])
        let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])

        // ensure model with AssetInventory here...

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.transcriber = t
        self.analyzer = a
        self.inputContinuation = continuation

        try await a.start(inputSequence: stream)

        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { buffer, _ in
            if let converted = convert(buffer, from: sourceFormat, to: targetFormat) {
                continuation.yield(.audioBuffer(converted))
            }
        }

        try engine.start()

        Task {
            for try await result in t.results {
                if result.isFinal {
                    commitFinal(result.text, timeRangesFrom: result.text)
                } else {
                    updateVolatile(result.text)
                }
            }
        }
    }

    func stop() async throws {
        engine.stop()
        inputContinuation?.finish()
        try await analyzer?.finalizeAndFinish(through: nil)
    }
}
```

```swift
// OpenAI Realtime pseudo-Swift
// PCM16 mono 24kHz -> base64 -> input_audio_buffer.append

func openRealtimeSession() async throws {
    let ws = try await RealtimeWebSocket.connect(url: realtimeURL, apiKey: apiKey)

    try await ws.sendJSON([
        "type": "session.update",
        "session": [
            "type": "transcription",
            "audio": [
                "input": [
                    "format": ["type": "audio/pcm", "rate": 24000],
                    "transcription": [
                        "model": "gpt-realtime-whisper",
                        "language": "zh"
                    ]
                ]
            ]
        ]
    ])

    Task {
        for try await event in ws.events {
            switch event.type {
            case "conversation.item.input_audio_transcription.delta":
                renderPartial(itemID: event.item_id, delta: event.delta)
            case "conversation.item.input_audio_transcription.completed":
                commitFinal(itemID: event.item_id, text: event.transcript)
            default:
                break
            }
        }
    }
}

func sendPcmChunk(_ pcm16Mono24k: Data, ws: RealtimeWebSocket) async throws {
    try await ws.sendJSON([
        "type": "input_audio_buffer.append",
        "audio": pcm16Mono24k.base64EncodedString()
    ])
}
```

```swift
// WhisperKit pseudo-Swift
import WhisperKit

final class LocalWhisperKitBackend {
    private var pipe: WhisperKit?

    func prepare() async throws {
        // multilingual accuracy preferred
        pipe = try await WhisperKit(
            WhisperKitConfig(model: "large-v3-v20240930_626MB")
        )
    }

    func transcribeFile(_ path: String) async throws -> String {
        guard let pipe else { throw BackendError.notReady }
        return try await pipe.transcribe(audioPath: path)?.text ?? ""
    }

    // 若要做 live，可直接用麥克風串流或啟本地 OpenAI-compatible server
}
```

## 準確率、延遲與成本

先說最重要的研究結論：**你不能把不同資料集、不同指標、不同任務型態的數字直接橫向比較。** 這份報告能給你的，是「公開可引用的上限與風險輪廓」，而不是保證某模型在你的會議資料上一定會是某個數字。對英語，WhisperKit 公開 Apple Silicon 基準顯示強勢表現；對 zh-TW，最接近的公開數字是 Common Voice zh-TW 這類讀句資料；對 zh+en code-switching，公開數字顯示難度遠高於單語。OpenAI 官方也只公開「比原始 Whisper 更低 WER」的方向性結果，而沒有放出可直接引用的 zh-TW / zh+en 細部數字。citeturn21search0turn30view0turn27view0turn32view0

下面這張表列的是**最有用、也最能避免誤解的公開數字**。

| 面向 | 可引用數字 | 解讀方式 |
|---|---|---|
| 英語，本機 WhisperKit on Apple Silicon | Apple M2 Pro 上，`whisper-large-v3-v20240930/turbo` 平均 WER 約 **6.14**；`distil-large-v3` 約 **6.77**；`large-v3` 約 **7.63**。同批數據中，`base` / `small` 更快但準確度較差。 | 代表「英語 benchmark 上，本機 large-v3-turbo 類路線是可打的」，也說明 **turbo 常是即時產品的甜蜜點**。citeturn21search0 |
| zh-TW 讀句，Whisper 微調 | Common Voice zh-TW 上，Hugging Face Whisper `medium` / `large-v2` 未微調 CER 約 **13.4 / 12.7**；微調後都降到 **8.9**。 | 這是 **台灣華語讀句 proxy**，不是遠場會議。它說明台灣華語值得做 locale / normalization / domain adaptation。citeturn30view0 |
| 台語 / 混合正字法風險 | Common Voice `nan-tw` 微調後 CER 約 **50.9–52.8**；台語連續劇最佳 CER 約 **50.7**。 | 如果你的產品未來想碰 Taigi 或台語混入，風險明顯比 zh-TW 國語高很多。citeturn30view0turn29view0 |
| Mandarin-English code-switching | Whisper-large-v3 在三個公開 code-switching 資料集上的零樣本平均 MER 約 **33.52**；加入 prompt 約 **21.67**；再加 SICL 約 **12.27**。 | **zh+en 是 hardest mode。** 單靠現成 zero-shot 模型，會議實務中通常不應樂觀估計。citeturn27view0 |
| OpenAI 新一代 transcription | OpenAI 官方明示 `gpt-4o-transcribe` / `gpt-4o-mini-transcribe` 在 FLEURS 與多個既有 benchmark 上 WER 低於原始 Whisper，且在 accents / noise / speed 場景較穩。 | 方向正面，但**公開文字沒有你需要的 zh-TW/zh+en 具體數字**。對你的 app，仍須自建 eval。citeturn32view0turn32view1 |

對**延遲**，有些數字能直接用，有些得誠實標成工程推估。WhisperKit/Apple Silicon 這邊，M2 Pro 上 `large-v3-v20240930/turbo` 的 speed 約 **12.81–12.85x realtime**，換句話說，**1 秒音訊的純計算時間約 78ms 左右**；`distil-large-v3/turbo` 約 **15.88x**，更快；`large-v3` 只有約 **3.01x**，即 1 秒音訊要約 **332ms** 的純計算時間。這說明在 M2 級硬體上，**即時 UX 的主要瓶頸通常不再是模型算力，而是 chunk 大小、VAD、partial 穩定度與 UI revision 策略**。相反地，若你選到完整 `large-v3` 而非 turbo / distilled 路線，live UX 就會明顯吃緊。citeturn21search0

對 OpenAI Realtime，官方能給你的保證是：`gpt-realtime-whisper` 是**最低延遲的串流轉寫路徑**，而且你可以用 `minimal / low / medium / high / xhigh` 調整延遲/準確率；但官方同時明說**不要假設固定毫秒數**，必須以代表性資料實測。這代表在產品規格上，你應該把雲端 live latency 寫成**SLO 目標**而不是外部承諾，例如：`first partial target <= 500ms in good network`、`turn final target <= 1.5s after pause`，並把它們當自己的驗收標準。WhisperKit 論文也提供一個有價值的外部參考：其作者在 M3 Max 上報告平均 hypothesis latency 約 **0.45 秒**，confirmed text latency約 **1.7 秒**，但那份比較使用的是 `gpt-4o-transcribe` 等 cloud APIs、而非你問題裡的 `gpt-realtime-whisper`，因此只能當「雲端 confirmed text 常落在秒級」的旁證，而不是 Realtime 官方數字。citeturn8view0turn9view1turn42view0

對 **faster-whisper**，要特別小心平台差異。它官方 README 的 benchmark 很漂亮，但多數是 NVIDIA GPU 或 Intel CPU；`CTranslate2` 官方安裝頁清楚寫到 Python wheels 的 **GPU support 只在 Linux / Windows**，macOS wheels 不在其列。這表示你在 Mac 上跑 faster-whisper，通常是走 CPU / Apple Accelerate 路。因此，faster-whisper 在 macOS 上仍然能用，尤其適合 batch、命令列工具、或本地 server，但若你要做一個長時間常駐、重視電池與 UI 反應的 native 會議助理，**WhisperKit 通常比 faster-whisper 更自然**。citeturn36view0turn36view3turn36view4

對**成本**，你可以很快地把架構決策量化。`gpt-realtime-whisper` 約 **US$1.02/小時**；`gpt-4o-transcribe` 約 **US$0.36/小時**；`gpt-4o-mini-transcribe` 約 **US$0.18/小時**。因此：  
若是 **學生專案**，假設每月 20 小時會議轉寫，live-only 的 OpenAI 成本約 **US$20.4/月**；若再加一條會後高品質 final pass，約 **US$27.6/月**。  
若是 **production**，假設每月 1000 小時，live-only 約 **US$1,020/月**；live + final pass 約 **US$1,380/月**。  
如果你的字幕 live path 改成本機，雲端就只剩 summary、action items、follow-up suggestions 與 optional cleanup，成本通常會掉到比較舒服的區間。citeturn8view1turn35search0

## 隱私、合規與穩健性

在**隱私與法遵**上，這類產品最大的風險不是模型，而是**你是否把「錄音」與「個資處理」視為第一等公民功能**。台灣的 PDPA / PDPC 公開資料明確指出，PDPA 的目的在於規範個人資料的蒐集、處理與利用，以避免人格權受侵害；音訊中若能識別自然人，通常就會落入個資處理範圍。歐盟 GDPR 則對個資處理的合法性、目的限制、資料最小化、資訊告知、保留期限與資料主體權利提出更高要求，且對可唯一識別個人的 biometric data 有更敏感的規範。美國則不是單一法，而是聯邦與各州錄音同意規則並存；可靠來源整理普遍指出，多數州是 one-party consent，但也有不少州要求 all-party / two-party consent，且是否屬於有合理隱私期待的情境會影響判斷。對跨境視訊會議產品，**最安全的產品策略永遠是顯示錄音/轉寫狀態並取得明示同意，而不是賭司法管轄細節**。citeturn43search3turn43search15turn43search7turn43search10turn43search5turn43search17

OpenAI API 的資料政策目前也相當關鍵。官方明示，自 2023-03-01 起，送進 OpenAI API 的資料**預設不會用來訓練模型**，除非你主動 opt in；但同時，平台預設的 abuse monitoring logs 可能保留**最多 30 天**。合規要求更高的客戶可申請 **Zero Data Retention** 或 **Modified Abuse Monitoring**。官方還說明，資料在傳輸中使用 TLS 1.2+、靜態 AES-256，加上可簽訂 DPA 以支援 GDPR 與其他隱私法遵。這代表：如果你的 app 可能進入學校、企業、醫療、法律、或台歐混合資料流場景，**不要只問「OpenAI 會不會拿去訓練」；要問的是 retention、區域處理、DPA、與使用者是否真的同意把會議內容送雲端**。citeturn13view0turn13view1turn14search0

從**韌性設計**看，最好的策略是把 live system 拆成三層：**capture layer、local transcript layer、cloud enhancement layer**。Capture layer 永遠本機持有 ring buffer；local transcript layer 永遠可獨立工作；cloud enhancement layer 只讀取「已穩定段落」或「可重送片段」。當網路抖動時，不應讓畫面上的字幕整段消失；相反地，應保持本機結果繼續跑，並把雲端狀態降級成「增強暫停」。OpenAI 官方也明確提醒：UI 必須決定如何修訂 partial text，以及如何用 `item_id` 對齊 final transcripts；Apple 官方範例也明說若不清掉 volatile 會重複。你的衝突解決可以採用這套簡單規則：**local partial is immediate truth，local final is display truth，cloud final is archival truth**；只有在 segment 關閉後，才允許 cloud 最終稿替換本地展示稿。citeturn9view1turn39view0

對**UI/UX**，即時字幕不該只是把字往上堆。Apple 在官方展示裡用較低 opacity 呈現 volatile，再由 finalized 取代，這就是很好的預設。我的建議是：  
畫面上只顯示**當前穩定 prefix + 一段不穩定尾巴**；  
時間戳預設只釘在 finalized 段落，不要對每個 partial 刷新時戳；  
speaker label 若來自 post-turn diarization，就先顯示「未標註」或暫時群組，不要假裝即時結果一定正確；  
「What should I say?」與「Follow-up questions」應該綁定 finalized turns，而不是逐 token 重算。  
一個務實的 latency budget 是：**字幕 first partial 目標 300–500ms；turn-final 目標 0.8–1.5s；AI 建議卡目標 1.5–3s**。其中 AI 建議最好只吃 finalized 或 high-stability partial，否則使用者會看到建議內容跟著字幕來回改，認知成本非常高。這些 budget 是工程建議，不是供應商 SLA。官方可支撐的部分是：Apple/ OpenAI 都已經把 partial-revision 問題明示為產品方必須自行設計處理。citeturn39view0turn9view1

## 推薦架構、優先實作步驟與測試計畫

在你的使用情境裡，我的**推薦方案**是：

**核心設計**：  
**本機 live captions** 以 `WhisperKit` 或 Apple `SpeechTranscriber` 擔任主後端；  
**Apple voice processing** 做 capture 前處理；  
**OpenAI** 不拿來當唯一 live ASR，而拿來做兩件事：  
其一，網路良好且使用者同意時，做雲端平行增強；  
其二，會後或 turn-level 用 `gpt-4o-transcribe` / `gpt-4o-transcribe-diarize` 做高品質清理、說話者標記、與後續摘要。  
若你必須支援較舊 OS 或 Apple 新 API 不可用，再退到 `SFSpeechRecognizer` 或 purely local WhisperKit。這樣的排序同時尊重了 **macOS 整合性、zh-TW/zh+en 風險、網路不確定性、與長期成本**。citeturn39view0turn36view2turn8view0turn35search1

```mermaid
flowchart LR
    Mic[麥克風輸入] --> VP[AVAudioEngine + Voice Processing]
    VP --> BUF[本機 Ring Buffer / Segmenter / Resampler]
    BUF --> L1[Apple SpeechTranscriber 或 WhisperKit]
    BUF --> C1[OpenAI Realtime 可選平行路徑]
    L1 --> P[Partial Transcript Store]
    C1 --> P
    P --> UI[Live Captions UI]

    UI --> A1[建議按鈕<br/>What should I say?]
    UI --> A2[建議按鈕<br/>Follow-up questions]

    P --> F[Final Segment Store]
    F --> D1[本機 SpeakerKit 可選]
    F --> D2[OpenAI gpt-4o-transcribe / diarize 可選]
    D1 --> R[最終逐字稿 / 摘要 / 行動項]
    D2 --> R

    NET[網路監測] --> C1
    NET --> Route[路由決策器]
    Route --> L1
    Route --> C1
```

對**執行路由**，建議你一開始就把 backend 抽象成協定，而不是先綁死某個 SDK。決策邏輯可以很簡單：  
若 `privacyMode == strict` 或 `network == poor`，強制本機；  
若 `languageHint in {zh-TW, en, mixed}` 且本機模型已就緒，先跑本機；  
若 `network == good && userConsentedCloud == true`，把 finalized 段落鏡像到雲端做 clean-up；  
若 `deviceThermalState` 高或電池低，從 `large-v3-turbo` 降到較小模型；  
若 `codeSwitchProbability` 高，增加 turn-final 的等待窗口，避免過早 commit。  
這套邏輯的價值不在「花俏」，而在於讓你的產品不會在錯誤的時間做錯誤的事。citeturn8view0turn9view1turn21search0turn27view0

下面是一段簡化後的**runtime orchestration pseudo-code**：

```swift
func chooseBackend(ctx: Context) -> RoutingDecision {
    if ctx.privacyMode == .strict || ctx.network.quality == .poor {
        return .localOnly(primary: .whisperKitOrApple)
    }

    if ctx.osSupportsAppleSpeech && ctx.localeSupportedByApple {
        if ctx.needsLowestFrictionNativeIntegration {
            return .localOnly(primary: .appleSpeech)
        }
    }

    if ctx.userConsentedCloud && ctx.network.rttMs < 150 {
        return .hybrid(
            live: .localWhisperKit,
            cloudEnhancement: .openAIRealtimeOptional,
            finalCleanup: .openAITranscribeDiarize
        )
    }

    return .localOnly(primary: .whisperKit)
}
```

**優先實作步驟**我建議按這個順序走。  
先做 **音訊層**：`AVAudioEngine` capture、voice processing、重採樣、ring buffer、segment id。  
再做 **單一本機 backend**：我建議先上 WhisperKit，因為你最容易拿到可測的 live path 與本地 server；若你鎖新 OS，可同步做 Apple `SpeechTranscriber` adapter。  
第三步才做 **transcript state machine**：partial/final、stable prefix、revision。  
第四步做 **UI**：volatile / final 差異化、時間戳、段落滾動。  
第五步再做 **OpenAI enhancement**：先接會後 finalization，再看 live parallel 是否必要。  
最後才接 **AI suggestions** 與 **摘要**。這個順序的關鍵，是不要把「LLM 魔法」放在「字幕可用」之前。citeturn39view0turn36view2turn8view0

**測試計畫**至少要分成 accuracy、latency、robustness 三組。  
Accuracy：英語用 LibriSpeech / Earnings22；台灣華語用 Common Voice zh-TW 外加你自行錄製的台灣口音會議音；code-switching 用 SEAME、NTUML2021、ASCEND、CSZS-correct；如果做多輪對話摘要，再加你自己的會議實錄集。  
Latency：量 `capture -> first partial`、`capture -> stable partial`、`pause -> final`、`AI suggestion ready`。  
Robustness：量離線切換成功率、WebSocket 重連成功率、partial correction 次數、空白/截斷 transcript、長會議 memory growth。OpenAI 官方 production checklist 還特別提醒要把 numbers、dates、currency、product names、domain terms 放進 eval set，並分開追蹤 empty / truncated / delayed transcripts，而不是只看 WER。citeturn9view1turn42view0turn27view0turn30view0

若是**學生專案規模**，我會把 sample size 設成：  
**英文 2 小時、zh-TW 2 小時、zh+en code-switching 2 小時、噪音與遠講 2 小時**，合計至少 **8 小時** 的帶標註資料；  
其中至少要包含：單人近講、雙人輪流、三到五人會議、筆電喇叭外放回音、咖啡店噪音、弱網路模擬、30 分鐘以上長會議。  
若是**production pre-launch**，我會把代表性錄音擴到 **20–30 小時以上**，而且要做 1–2 小時的長 session soak test，看記憶體、發熱、partial correction 漂移與 reconnect 行為。這些是會議助理真正會踩到的坑，比漂亮的單句 benchmark 更重要。citeturn9view1turn42view0

最後，這份研究也有三個**你應明確知道的限制**。  
第一，Apple 目前公開資料對 SpeechTranscriber 的**公開 WER/CER 透明度不足**；它看起來產品化程度高，但你不能只靠品牌名判斷準確率。  
第二，OpenAI 對語音模型公開的是**方向性優勢**與事件介面，而非你最需要的 **zh-TW / zh+en 細部 benchmark**。  
第三，我沒有在這份報告中給出一個可嚴格辯護的**本機每小時能耗數字**，因為我收集到的第一手或官方文件更集中在模型延遲、大小與平台能力，而不是可直接引用的 Wh / 小時結果。若你之後要做產品化決策，能耗應由你自己的 `powermetrics` / Instruments / battery drain A/B test 測出。citeturn39view0turn32view0turn42view0

綜合以上，我對你的 macOS 會議助理的明確建議是：**以 WhisperKit 或 Apple SpeechTranscriber 做本機 live transcript 主引擎；以 Apple voice processing 改善輸入；以 OpenAI 作為可選的雲端增強與會後清理；用 segment-versioned transcript store 解決 partial/final 與衝突合併；把評估資源集中在 zh-TW 與 zh+en code-switching，而不是只看英文。** 這是目前在工程可行性、產品體驗、成本、與隱私之間，最平衡也最不脆弱的做法。citeturn36view2turn39view0turn8view0turn27view0turn30view0turn6search0