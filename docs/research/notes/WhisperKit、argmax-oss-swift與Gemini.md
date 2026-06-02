# 即時語音辨識與即時對話模型技術研究報告：以 macOS 會議輔助工具為應用場景

## 一、研究背景

本專題預計開發一個 macOS 會議輔助工具，核心功能包含即時逐字稿、即時回應建議、會議摘要、後續行動整理，以及可讓使用者詢問 AI 的即時對話框。這類系統的技術核心可以分成三層：第一層是音訊擷取，負責從麥克風或會議軟體取得聲音；第二層是語音辨識，也就是將語音轉換成文字；第三層是語意理解與生成，負責根據逐字稿產生回答建議、追問問題、會議筆記與 action items。

目前相關技術大致可分為兩種路線。第一種是傳統或專用的 ASR，也就是 Automatic Speech Recognition，例如 WhisperKit、Deepgram、AssemblyAI、OpenAI realtime transcription 等。這類技術的主要目標是「準確、穩定、可追蹤地把語音轉成文字」。第二種是新一代即時對話模型，例如 Google Gemini Live API 或 OpenAI Realtime API。這類模型不只是語音辨識，而是能直接處理語音、理解語境並即時回應，適合做語音代理人或對話式 AI。

對於本專題來說，關鍵問題不是單純選擇哪一個模型，而是要判斷每個技術適合放在系統中的哪一層。逐字稿、會議記錄、即時應答、語音對話代理雖然都與語音有關，但技術需求不同，因此應避免把所有需求都交給單一模型處理。

## 二、WhisperKit 與 argmax-oss-swift

WhisperKit 是 Argmax 開發的 Apple 裝置本地語音辨識框架，目標是在 iPhone、iPad、Mac 等 Apple Silicon 裝置上高效率執行 Whisper 類模型。Whisper 原本是 OpenAI 推出的多語言語音辨識模型，具備良好的跨語言能力，但原始 Whisper 並不是為即時串流場景設計。因此，若要把 Whisper 用於即時會議字幕，需要額外處理音訊切片、增量推論、暫時結果、最終確認文字與延遲控制等問題。

Argmax 後來將 WhisperKit 擴展為 argmax-oss-swift。這個 open-source Swift SDK 目前包含 WhisperKit、SpeakerKit、TTSKit 等模組。[1] 其中 WhisperKit 負責 speech-to-text，SpeakerKit 負責 speaker diarization，也就是說話者分離，TTSKit 則負責文字轉語音。對 macOS App 來說，這套 SDK 的優勢是 Swift 原生、與 Apple 平台整合度高，且可以在本機端執行，不必把使用者音訊送到雲端。

WhisperKit 的核心原理仍然是語音辨識模型。一般流程為：先將音訊轉換成固定取樣率的 PCM waveform，再轉成 log-Mel spectrogram 之類的聲學特徵，接著送入 Transformer encoder-decoder 模型。Encoder 將音訊特徵轉成語意表示，decoder 則像語言模型一樣逐步生成文字 token。由於 Whisper 類模型本質上傾向處理一段音訊後再輸出結果，WhisperKit 需要使用 streaming inference 策略，將連續音訊切成小段，持續產生 hypothesis text，也就是暫時辨識結果，再透過類似 local agreement 的方法確認哪些文字可以穩定輸出為 confirmed text。[2]

這種 partial / confirmed transcript 的設計非常適合即時字幕。系統可以先在 UI 顯示暫時文字，等待模型確認後再變成正式逐字稿。如此一來，使用者能感受到低延遲，同時系統仍保留修正錯字、補齊句子的能力。

WhisperKit 的最大優勢是本地端運算。對會議輔助工具而言，這代表三個好處。第一是隱私性高，因為音訊不必離開使用者裝置。第二是成本低，因為不需要依照音訊分鐘數支付雲端 ASR 費用。第三是離線可用，網路不穩時仍可提供逐字稿。不過，它也有幾個限制。首先，本地模型需要消耗 CPU、GPU 或 Apple Neural Engine 資源，對較舊的 Mac 或低階裝置可能造成負擔。其次，中文、台灣口音、雜訊環境、多人同時說話、專有名詞等場景需要實測。第三，open-source 版雖然提供 SpeakerKit，但若要穩定做到「即時逐字稿加說話者分離」，仍可能需要額外工程整合，或考慮商業版功能。

整體而言，WhisperKit / argmax-oss-swift 非常適合作為本專題的「本地即時逐字稿核心」。它不應被視為完整會議助理，而應視為底層語音轉文字引擎。它負責把聲音轉成文字，再由後面的 LLM 或即時對話模型進行理解、摘要與回應生成。

## 三、Google Gemini Live API 與 Gemini 3.1 Flash Live

Google Gemini Live API 是用於即時語音與影像互動的 API。與傳統 ASR 不同，Live API 的重點不是單純產生逐字稿，而是讓模型能持續接收音訊、影像或文字，並即時產生自然的對話回應。[3][4] 其中 Gemini 3.1 Flash Live Preview 被官方定位為低延遲 audio-to-audio 模型，適合 real-time dialogue 與 voice-first AI 場景。[3]

