import Foundation

@MainActor
extension CaptureViewModel {
    var googleDocsStatusLabel: String {
        switch googleDocsStatus {
        case .idle:
            return googleDocsAuthReady ? "Auth ready" : "Not authorized"
        case .starting:
            return "Syncing"
        case .running:
            return googleDocsConnectedTitle.isEmpty ? "Ready" : "Connected"
        case .failed(let message):
            return message
        }
    }

    var googleDocsDetailLabel: String {
        if !googleDocsDependenciesAvailable {
            return "Install Google Python dependencies"
        }
        if !googleDocsClientConfigured {
            return "Missing OAuth client JSON"
        }
        if googleDocsConnectedTitle.isEmpty {
            return googleDocsAuthReady ? "Paste a Google Docs URL" : "Authorize Google Docs"
        }
        return googleDocsConnectedTitle
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
                appendLog("Google Docs auth status loaded.")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Docs auth status failed: \(error.localizedDescription)")
            }
        }
    }

    func startGoogleAuth() {
        guard googleDocsStatus != .starting else {
            return
        }

        googleDocsStatus = .starting
        googleDocsMessage = "Opening Google OAuth flow..."
        appendLog("Starting Google Docs OAuth flow.")
        Task {
            do {
                let response = try await assistantClient.startGoogleAuth()
                applyGoogleAuthStatus(response)
                googleDocsStatus = .idle
                googleDocsMessage = response.ready ? "Google Docs authorization is ready." : "Google Docs authorization is incomplete."
                appendLog("Google Docs OAuth flow finished.")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Docs OAuth failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshGoogleBrowserStatus() {
        Task {
            do {
                let response = try await assistantClient.fetchGoogleBrowserStatus()
                applyGoogleBrowserResponse(response)
                appendLog("Google Docs browser helper status loaded.")
            } catch {
                googleBrowserMessage = error.localizedDescription
                appendLog("Google Docs browser helper status failed: \(error.localizedDescription)")
            }
        }
    }

    func connectGoogleDoc() {
        guard googleDocsStatus != .starting else {
            return
        }

        let trimmedURL = googleDocsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else {
            googleDocsStatus = .failed("Paste a Google Docs URL first.")
            googleDocsMessage = "Paste a Google Docs URL first."
            return
        }

        let meetingID = ensureCurrentMeetingID()
        googleDocsStatus = .starting
        googleDocsMessage = "Connecting Google Doc..."
        appendLog("Connecting Google Doc to \(meetingID).")

        let request = GoogleDocConnectRequest(
            url: trimmedURL,
            meetingID: meetingID,
            provider: assistantProviderID,
            model: assistantModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "gpt-5.5"
                : assistantModel,
            thinking: assistantThinking
        )

        Task {
            do {
                let response = try await assistantClient.connectGoogleDoc(request)
                applyGoogleDocSnapshot(response, fallbackMessage: "Google Doc connected.")
                appendLog("Google Doc connected: \(response.title).")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Doc connect failed: \(error.localizedDescription)")
            }
        }
    }

    func refreshGoogleDocContext() {
        guard googleDocsIsConnected else {
            googleDocsMessage = "Connect a Google Doc first."
            return
        }
        runGoogleDocSnapshotAction(
            label: "Refreshing Google Doc context...",
            request: GoogleDocMeetingRequest(meetingID: ensureCurrentMeetingID()),
            call: assistantClient.refreshGoogleDoc
        )
    }

    func appendMeetingNotesToGoogleDoc() {
        guard googleDocsIsConnected else {
            googleDocsMessage = "Connect a Google Doc first."
            return
        }

        let request = googleDocMeetingNotesRequest()
        googleDocsStatus = .starting
        googleDocsMessage = "Appending meeting notes..."
        appendLog("Appending meeting notes to Google Doc.")

        Task {
            do {
                let response = try await assistantClient.appendMeetingNotesToGoogleDoc(request)
                applyGoogleDocSnapshot(response, fallbackMessage: "Meeting notes appended.")
                appendLog("Meeting notes appended to Google Doc.")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Append to Google Doc failed: \(error.localizedDescription)")
            }
        }
    }

    func updateGoogleDocLiveNotes() {
        updateGoogleDocLiveNotes(triggeredByAutoSummary: false)
    }

    func openGoogleDocInBrowser() {
        guard googleDocsIsConnected || !googleDocsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            googleBrowserMessage = "Connect a Google Doc or paste a URL first."
            googleDocsMessage = googleBrowserMessage
            return
        }

        let request = GoogleBrowserOpenRequest(
            meetingID: ensureCurrentMeetingID(),
            url: googleDocsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        googleDocsMessage = "Opening Google Doc..."
        appendLog("Opening Google Doc in browser helper.")
        Task {
            do {
                let response = try await assistantClient.openGoogleDocInBrowser(request)
                applyGoogleBrowserResponse(response)
                appendLog("Google Doc browser open result: \(response.message)")
            } catch {
                googleBrowserMessage = error.localizedDescription
                googleDocsMessage = error.localizedDescription
                appendLog("Google Doc browser open failed: \(error.localizedDescription)")
            }
        }
    }

    func scrollGoogleDocBrowserToBottom() {
        let request = GoogleBrowserMeetingRequest(meetingID: ensureCurrentMeetingID())
        appendLog("Scrolling Google Doc browser view.")
        Task {
            do {
                let response = try await assistantClient.scrollGoogleDocBrowserToBottom(request)
                applyGoogleBrowserResponse(response)
                appendLog("Google Doc browser scroll result: \(response.message)")
            } catch {
                googleBrowserMessage = error.localizedDescription
                appendLog("Google Doc browser scroll failed: \(error.localizedDescription)")
            }
        }
    }

    func findVisibleTextInGoogleDocBrowser() {
        let query = googleBrowserFindText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            googleBrowserMessage = "Enter text for browser find."
            return
        }

        let request = GoogleBrowserFindRequest(meetingID: ensureCurrentMeetingID(), text: query)
        appendLog("Finding visible text in Google Doc browser view.")
        Task {
            do {
                let response = try await assistantClient.findVisibleGoogleDocText(request)
                applyGoogleBrowserResponse(response)
                appendLog("Google Doc browser find result: \(response.message)")
            } catch {
                googleBrowserMessage = error.localizedDescription
                appendLog("Google Doc browser find failed: \(error.localizedDescription)")
            }
        }
    }

    func startDocumentEditWatcher() {
        documentEditTask?.cancel()
        documentEditRequestGeneration += 1
        documentEditIsPlanning = false

        documentEditTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(self?.documentEditIntervalSeconds ?? 10) * 1_000_000_000)
                guard !Task.isCancelled else {
                    break
                }
                guard let self else {
                    break
                }
                self.tickDocumentEditWatcher()
            }
        }
    }

    func stopDocumentEditWatcher() {
        documentEditTask?.cancel()
        documentEditTask = nil
        documentEditRequestGeneration += 1
        documentEditIsPlanning = false
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

        documentEditIsPlanning = true
        googleDocsMessage = "Checking voice edit commands..."
        documentEditRequestGeneration += 1
        let requestGeneration = documentEditRequestGeneration
        let lineIDsToMark = Set(newFinalLines.map(\.id))

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
                    self.googleDocsMessage = "Listening for AI edit commands."
                    return
                }

                guard !plan.requiresUserConfirmation else {
                    self.documentEditCheckedFinalLineIDs.formUnion(lineIDsToMark)
                    self.googleDocsMessage = plan.reason.isEmpty
                        ? "AI edit command needs more detail."
                        : "AI edit command needs more detail: \(plan.reason)"
                    return
                }

                let editKey = self.documentEditKey(plan)
                guard !self.appliedDocumentEditKeys.contains(editKey) else {
                    self.documentEditCheckedFinalLineIDs.formUnion(lineIDsToMark)
                    self.googleDocsMessage = "AI edit command was already applied."
                    return
                }

                self.googleDocsStatus = .starting
                self.googleDocsMessage = "Applying AI voice edit..."
                let snapshot = try await self.applyDocumentEditPlan(plan)
                guard self.documentEditRequestGeneration == requestGeneration else {
                    return
                }

                self.appliedDocumentEditKeys.insert(editKey)
                self.documentEditCheckedFinalLineIDs.formUnion(lineIDsToMark)
                self.applyGoogleDocSnapshot(snapshot, fallbackMessage: "AI voice edit applied.")
                self.appendLog("AI voice edit applied: \(self.documentEditLabel(plan.intent)).")
            } catch {
                guard self.documentEditRequestGeneration == requestGeneration else {
                    return
                }

                self.documentEditCheckedFinalLineIDs.formUnion(lineIDsToMark)
                self.googleDocsStatus = .failed(error.localizedDescription)
                self.googleDocsMessage = error.localizedDescription
                self.appendLog("AI voice edit failed: \(error.localizedDescription)")
            }

        }
    }

    func applyGoogleAuthStatus(_ response: GoogleAuthStatusResponse) {
        googleDocsAuthReady = response.ready
        googleDocsClientConfigured = response.clientConfigured
        googleDocsDependenciesAvailable = response.dependenciesAvailable
        if googleDocsStatus != .starting {
            googleDocsStatus = response.ready ? .idle : .failed("Google Docs authorization required.")
        }
        if !response.dependenciesAvailable {
            googleDocsMessage = "Install Google API Python dependencies in the backend environment."
        } else if !response.clientConfigured {
            googleDocsMessage = "Save OAuth client JSON to apps/backend/secrets/google_oauth_client.json."
        } else if !response.ready {
            googleDocsMessage = "Click Authorize to create apps/backend/secrets/google_token.json."
        } else if googleDocsConnectedTitle.isEmpty {
            googleDocsMessage = "Google Docs authorization is ready."
        }
    }

    func applyGoogleDocSnapshot(
        _ response: GoogleDocSnapshotResponse,
        fallbackMessage: String
    ) {
        googleDocsStatus = .running
        googleDocsAuthReady = true
        googleDocsConnectedTitle = response.title
        googleDocsDocumentID = response.documentId
        googleDocsRevisionID = response.revisionId
        googleDocsPreview = response.preview
        googleDocsPlainText = response.plainText ?? googleDocsPlainText
        googleDocsBriefing = response.documentBriefing ?? googleDocsBriefing
        googleDocsSnippets = response.snippets ?? googleDocsSnippets
        if let briefingError = response.briefingError, !briefingError.isEmpty {
            googleDocsMessage = "Connected, but briefing failed: \(briefingError)"
        } else {
            googleDocsMessage = response.message ?? fallbackMessage
        }
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
                applyGoogleDocSnapshot(response, fallbackMessage: "Google Doc context refreshed.")
                appendLog("Google Doc context refreshed.")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Doc refresh failed: \(error.localizedDescription)")
            }
        }
    }

    func updateGoogleDocLiveNotes(triggeredByAutoSummary: Bool) {
        guard googleDocsIsConnected else {
            googleDocsMessage = "Connect a Google Doc first."
            return
        }
        guard !googleDocsIsBusy else {
            if !triggeredByAutoSummary {
                googleDocsMessage = "Google Docs request is already running."
            }
            return
        }

        let request = googleDocMeetingNotesRequest()
        googleDocsStatus = .starting
        googleDocsMessage = triggeredByAutoSummary ? "Auto-updating live notes..." : "Updating live notes..."
        appendLog(triggeredByAutoSummary ? "Auto-updating Google Doc live notes." : "Updating Google Doc live notes.")

        Task {
            do {
                let response = try await assistantClient.updateGoogleDocLiveNotes(request)
                applyGoogleDocSnapshot(response, fallbackMessage: "Live notes updated.")
                appendLog("Google Doc live notes updated.")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Doc live notes failed: \(error.localizedDescription)")
            }
        }
    }

    func applyDocumentEditPlan(_ plan: DocumentEditPlanResponse) async throws -> GoogleDocSnapshotResponse {
        switch plan.intent {
        case "replace_text":
            let find = plan.find.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !find.isEmpty else {
                throw VoiceEditError("AI edit plan did not include find text.")
            }
            return try await assistantClient.replaceGoogleDocText(
                GoogleDocReplaceTextRequest(
                    meetingID: ensureCurrentMeetingID(),
                    find: find,
                    replace: plan.replace,
                    occurrence: plan.occurrence == "all" ? "all" : "first"
                )
            )

        case "insert_under_heading":
            let heading = plan.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = plan.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !heading.isEmpty else {
                throw VoiceEditError("AI edit plan did not include a heading.")
            }
            guard !text.isEmpty else {
                throw VoiceEditError("AI edit plan did not include text to insert.")
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
                throw VoiceEditError("AI edit plan did not include anchor text.")
            }
            guard !text.isEmpty else {
                throw VoiceEditError("AI edit plan did not include replacement text.")
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
            throw VoiceEditError("AI edit plan did not include an executable intent.")
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
            return "replace text"
        case "insert_under_heading":
            return "insert under heading"
        case "rewrite_paragraph_containing_anchor":
            return "rewrite paragraph"
        case "append_meeting_notes":
            return "append meeting notes"
        default:
            return "document edit"
        }
    }

}
