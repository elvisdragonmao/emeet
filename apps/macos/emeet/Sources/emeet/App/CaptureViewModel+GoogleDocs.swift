import Foundation

@MainActor
extension CaptureViewModel {
    var googleDocsStatusLabel: String {
        switch googleDocsStatus {
        case .idle:
            return googleDocsAuthReady ? "已授權" : "未授權"
        case .starting:
            return "同步中"
        case .running:
            return googleDocsConnectedTitle.isEmpty ? "就緒" : "已連接"
        case .failed(let message):
            return message
        }
    }

    var googleDocsDetailLabel: String {
        if !googleDocsConnectedTitle.isEmpty {
            return googleDocsConnectedTitle
        }
        if !googleDocsDependenciesAvailable {
            return "請安裝 Google Python 依賴"
        }
        if !googleDocsClientConfigured {
            return "缺少 OAuth client JSON"
        }
        if googleDocsConnectedTitle.isEmpty {
            return googleDocsAuthReady ? "貼上 Google Docs 連結" : "授權 Google Docs"
        }
        return "Google Docs 就緒"
    }

    var googleDocsIsConnected: Bool {
        !googleDocsDocumentID.isEmpty
    }

    var googleDocsIsBusy: Bool {
        googleDocsStatus == .starting
    }

    func updateGoogleDocsURL(_ url: String) {
        googleDocsURL = url
    }

    func updateGoogleBrowserFindText(_ text: String) {
        googleBrowserFindText = text
    }

    func refreshGoogleAuthStatus() {
        Task {
            do {
                let response = try await assistantClient.fetchGoogleAuthStatus()
                applyGoogleAuthStatus(response)
                appendLog("Google Docs 授權狀態已載入。")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Docs 授權狀態載入失敗：\(error.localizedDescription)")
            }
        }
    }

    func startGoogleAuth() {
        guard googleDocsStatus != .starting else {
            return
        }

        googleDocsStatus = .starting
        googleDocsMessage = "正在開啟 Google OAuth 授權流程..."
        appendLog("正在啟動 Google Docs OAuth 授權流程。")
        Task {
            do {
                let response = try await assistantClient.startGoogleAuth()
                applyGoogleAuthStatus(response)
                googleDocsStatus = .idle
                googleDocsMessage = response.ready ? "Google Docs 授權已就緒。" : "Google Docs 授權尚未完成。"
                appendLog("Google Docs OAuth 授權流程已完成。")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Docs OAuth 授權失敗：\(error.localizedDescription)")
            }
        }
    }

    func refreshGoogleBrowserStatus() {
        Task {
            do {
                let response = try await assistantClient.fetchGoogleBrowserStatus()
                applyGoogleBrowserResponse(response)
                appendLog("Google Docs 瀏覽器輔助工具狀態已載入。")
            } catch {
                googleBrowserMessage = error.localizedDescription
                appendLog("Google Docs 瀏覽器輔助工具狀態載入失敗：\(error.localizedDescription)")
            }
        }
    }

    func connectGoogleDoc() {
        guard googleDocsStatus != .starting else {
            return
        }

        let trimmedURL = googleDocsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            googleDocsStatus = .failed("請先貼上 Google Docs 連結。")
            googleDocsMessage = "請先貼上 Google Docs 連結。"
            return
        }

        let meetingID = ensureCurrentMeetingID()
        googleDocsStatus = .starting
        googleDocsMessage = "正在連接 Google Doc..."
        appendLog("正在將 Google Doc 連接到會議 \(meetingID)。")