它的技術路線接近「原生語音對話模型」。傳統語音代理常見流程是 STT → LLM → TTS，也就是先把語音轉成文字，再交給語言模型推理，最後再用文字轉語音輸出。這種 cascaded pipeline 容易理解、容易除錯，但每一層都會增加延遲。Gemini Live 這類模型則嘗試直接在同一個即時 session 中處理音訊輸入、語境理解、回應生成與音訊輸出。這使它更適合做自然語音互動，例如客服機器人、語音助理、即時翻譯、口語教練或會議中的 AI 代理人。

Gemini Live API 使用 stateful WebSocket session。也就是說，應用程式不是每次送一個完整 request，而是建立一條持續連線，將小段音訊持續送入模型，模型也持續回傳音訊或文字相關事件。[4] 在實作上，這種架構比一般 HTTP API 更複雜，因為開發者需要處理音訊取樣率、chunk 大小、連線狀態、session 中斷、上下文壓縮、權限與金鑰安全等問題。官方文件也提到，為了降低延遲，音訊 chunk 不應該緩衝太久，建議以較小片段傳送；同時，由於音訊 token 會快速累積，長時間會議需要 context window compression 或 session management。[5]

對本專題而言，Gemini Live 的價值在於「即時對話輔助」而不是「完整逐字稿保存」。它可以用來做更自然的語音互動，例如使用者可以直接問：「剛剛對方問了什麼？」或「我現在該怎麼回答？」模型可以根據近期語音脈絡給出回應。但是，如果系統核心需求是產生完整、可追蹤、可搜尋、可匯出的會議逐字稿，仍然建議使用專用 ASR 作為主要轉錄引擎。原因是逐字稿系統需要穩定時間戳、文字確認狀態、錯誤修正、片段儲存與後處理；而原生語音對話模型的設計重點是互動體驗，不一定是嚴格的逐字稿品質控制。

因此，Gemini Live 適合放在本專題的進階功能層，例如語音版「我該說什麼？」、「幫我追問」、「幫我整理目前討論重點」。但在 MVP 階段，若要降低開發難度，可以先用 WhisperKit 產生文字逐字稿，再把最近 30 到 90 秒逐字稿送給一般文字 LLM 產生建議。等逐字稿與摘要功能穩定後，再加入 Gemini Live 作為進階語音互動模式。

## 四、OpenAI Realtime API 與其他雲端即時語音辨識服務

除了 Google Gemini Live，OpenAI 也提供 Realtime API 與 realtime transcription session。這類 API 可用於即時轉錄，也可以用於 speech-to-speech 對話代理。[6] OpenAI 的優勢是模型生態完整，能同時處理語音、文字、工具呼叫與對話狀態。若專題希望展示「AI 直接聽、直接回答」的效果，OpenAI Realtime API 是 Gemini Live 之外的重要選項。

不過，Realtime API 與 Gemini Live 一樣，工程複雜度高於一般文字 API。開發者需要處理 WebSocket 或 WebRTC 連線、音訊串流、turn detection、打斷處理、session state、費用控制與金鑰安全。對畢業專題而言，這類技術可以作為加分功能，但不建議在第一階段就把整個系統建立在 realtime speech-to-speech 上，否則容易花太多時間處理串流與連線細節，反而延誤主要產品功能。

Deepgram、AssemblyAI 等雲端 ASR 服務則屬於另一類選項。它們主要提供成熟的 streaming speech-to-text API，通常透過 WebSocket 持續接收音訊並回傳即時轉錄結果。[7] 這類服務的優點是產品化程度高、文件完整、延遲低，且常見功能如 endpointing、punctuation、speaker diarization、custom vocabulary 等已經封裝好。缺點是需要付費、依賴網路，且音訊會送到第三方伺服器，必須考慮隱私與資料保護。

若本專題目標是快速做出穩定 demo，Deepgram 或 AssemblyAI 這類雲端 ASR 其實很適合。它們可以大幅降低本地模型部署難度。但若專題強調 macOS App、本地運算、隱私與低成本，WhisperKit 會更符合方向。最好的策略是系統設計上保留 provider abstraction，也就是把 ASR 層抽象化，讓使用者或開發者可以切換 WhisperKit、本地模型或雲端 ASR。

## 五、macOS 音訊擷取技術

在 macOS 會議輔助工具中，語音模型只是其中一部分。真正困難的第一步是取得正確的音訊來源。若只需要使用者自己的聲音，可以用 AVAudioEngine 擷取麥克風音訊。若要聽到 Google Meet、Zoom、Discord、Line Call 或其他會議軟體中的對方聲音，就需要擷取系統音訊或特定 app 音訊。

