# 本機資料結構與 SQLite 儲存設計 筆記

## 重點整理
- 這個 App 的資料負載不是普通 CRUD，而是高頻追加寫入、時間軸查詢、全文搜尋、版本化筆記和模型設定管理。
- 直接用 SQLite 當主要事實來源比較合理，因為它能精準控制 WAL、索引、FTS5、JSON、備份和遷移。
- SwiftData 適合小型 SwiftUI 資料模型，但不適合扛高頻逐字稿主路徑；Core Data 適合 CloudKit 同步是第一需求的情況。
- 主資料庫應該存會議、逐字稿片段、說話者標籤、AI 建議、筆記修訂版、行動項目、記憶快照和供應商設定。
- 錄音檔、embedding 檔、PDF 中間產物這種大型檔案不要塞 SQLite，只存路徑、hash 或 metadata。
- API key 和 refresh token 不應進資料庫，要存在 Keychain，SQLite 只存 Keychain reference 或 provider config。
- 逐字稿片段要同時保存片段層級時間戳和必要的 word timing，否則之後很難做精準回放、字幕重切或說話者重新對齊。
- 筆記不需要一開始就用 OT/CRDT；單機 MVP 用不可變修訂版和目前版本指標就夠。

## 對專題的影響
- 資料庫設計會決定後面的 AI 功能能不能追溯證據，不能只把整場逐字稿存成一大段文字。
- 即時 UI 和資料持久化要分開：暫定 token 可以先放記憶體，穩定片段才寫 SQLite。
- 如果有 evidence segment id，AI 建議和行動項目才能回到原始逐字稿，這對降低幻覺很重要。
- 本機優先的設計比較符合會議隱私，但要誠實說明本機資料庫預設未加密。
- 未來若要支援多模型或 BYOK，`provider_configs` 要先把 endpoint、model id、能力旗標、驗證方式拆開，不要寫死某一家 API。
- 匯出功能不只是 UI 附加品，它也可以當備份、測試資料和報告展示的一部分。

## 可以採用的做法
- 用單一 SQLite 主庫搭配 Swift actor 或序列寫入佇列，避免多執行緒同時亂寫。
- 開啟 WAL，採用一個寫入連線和多個讀取連線；寫入可以每 100 到 300ms 批次提交。
- 核心表先做：`meetings`、`transcript_segments`、`speaker_labels`、`ai_suggestions`、`meeting_notes`、`action_items`、`memory_snapshots`、`provider_configs`。
- 內部用整數 rowid 提升索引效率，對外用穩定字串 ID 方便匯出、除錯和跨系統整合。
- `transcript_segments` 要有 `seq_no`、`start_ms`、`end_ms`、`text`、`is_final`、`confidence`、`speaker_label_id`、`source`、`language`、`word_timing_json`。
- 不要保存每個暫定 token；只保留最近幾秒在記憶體，穩定片段用 UPSERT 更新，final 後再進全文搜尋。
- 時間軸查詢優先建 `(meeting_id, start_ms)`，說話者過濾再加 `(meeting_id, speaker_label_id, start_ms)`。
- FTS5 可以用外部內容表；中文逐字稿要注意 tokenizer，必要時用 trigram 或未來接中文斷詞。
- 筆記表用 `note_id + version` 管修訂版，並用部分唯一索引確保每份筆記只有一個目前版本。
- Markdown 匯出用固定段落：摘要、決策、行動項目、逐字稿；JSON 匯出則保留 schema version、會議、speakers、segments、notes、action_items。
- 備份可分兩種：日常自動備份用 SQLite backup API，使用者手動封存用 `VACUUM INTO` 產生乾淨副本。

## 風險與待確認
- SQLite WAL 不適合直接放在雲端同步資料夾裡同步活躍主庫，未來要多裝置同步應改做記錄層級同步。
- SQLite 預設沒有資料庫加密，只靠 FileVault 不是完整的 App 層保護；高敏感情境要評估 SQLCipher 或 SEE。
- 中文全文搜尋效果可能不如英文，需要實測 tokenizer 和索引大小。
- 說話者分離本身不穩，資料模型要允許 `speaker_label_id` 為 null，也要保留逐詞 speaker 資訊。
- `word_timing_json` 會讓資料變大，要決定保留期限和壓縮策略。
- 遷移要從第一版就規劃 `user_version` 和 migration scripts，不然後期 schema 改動會很痛。
- 還原備份不能直接覆蓋現用主庫，要先檢查 application id、user version、quick_check、integrity_check 和 foreign_key_check。
- 刪除會議時要同步刪資料庫列、外部錄音檔、匯出檔和索引，避免隱私資料殘留。