        let request = GoogleDocConnectRequest(
            url: trimmedURL,
            meetingID: meetingID,
            provider: assistantProviderID,
            model: assistantModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "gpt-5.5"
                : assistantModel,
            thinking: assistantThinking
        )

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let response = try await self.assistantClient.connectGoogleDoc(request)
                self.applyGoogleDocSnapshot(response, fallbackMessage: "Google Doc 已連接。")
                self.appendLog("Google Doc 已連接：\(response.title)。")
                await self.prepareMeetingFromDocumentSnapshotIfNeeded(response, meetingID: meetingID)
            } catch {
                self.googleDocsStatus = .failed(error.localizedDescription)
                self.googleDocsMessage = error.localizedDescription
                self.appendLog("Google Doc 連接失敗：\(error.localizedDescription)")
            }
        }
    }

    func refreshGoogleDocContext() {
        guard googleDocsIsConnected else {
            googleDocsMessage = "請先連接 Google Doc。"
            return
        }
        runGoogleDocSnapshotAction(
            label: "正在重新整理 Google Doc 內容...",
            request: GoogleDocMeetingRequest(meetingID: ensureCurrentMeetingID()),
            call: assistantClient.refreshGoogleDoc
        )
    }

    func prepareMeetingFromConnectedDocumentOnStart() {
        guard googleDocsIsConnected else {
            return
        }

        let meetingID = ensureCurrentMeetingID()
        guard beginDocumentBriefingPreparation(meetingID: meetingID) else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let snapshot = try await self.assistantClient.refreshGoogleDoc(
                    GoogleDocMeetingRequest(meetingID: meetingID)
                )
                guard self.currentMeetingID == meetingID else {
                    return
                }

                self.applyGoogleDocSnapshot(snapshot, fallbackMessage: "Google Doc 內容已重新整理。")
                try await self.prepareMeetingFromDocumentSnapshot(snapshot, meetingID: meetingID)
            } catch {
                self.handleDocumentBriefingFailure(error, meetingID: meetingID)
            }
        }
    }

    func prepareMeetingFromDocumentSnapshotIfNeeded(
        _ snapshot: GoogleDocSnapshotResponse,
        meetingID: String
    ) async {
        guard beginDocumentBriefingPreparation(meetingID: meetingID) else {
            return
        }

        do {
            try await prepareMeetingFromDocumentSnapshot(snapshot, meetingID: meetingID)
        } catch {
            handleDocumentBriefingFailure(error, meetingID: meetingID)
        }
    }

    func beginDocumentBriefingPreparation(meetingID: String) -> Bool {
        guard !documentPreparedMeetingIDs.contains(meetingID) else {
            return false
        }

        guard noteDrafts.isEmpty && actionDrafts.isEmpty else {
            appendLog("已略過 Google Doc 會議準備，因為已有會議紀錄或行動項目。")
            return false
        }

        documentPreparedMeetingIDs.insert(meetingID)
        googleDocsStatus = .starting
        googleDocsMessage = "正在根據 Google Doc 準備會議..."
        assistantStatus = .starting
        assistantModeLabel = "文件準備 · \(assistantProviderID)"
        autoSummaryStatusLabel = "正在根據文件準備"
        appendLog("正在根據已連接的 Google Doc 準備初始會議紀錄。")
        return true
    }

    func prepareMeetingFromDocumentSnapshot(
        _ snapshot: GoogleDocSnapshotResponse,
        meetingID: String
    ) async throws {
        guard currentMeetingID == meetingID else {
            return
        }

        let fullDocumentText = (snapshot.plainText ?? googleDocsPlainText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let documentSummary = fullDocumentText.isEmpty ? snapshot.preview : fullDocumentText

        let request = AssistantRespondRequest(
            action: "document_briefing",
            meetingID: meetingID,
            provider: assistantProviderID,
            model: assistantModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "gpt-5.5"
                : assistantModel,
            thinking: assistantThinking,
            transcript: [],
            rollingSummary: "",
            previousNotes: [],
            previousActions: [],
            documentTitle: snapshot.title,
            documentSummary: documentSummary,
            documentSnippets: snapshot.snippets ?? googleDocsSnippets,
            documentBriefing: ""
        )

        let response = try await assistantClient.respond(request)
        guard currentMeetingID == meetingID else {
            return
        }

        applyInitialDocumentBriefingResponse(response)
    }

    func handleDocumentBriefingFailure(_ error: Error, meetingID: String) {
        guard currentMeetingID == meetingID else {
            return
        }

        documentPreparedMeetingIDs.remove(meetingID)
        googleDocsStatus = .failed(error.localizedDescription)
        googleDocsMessage = error.localizedDescription
        assistantStatus = .failed(error.localizedDescription)
        assistantModeLabel = "文件準備失敗"
        autoSummaryStatusLabel = "文件準備失敗"
        appendLog("Google Doc 會議準備失敗：\(error.localizedDescription)")
    }

    func appendMeetingNotesToGoogleDoc() {
        guard googleDocsIsConnected else {
            googleDocsMessage = "請先連接 Google Doc。"
            return
        }

        let request = googleDocMeetingNotesRequest()
        googleDocsStatus = .starting
        googleDocsMessage = "正在附加會議紀錄..."
        appendLog("正在將會議紀錄附加到 Google Doc。")

        Task {
            do {
                let response = try await assistantClient.appendMeetingNotesToGoogleDoc(request)
                applyGoogleDocSnapshot(response, fallbackMessage: "會議紀錄已附加。")
                appendLog("會議紀錄已附加到 Google Doc。")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("附加到 Google Doc 失敗：\(error.localizedDescription)")
            }
        }
    }

    func updateGoogleDocLiveNotes() {
        updateGoogleDocLiveNotes(triggeredByAutoSummary: false)
    }

    func openGoogleDocInBrowser() {
        guard googleDocsIsConnected || !googleDocsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            googleBrowserMessage = "請先連接 Google Doc 或貼上連結。"
            googleDocsMessage = googleBrowserMessage
            return
        }

        let request = GoogleBrowserOpenRequest(
            meetingID: ensureCurrentMeetingID(),
            url: googleDocsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        googleDocsMessage = "正在開啟 Google Doc..."
        appendLog("正在透過瀏覽器輔助工具開啟 Google Doc。")
        Task {
            do {
                let response = try await assistantClient.openGoogleDocInBrowser(request)
                applyGoogleBrowserResponse(response)
                appendLog("Google Doc 瀏覽器開啟結果：\(response.message)")
            } catch {
                googleBrowserMessage = error.localizedDescription
                googleDocsMessage = error.localizedDescription
                appendLog("Google Doc 瀏覽器開啟失敗：\(error.localizedDescription)")
            }
        }
    }

    func scrollGoogleDocBrowserToBottom() {
        let request = GoogleBrowserMeetingRequest(meetingID: ensureCurrentMeetingID())
        appendLog("正在捲動 Google Doc 瀏覽器畫面。")
        Task {
            do {
                let response = try await assistantClient.scrollGoogleDocBrowserToBottom(request)
                applyGoogleBrowserResponse(response)
                appendLog("Google Doc 瀏覽器捲動結果：\(response.message)")
            } catch {
                googleBrowserMessage = error.localizedDescription
                appendLog("Google Doc 瀏覽器捲動失敗：\(error.localizedDescription)")
            }
        }
    }

    func findVisibleTextInGoogleDocBrowser() {
        let query = googleBrowserFindText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            googleBrowserMessage = "請輸入要在瀏覽器中尋找的文字。"
            return
        }

        let request = GoogleBrowserFindRequest(meetingID: ensureCurrentMeetingID(), text: query)
        appendLog("正在 Google Doc 瀏覽器畫面尋找可見文字。")
        Task {
            do {
                let response = try await assistantClient.findVisibleGoogleDocText(request)
                applyGoogleBrowserResponse(response)
                appendLog("Google Doc 瀏覽器搜尋結果：\(response.message)")
            } catch {
                googleBrowserMessage = error.localizedDescription
                appendLog("Google Doc 瀏覽器搜尋失敗：\(error.localizedDescription)")
            }
        }
    }

    func startDocumentEditWatcher() {
        documentEditTask?.cancel()
        documentEditRequestGeneration += 1
        documentEditIsPlanning = false

        documentEditTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    break
                }
                self.tickDocumentEditWatcher()
                try? await Task.sleep(nanoseconds: UInt64(self.documentEditIntervalSeconds) * 1_000_000_000)
                guard !Task.isCancelled else {
                    break
                }
            }
        }
    }

    func stopDocumentEditWatcher() {
        documentEditTask?.cancel()
        documentEditTask = nil
        documentEditDebounceTask?.cancel()
        documentEditDebounceTask = nil
        documentEditRequestGeneration += 1
        documentEditIsPlanning = false
    }

    func scheduleDocumentEditWatcherTick() {
        guard googleDocsIsConnected else {
            return
        }

        documentEditDebounceTask?.cancel()
        documentEditDebounceTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(self.documentEditDebounceMilliseconds) * 1_000_000)
            guard !Task.isCancelled else {
                return
            }
            self.tickDocumentEditWatcher()
        }
    }

    func tickDocumentEditWatcher() {
        guard transcriptionStatus == .starting || transcriptionStatus == .running else {
            return
        }
        guard googleDocsIsConnected else {
            return
        }
        guard !googleDocsIsBusy, !documentEditIsPlanning else {
            return
        }

        let newFinalLines = finalTranscriptArchive.filter { !documentEditCheckedFinalLineIDs.contains($0.id) }
        guard !newFinalLines.isEmpty else {
            return
        }
        let commandHint = documentEditCommandHint(in: newFinalLines)

        documentEditIsPlanning = true
        googleDocsMessage = "正在檢查語音文件修改指令..."
        documentEditRequestGeneration += 1
        let requestGeneration = documentEditRequestGeneration
        let lineIDsToMark = Set(newFinalLines.map(\.id))
        let anchorLine = newFinalLines.last
        let markerID = documentEditMarkerID(for: newFinalLines)
        let markerAnchorLineID = anchorLine?.id
        let markerAnchorMs = anchorLine?.endMs ?? anchorLine?.startMs

        if commandHint != nil {
            recordTranscriptMarker(
                id: markerID,
                title: "正在判斷文件修改指令",
                detail: documentEditTranscriptPreview(newFinalLines),
                iconName: "wand.and.stars",
                style: .progress,
                anchorLineID: markerAnchorLineID,
                anchorMs: markerAnchorMs
            )
        }

        let request = AssistantRespondRequest(
            action: "document_edit_plan",
            meetingID: ensureCurrentMeetingID(),
            provider: assistantProviderID,
            model: assistantModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "gpt-5.5"
                : assistantModel,
            thinking: assistantThinking,
            transcript: assistantTranscriptPayload(finalOnly: true),
            rollingSummary: "",
            previousNotes: [],
            previousActions: [],
            documentTitle: googleDocsConnectedTitle,
            documentSummary: googleDocsPreview,
            documentSnippets: googleDocsSnippets,
            documentBriefing: googleDocsBriefing
        )

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            defer {
                if self.documentEditRequestGeneration == requestGeneration {
                    self.documentEditIsPlanning = false
                }
            }

            do {
                let response = try await self.assistantClient.respond(request)
                guard self.documentEditRequestGeneration == requestGeneration else {
                    return
                }

                guard let plan = response.documentEditPlan, plan.intent != "none" else {
                    self.documentEditCheckedFinalLineIDs.formUnion(lineIDsToMark)
                    if let commandHint {
                        let detail: String
                        switch commandHint {
                        case .explicit:
                            let reason = response.documentEditPlan?.reason ?? ""
                            detail = !reason.isEmpty
                                ? reason
                                : "AI 判斷這段內容還不足以安全修改文件，請再說一次位置與要新增或替換的文字。"
                        case .missingWakeWord:
                            detail = "聽到疑似文件修改內容。請用「AI 幫我...」或「請你幫我...」開頭，並說清楚位置與內容。"
                        }
                        self.recordTranscriptMarker(
                            id: markerID,
                            title: "沒有套用文件修改",
                            detail: detail,
                            iconName: "exclamationmark.bubble",
                            style: .warning,
                            anchorLineID: markerAnchorLineID,
                            anchorMs: markerAnchorMs
                        )
                    }
                    self.googleDocsMessage = "正在聆聽 AI 文件修改指令。"
                    return
                }

                guard !plan.requiresUserConfirmation else {
                    self.documentEditCheckedFinalLineIDs.formUnion(lineIDsToMark)
                    self.googleDocsMessage = plan.reason.isEmpty
                        ? "AI 文件修改指令需要更多資訊。"
                        : "AI 文件修改指令需要更多資訊：\(plan.reason)"
                    self.recordTranscriptMarker(
                        id: markerID,
                        title: "文件修改指令需要更多資訊",
                        detail: plan.reason.isEmpty ? "請補充要修改的位置與內容。" : plan.reason,
                        iconName: "questionmark.bubble",
                        style: .warning,
                        anchorLineID: markerAnchorLineID,
                        anchorMs: markerAnchorMs
                    )
                    return
                }

                guard plan.intent != "append_meeting_notes" || self.documentEditRequestsMeetingNotes(newFinalLines) else {
                    self.documentEditCheckedFinalLineIDs.formUnion(lineIDsToMark)
                    self.googleDocsMessage = "已避免錯誤附加會議紀錄。"
                    self.recordTranscriptMarker(
                        id: markerID,
                        title: "沒有套用文件修改",
                        detail: "AI 回傳的是附加會議紀錄，但這段指令不是要求附加會議紀錄。請再說一次要寫到文件最後的文字。",
                        iconName: "exclamationmark.bubble",
                        style: .warning,
                        anchorLineID: markerAnchorLineID,
                        anchorMs: markerAnchorMs
                    )
                    return
                }

                let editKey = self.documentEditKey(plan)
                guard !self.appliedDocumentEditKeys.contains(editKey) else {
                    self.documentEditCheckedFinalLineIDs.formUnion(lineIDsToMark)
                    self.googleDocsMessage = "這個 AI 文件修改指令已套用過。"
                    self.recordTranscriptMarker(
                        id: markerID,
                        title: "已略過重複文件修改",
                        detail: self.documentEditPlanSummary(plan),
                        iconName: "checkmark.seal",
                        style: .info,
                        anchorLineID: markerAnchorLineID,
                        anchorMs: markerAnchorMs
                    )
                    return
                }

                self.googleDocsStatus = .starting
                self.googleDocsMessage = "正在套用 AI 語音文件修改..."
                self.recordTranscriptMarker(
                    id: markerID,
                    title: "正在套用文件修改",
                    detail: self.documentEditPlanSummary(plan),
                    iconName: "doc.text.magnifyingglass",
                    style: .progress,
                    anchorLineID: markerAnchorLineID,
                    anchorMs: markerAnchorMs
                )
                let snapshot = try await self.applyDocumentEditPlan(plan)
                guard self.documentEditRequestGeneration == requestGeneration else {
                    return
                }

                self.appliedDocumentEditKeys.insert(editKey)
                self.documentEditCheckedFinalLineIDs.formUnion(lineIDsToMark)
                self.applyGoogleDocSnapshot(snapshot, fallbackMessage: "AI 語音文件修改已套用。")
                self.recordTranscriptMarker(
                    id: markerID,
                    title: "已套用文件修改",
                    detail: self.documentEditPlanSummary(plan),
                    iconName: "checkmark.circle",
                    style: .success,
                    anchorLineID: markerAnchorLineID,
                    anchorMs: markerAnchorMs
                )
                self.appendLog("AI 語音文件修改已套用：\(self.documentEditLabel(plan.intent))。")
            } catch {
                guard self.documentEditRequestGeneration == requestGeneration else {
                    return
                }

                self.documentEditCheckedFinalLineIDs.formUnion(lineIDsToMark)
                self.googleDocsStatus = .failed(error.localizedDescription)
                self.googleDocsMessage = error.localizedDescription
                self.recordTranscriptMarker(
                    id: markerID,
                    title: "文件修改失敗",
                    detail: error.localizedDescription,
                    iconName: "xmark.octagon",
                    style: .failure,
                    anchorLineID: markerAnchorLineID,
                    anchorMs: markerAnchorMs
                )
                self.appendLog("AI 語音文件修改失敗：\(error.localizedDescription)")
            }

        }
    }

    func applyGoogleAuthStatus(_ response: GoogleAuthStatusResponse) {
        googleDocsAuthReady = response.ready
        googleDocsClientConfigured = response.clientConfigured
        googleDocsDependenciesAvailable = response.dependenciesAvailable
        if googleDocsStatus != .starting {
            googleDocsStatus = response.ready ? .idle : .failed("需要 Google Docs 授權。")
        }
        if !response.dependenciesAvailable {
            googleDocsMessage = "請在後端環境安裝 Google API Python 依賴。"
        } else if !response.clientConfigured {
            googleDocsMessage = "請將 OAuth client JSON 儲存到 apps/backend/secrets/google_oauth_client.json。"
        } else if !response.ready {
            googleDocsMessage = "請按授權以建立 apps/backend/secrets/google_token.json。"
        } else if googleDocsConnectedTitle.isEmpty {
            googleDocsMessage = "Google Docs 授權已就緒。"
        }
    }

    func applyGoogleDocSnapshot(
        _ response: GoogleDocSnapshotResponse,
        fallbackMessage: String
    ) {
        googleDocsStatus = .running
        googleDocsAuthReady = true
        googleDocsClientConfigured = true
        googleDocsDependenciesAvailable = true
        googleDocsConnectedTitle = response.title
        googleDocsDocumentID = response.documentId
        googleDocsRevisionID = response.revisionId
        googleDocsPreview = response.preview
        googleDocsPlainText = response.plainText ?? googleDocsPlainText
        googleDocsBriefing = response.documentBriefing ?? googleDocsBriefing
        googleDocsSnippets = response.snippets ?? googleDocsSnippets
        if let briefingError = response.briefingError, !briefingError.isEmpty {
            googleDocsMessage = "已連接，但文件整理失敗：\(briefingError)"
        } else {
            googleDocsMessage = response.message ?? fallbackMessage
        }
    }

    func applyInitialDocumentBriefingResponse(_ response: AssistantRespondResponse) {
        let notes = response.notes.map {
            MeetingNoteDraft(
                title: documentContextNoteTitle($0.title),
                detail: documentContextDetail($0.detail)
            )
        }
        let actions = response.actions.map {
            MeetingActionDraft(
                title: $0.title,
                owner: documentContextActionOwner($0.owner),
                state: documentContextActionState($0.state)
            )
        }

        if !notes.isEmpty {
            noteDrafts = notes
        }
        if !actions.isEmpty {
            actionDrafts = actions
        }

        googleDocsBriefing = documentBriefingText(notes: response.notes, actions: response.actions)
        googleDocsStatus = .running
        googleDocsMessage = notes.isEmpty && actions.isEmpty
            ? "Google Doc 已連接，文件內容已載入。"
            : "Google Doc 已連接，會議紀錄已準備。"
        assistantStatus = .running
        assistantModeLabel = "文件準備 · \(response.provider) · \(response.model) · \(response.latencyMs) ms"
        autoSummaryStatusLabel = notes.isEmpty && actions.isEmpty
            ? "文件內容已載入"
            : "文件內容已準備"
        appendLog("已根據 Google Doc 準備初始會議紀錄：\(response.latencyMs)ms。")
    }

    func applyGoogleBrowserResponse(_ response: GoogleBrowserResponse) {
        googleBrowserMessage = response.message
        googleDocsMessage = response.message
        googleBrowserSeleniumAvailable = response.seleniumAvailable
        googleBrowserChromeDriverAvailable = response.chromedriverAvailable
        googleBrowserSessionActive = response.browserSessionActive
    }

    func runGoogleDocSnapshotAction(
        label: String,
        request: GoogleDocMeetingRequest,
        call: @escaping (GoogleDocMeetingRequest) async throws -> GoogleDocSnapshotResponse
    ) {
        guard googleDocsStatus != .starting else {
            return
        }

        googleDocsStatus = .starting
        googleDocsMessage = label
        appendLog(label)
        Task {
            do {
                let response = try await call(request)
                applyGoogleDocSnapshot(response, fallbackMessage: "Google Doc 內容已重新整理。")
                appendLog("Google Doc 內容已重新整理。")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Doc 重新整理失敗：\(error.localizedDescription)")
            }
        }
    }

    func updateGoogleDocLiveNotes(triggeredByAutoSummary: Bool) {
        guard googleDocsIsConnected else {
            googleDocsMessage = "請先連接 Google Doc。"
            return
        }
        guard !googleDocsIsBusy else {
            if !triggeredByAutoSummary {
                googleDocsMessage = "Google Docs 請求仍在執行。"
            }
            return
        }

        let request = googleDocMeetingNotesRequest()
        googleDocsStatus = .starting
        googleDocsMessage = triggeredByAutoSummary ? "正在自動更新即時紀錄..." : "正在更新即時紀錄..."
        appendLog(triggeredByAutoSummary ? "正在自動更新 Google Doc 即時紀錄。" : "正在更新 Google Doc 即時紀錄。")

        Task {
            do {
                let response = try await assistantClient.updateGoogleDocLiveNotes(request)
                applyGoogleDocSnapshot(response, fallbackMessage: "即時紀錄已更新。")
                appendLog("Google Doc 即時紀錄已更新。")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Doc 即時紀錄更新失敗：\(error.localizedDescription)")
            }
        }
    }

    func applyDocumentEditPlan(_ plan: DocumentEditPlanResponse) async throws -> GoogleDocSnapshotResponse {
        switch plan.intent {
        case "replace_text":
            let find = plan.find.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !find.isEmpty else {
                throw VoiceEditError("AI 修改計畫缺少要尋找的文字。")
            }
            return try await assistantClient.replaceGoogleDocText(
                GoogleDocReplaceTextRequest(
                    meetingID: ensureCurrentMeetingID(),
                    find: find,
                    replace: plan.replace,
                    occurrence: plan.occurrence == "all" ? "all" : "first"
                )
            )

        case "append_text":
            let text = plan.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                throw VoiceEditError("AI 修改計畫缺少要附加到文件最後的文字。")
            }
            return try await assistantClient.appendGoogleDocText(
                GoogleDocAppendRequest(
                    meetingID: ensureCurrentMeetingID(),
                    text: text
                )
            )

        case "insert_under_heading":
            let heading = plan.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = plan.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heading.isEmpty else {
                throw VoiceEditError("AI 修改計畫缺少標題。")
            }
            guard !text.isEmpty else {
                throw VoiceEditError("AI 修改計畫缺少要新增的文字。")
            }
            return try await assistantClient.insertGoogleDocTextUnderHeading(
                GoogleDocInsertUnderHeadingRequest(
                    meetingID: ensureCurrentMeetingID(),
                    heading: heading,
                    text: text
                )
            )

        case "rewrite_paragraph_containing_anchor":
            let anchor = plan.anchor.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = plan.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !anchor.isEmpty else {
                throw VoiceEditError("AI 修改計畫缺少定位文字。")
            }
            guard !text.isEmpty else {
                throw VoiceEditError("AI 修改計畫缺少替換文字。")
            }
            return try await assistantClient.rewriteGoogleDocParagraph(
                GoogleDocRewriteParagraphRequest(
                    meetingID: ensureCurrentMeetingID(),
                    anchor: anchor,
                    text: text
                )
            )

        case "append_meeting_notes":
            return try await assistantClient.appendMeetingNotesToGoogleDoc(googleDocMeetingNotesRequest())

        default:
            throw VoiceEditError("AI 修改計畫缺少可執行的意圖。")
        }
    }

    func googleDocMeetingNotesRequest() -> GoogleDocMeetingNotesRequest {
        GoogleDocMeetingNotesRequest(
            meetingID: ensureCurrentMeetingID(),
            notes: previousNoteContextPayload(),
            actions: previousActionContextPayload(),
            transcript: assistantTranscriptPayload(finalOnly: true)
        )
    }

    func documentEditKey(_ plan: DocumentEditPlanResponse) -> String {
        [
            plan.intent,
            plan.find,
            plan.replace,
            plan.heading,
            plan.text,
            plan.anchor,
            plan.occurrence,
        ]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: "\u{1f}")
    }

    func documentEditLabel(_ intent: String) -> String {
        switch intent {
        case "replace_text":
            return "替換文字"
        case "append_text":
            return "在文件最後新增文字"
        case "insert_under_heading":
            return "在標題下新增內容"
        case "rewrite_paragraph_containing_anchor":
            return "重寫段落"
        case "append_meeting_notes":
            return "附加會議紀錄"
        default:
            return "文件修改"
        }
    }

    func documentEditMarkerID(for lines: [TranscriptLine]) -> String {
        let lineKey = lines.map(\.id).joined(separator: "-")
        if lineKey.isEmpty {
            return "document-edit-\(documentEditRequestGeneration)"
        }
        return "document-edit-\(lineKey)"
    }

    func documentEditPlanSummary(_ plan: DocumentEditPlanResponse) -> String {
        switch plan.intent {
        case "replace_text":
            let find = plan.find.trimmingCharacters(in: .whitespacesAndNewlines)
            let replace = plan.replace.trimmingCharacters(in: .whitespacesAndNewlines)
            let occurrence = plan.occurrence == "all" ? "全部" : "第一處"
            return "把\(occurrence)「\(shortDocumentEditText(find))」替換成「\(shortDocumentEditText(replace))」。"

        case "append_text":
            let text = plan.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "在文件最後新增：「\(shortDocumentEditText(text))」。"

        case "insert_under_heading":
            let heading = plan.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = plan.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "在「\(shortDocumentEditText(heading))」下面新增：「\(shortDocumentEditText(text))」。"

        case "rewrite_paragraph_containing_anchor":
            let anchor = plan.anchor.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = plan.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return "重寫包含「\(shortDocumentEditText(anchor))」的段落為：「\(shortDocumentEditText(text))」。"

        case "append_meeting_notes":
            return "把目前會議紀錄與下一步行動附加到文件。"

        default:
            return documentEditLabel(plan.intent)
        }
    }

    func shortDocumentEditText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 80 else {
            return trimmed
        }
        return "\(trimmed.prefix(80))..."
    }

    func documentEditCommandHint(in lines: [TranscriptLine]) -> DocumentEditCommandHint? {
        let text = lines
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }

        let editTerms = ["文件", "新增", "加上", "改成", "修改", "替換", "下面", "最後面", "最後", "刪掉"]
        let matchedCount = editTerms.filter { text.contains($0) }.count
        let loweredText = text.lowercased()
        if matchedCount >= 1
            && (loweredText.contains("ai")
                || text.contains("請你幫我")
                || text.contains("請幫我")
                || text.contains("幫我")) {
            return .explicit
        }

        if matchedCount >= 2 {
            return .missingWakeWord
        }

        return nil
    }

    func documentEditRequestsMeetingNotes(_ lines: [TranscriptLine]) -> Bool {
        let text = lines
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let noteTerms = [
            "會議紀錄",
            "會議記錄",
            "meeting notes",
            "meeting record",
            "next actions",
            "下一步",
            "行動項目",
            "待辦",
            "todo",
        ]
        return noteTerms.contains { text.contains($0) }
    }

    func documentEditTranscriptPreview(_ lines: [TranscriptLine]) -> String {
        let text = lines
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return "AI 正在檢查最新完成的逐字稿。"
        }
        return "聽到：「\(String(text.prefix(120)))」"
    }

    func documentContextDetail(_ detail: String) -> String {
        let bulletLines = detail
            .components(separatedBy: .newlines)
            .map { normalizedDocumentContextBullet($0) }
            .filter { !$0.isEmpty }

        guard !bulletLines.isEmpty else {
            return "• 文件中尚無足夠內容。"
        }

        return bulletLines.joined(separator: "\n")
    }

    func documentContextActionState(_ state: String) -> String {
        let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        if trimmed.isEmpty || lowered == "draft" || lowered.contains("document draft") {
            return "草稿"
        }
        if lowered.contains("open") {
            return "待確認"
        }
        if lowered.contains("waiting") {
            return "等待中"
        }
        if lowered.contains("confirmed") {
            return "已確認"
        }
        if lowered.contains("blocked") {
            return "受阻"
        }
        return trimmed
    }

    func documentBriefingText(notes: [MeetingNoteResponse], actions: [MeetingActionResponse]) -> String {
        var lines: [String] = []
        for note in notes {
            lines.append("\(documentContextNoteTitle(note.title)):")
            lines.append(documentContextDetail(note.detail))
        }
        if !actions.isEmpty {
            lines.append("下一步行動:")
            for action in actions {
                lines.append(
                    "- \(action.title) / owner=\(documentContextActionOwner(action.owner)) / state=\(documentContextActionState(action.state))"
                )
            }
        }
        return lines.joined(separator: "\n")
    }

    func documentContextNoteTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "document summary":
            return "會前文件重點"
        case "current todos and open questions", "current todos / open questions":
            return "待辦與開放問題"
        case "likely meeting agenda":
            return "可能討論議程"
        case "sections needing clarification":
            return "需要釐清的事項"
        default:
            return trimmed.isEmpty ? "會前文件重點" : trimmed
        }
    }

    func documentContextActionOwner(_ owner: String) -> String {
        let trimmed = owner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "unassigned" else {
            return "未指派"
        }
        return trimmed
    }

    func normalizedDocumentContextBullet(_ line: String) -> String {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let lowered = trimmed.lowercased()
        if lowered.hasPrefix("source:")
            || lowered.contains("connected google doc before the meeting") {
            return ""
        }

        while let first = trimmed.first, ["-", "*", "•", "‣"].contains(first) {
            trimmed.removeFirst()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !trimmed.isEmpty else {
            return ""
        }
        return "• \(trimmed)"
    }

}