Apple 的 ScreenCaptureKit 可以用於 macOS 螢幕與音訊擷取。它可以取得音訊與影像 sample buffer，適合用於螢幕錄製、直播、會議輔助等場景。[8] 對本專題來說，可能的架構是：使用 AVAudioEngine 取得麥克風聲音，使用 ScreenCaptureKit 或 Core Audio 相關機制取得系統音訊，接著將兩路音訊整理成模型可接受的格式，例如 16kHz mono PCM，再送入 WhisperKit 或雲端 ASR。

這裡需要注意一個產品設計問題：如果同時擷取使用者麥克風和系統音訊，逐字稿可能需要區分「我方」與「對方」。最簡單的方法是把兩路音訊分開送入 ASR，分別標記為 self 和 remote。較進階的方法則是使用 speaker diarization，把同一路混合音訊中的不同說話者分離出來。不過 speaker diarization 在即時場景中比單純語音辨識更困難，因為模型不只要辨識文字，還要判斷誰在說話，而且多人重疊說話時錯誤率會上升。

## 六、是否適合本專題

以本專題「macOS 即時會議輔助工具」的需求來看，各技術適用性如下。

WhisperKit / argmax-oss-swift 非常適合做本地即時逐字稿。它的優勢是隱私、成本與 Apple 平台整合。只要目標是「把會議內容即時轉成文字」，WhisperKit 是最符合 macOS App 方向的技術。但它不負責真正的語意推理，因此仍需要 LLM 來做回應建議、摘要與行動項目整理。

SpeakerKit 適合做說話者分離，但建議放在第二階段。MVP 可以先不做完整 speaker diarization，而是先區分本機麥克風與系統音訊兩路來源。等逐字稿穩定後，再加入 SpeakerKit 或雲端 diarization 功能。

Gemini Live API 適合做即時語音互動與進階 AI 助理。它不只是 ASR，而是能建立持續語音 session 的對話模型。若專題想展示「AI 直接聽會議，並即時用語音或文字給建議」，Gemini Live 很有展示效果。但它的 session 管理、音訊串流、成本與穩定性都比文字 LLM 複雜，因此不建議作為第一階段核心。

OpenAI Realtime API 與 Gemini Live 類似，也適合做語音代理與即時互動。不過若只是要做「我該說什麼？」按鈕，使用文字 LLM 搭配最近逐字稿通常更簡單、更穩定，也更容易控制輸出格式。

Deepgram、AssemblyAI 等雲端 ASR 適合做備用或比較組。如果本地 WhisperKit 在某些裝置效能不足，或中文辨識效果不夠穩定，可以讓系統切換到雲端 ASR。這樣可以兼顧展示穩定性與技術彈性。

## 七、建議系統架構

本專題最適合採用 hybrid local-first 架構。底層使用 macOS 音訊擷取取得麥克風與系統音訊，中層使用 WhisperKit 進行本地即時轉錄，上層使用 LLM 產生即時回應建議、追問問題、會議摘要與 action items。Gemini Live 或 OpenAI Realtime 則作為進階模式，用於展示更自然的語音對話功能。

建議的資料流程如下：

音訊擷取 → 音訊前處理 → WhisperKit 即時逐字稿 → Transcript Buffer → LLM 分析 → UI 顯示建議與筆記

Transcript Buffer 不應該每次都把完整會議逐字稿丟給模型，而應該分成三種上下文。第一是最近 30 到 90 秒的原文逐字稿，用於即時回應。第二是 rolling summary，用於保留前面幾分鐘或整場會議的重點。第三是結構化狀態，例如已決定事項、待辦事項、人物名稱、專案名稱與尚未回答的問題。若之後會議時間很長，才需要加入向量資料庫，用於搜尋過去片段。

這種架構的優點是延遲較低、成本可控、容易除錯，也符合畢專展示需求。WhisperKit 展示本地 AI 與即時語音辨識能力，LLM 展示語意理解與生成能力，Gemini Live 或 Realtime API 則可作為進階展示，說明系統未來可以擴充成完整 voice agent。

## 八、結論

即時會議輔助工具不應只被理解成一個語音辨識系統，也不應只被理解成一個聊天機器人。它其實是一個結合音訊工程、即時 ASR、上下文管理、LLM 推理與使用者介面的複合系統。

WhisperKit / argmax-oss-swift 適合作為本專題的本地 ASR 核心，因為它符合 macOS、隱私、本地運算與低成本需求。Google Gemini Live API 與 OpenAI Realtime API 適合作為進階的即時語音互動層，但不建議在第一階段取代專用逐字稿系統。Deepgram、AssemblyAI 等雲端 ASR 則適合作為備援方案或比較對象。

因此，本專題最推薦的開發策略是：第一階段先完成 macOS 音訊擷取、WhisperKit 即時逐字稿、文字 LLM 回應建議與會議摘要；第二階段加入系統音訊擷取、speaker diarization、action items 與 provider 切換；第三階段再整合 Gemini Live 或 OpenAI Realtime，展示真正的即時語音 AI 助理能力。這樣的路線技術上可行、展示效果明確，也能清楚說明每個技術在系統中的角色與適用性。
