import Foundation

@MainActor
extension CaptureViewModel {
    var assistantProviderOptions: [AssistantProviderDescriptor] {
        assistantProviders.isEmpty
            ? [
                AssistantProviderDescriptor(
                    id: "codex-cli",
                    label: "Codex CLI",
                    kind: "cli_agent",
                    installed: false,
                    available: false,
                    models: ["gpt-5.5"],
                    capabilities: ["chat", "text_output"],
                    riskLevel: "low",
                    authMode: "provider_owned",
                    endpoint: "",
                    binaryPath: "",
                    notes: ["Provider discovery failed. Start the backend and install Codex CLI, then refresh."]
                )
            ]
            : assistantProviders
    }

    var assistantModelOptions: [String] {
        assistantProviderOptions
            .first(where: { $0.id == assistantProviderID })?
            .models
            .filter { !$0.isEmpty } ?? []
    }

    var assistantStatusLabel: String {
        switch assistantStatus {
        case .idle:
            return "Ready"
        case .starting:
            return "Generating"
        case .running:
            return "Ready"
        case .failed(let message):
            return message
        }
    }

    var isAssistantActionRunning: Bool {
        activeAssistantAction != nil
    }

    var isWhatShouldISayLoading: Bool {
        activeAssistantAction == .whatShouldISay
    }

    var isFollowUpQuestionsLoading: Bool {
        activeAssistantAction == .followUpQuestions
    }

    var autoSummaryProgress: Double {
        guard autoSummaryIntervalSeconds > 0 else {
            return 0
        }

        let elapsedSeconds = autoSummaryIntervalSeconds - autoSummaryRemainingSeconds
        return min(max(Double(elapsedSeconds) / Double(autoSummaryIntervalSeconds), 0), 1)
    }

    func prepareWhatShouldISay() {
        runAssistant(.whatShouldISay)
    }

    func prepareFollowUpQuestions() {
        runAssistant(.followUpQuestions)
    }

    func refreshAssistantProviders() {
        assistantStatus = .starting
        appendLog("Loading assistant providers...")

        Task {
            do {
                let response = try await assistantClient.fetchProviders()
                assistantProviders = response.providers
                assistantProviderID = response.defaults.provider
                assistantModel = response.defaults.model
                assistantThinking = response.defaults.thinking
                assistantStatus = .idle
                assistantModeLabel = "Ready"
                appendLog("Assistant providers loaded: \(response.providers.count).")
            } catch {
                assistantStatus = .failed(error.localizedDescription)
                appendLog("Assistant provider load failed: \(error.localizedDescription)")
            }
        }
    }

    func selectAssistantProvider(_ providerID: String) {
        assistantProviderID = providerID
        if let firstModel = assistantProviderOptions.first(where: { $0.id == providerID })?.models.first,
           !firstModel.isEmpty {
            assistantModel = firstModel
        }
    }

    func updateAssistantModel(_ model: String) {
        assistantModel = model
    }

    func updateAssistantThinking(_ thinking: String) {
        assistantThinking = thinking
    }

    func runAssistant(_ quickAction: AssistantQuickAction) {
        guard activeAssistantAction == nil else {
            appendLog("Assistant request ignored because another quick action is still running.")
            return
        }

        activeAssistantAction = quickAction
        assistantRequestGeneration += 1
        let requestGeneration = assistantRequestGeneration
        assistantStatus = .starting
        assistantModeLabel = "\(quickAction.label) · \(assistantProviderID)"
        appendLog("Requesting assistant response: \(quickAction.label).")

        let request = AssistantRespondRequest(
            action: quickAction.requestAction,
            meetingID: currentMeetingID,
            provider: assistantProviderID,
            model: assistantModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "gpt-5.5"
                : assistantModel,
            thinking: assistantThinking,
            transcript: assistantTranscriptPayload(),
            rollingSummary: "",
            previousNotes: [],
            previousActions: [],
            documentTitle: googleDocsConnectedTitle,
            documentSummary: googleDocsPreview,
            documentSnippets: googleDocsSnippets,
            documentBriefing: googleDocsBriefing
        )

        Task {
            do {
                let response = try await assistantClient.respond(request)
                if requestGeneration == assistantRequestGeneration {
                    applyAssistantResponse(response, label: quickAction.label)
                }
            } catch {
                if requestGeneration == assistantRequestGeneration {
                    assistantStatus = .failed(error.localizedDescription)
                    assistantModeLabel = "AI error"
                    appendLog("Assistant response failed: \(error.localizedDescription)")
                }
            }

            if requestGeneration == assistantRequestGeneration {
                activeAssistantAction = nil
            }
        }
    }

    func applyAssistantResponse(_ response: AssistantRespondResponse, label: String) {
        assistantStatus = .running
        assistantModeLabel = "\(label) · \(response.provider) · \(response.model) · \(response.latencyMs) ms"
        assistantProviderID = response.provider
        assistantModel = response.model
        assistantThinking = response.thinking

        assistantDrafts = response.drafts.map {
            AssistantDraft(
                title: $0.title,
                detail: $0.detail,
                badge: $0.badge,
                iconName: $0.iconName
            )
        }

        appendLog("Assistant response ready: \(response.provider) \(response.model) \(response.latencyMs)ms.")
    }

    func assistantTranscriptPayload(finalOnly: Bool = false) -> [AssistantTranscriptLinePayload] {
        let sourceLines = finalOnly ? finalTranscriptArchive : transcriptLines
        return sourceLines.suffix(16).map {
            AssistantTranscriptLinePayload(
                source: $0.source,
                sourceLabel: $0.sourceLabel,
                speakerHint: $0.speakerHint,
                speakerID: $0.speakerID,
                speakerLabel: $0.speakerLabel,
                startMs: $0.startMs,
                endMs: $0.endMs,
                text: $0.text,
                isFinal: $0.isFinal
            )
        }
    }

    func assistantTranscriptPayload(lines: [TranscriptLine]) -> [AssistantTranscriptLinePayload] {
        lines.map {
            AssistantTranscriptLinePayload(
                source: $0.source,
                sourceLabel: $0.sourceLabel,
                speakerHint: $0.speakerHint,
                speakerID: $0.speakerID,
                speakerLabel: $0.speakerLabel,
                startMs: $0.startMs,
                endMs: $0.endMs,
                text: $0.text,
                isFinal: $0.isFinal
            )
        }
    }

    func startAutoSummaryCountdown() {
        autoSummaryTask?.cancel()
        autoSummaryRequestGeneration += 1
        autoSummaryRemainingSeconds = autoSummaryIntervalSeconds
        autoSummaryStatusLabel = "Next summary in \(autoSummaryIntervalSeconds)s"
        autoSummaryIsGenerating = false

        autoSummaryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else {
                    break
                }
                guard let self else {
                    break
                }
                self.tickAutoSummaryCountdown()
            }
        }
    }

    func stopAutoSummaryCountdown() {
        autoSummaryTask?.cancel()
        autoSummaryTask = nil
        autoSummaryRequestGeneration += 1
        autoSummaryIsGenerating = false
        autoSummaryRemainingSeconds = autoSummaryIntervalSeconds
        autoSummaryStatusLabel = "Start Meeting to begin"
    }

    func tickAutoSummaryCountdown() {
        guard transcriptionStatus == .starting || transcriptionStatus == .running else {
            autoSummaryRemainingSeconds = autoSummaryIntervalSeconds
            autoSummaryStatusLabel = "Waiting for STT"
            return
        }

        guard !autoSummaryIsGenerating else {
            return
        }

        if autoSummaryRemainingSeconds > 1 {
            autoSummaryRemainingSeconds -= 1
            autoSummaryStatusLabel = "Next summary in \(autoSummaryRemainingSeconds)s"
            return
        }

        autoSummaryRemainingSeconds = 0
        runAutomaticMeetingSummary()
    }

    func runAutomaticMeetingSummary() {
        guard !autoSummaryIsGenerating else {
            return
        }

        let newFinalLines = finalTranscriptArchive.filter { !summarizedFinalLineIDs.contains($0.id) }
        let transcript = assistantTranscriptPayload(lines: newFinalLines)
        guard !transcript.isEmpty else {
            resetAutoSummaryCountdown(status: "Waiting for final transcript")
            return
        }
        let lineIDsToMark = Set(newFinalLines.map(\.id))

        autoSummaryIsGenerating = true
        autoSummaryStatusLabel = "Summarizing now"
        appendLog("Auto summarizing meeting notes and next actions...")
        autoSummaryRequestGeneration += 1
        let requestGeneration = autoSummaryRequestGeneration

        let request = AssistantRespondRequest(
            action: "meeting_notes",
            meetingID: currentMeetingID,
            provider: assistantProviderID,
            model: assistantModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "gpt-5.5"
                : assistantModel,
            thinking: assistantThinking,
            transcript: transcript,
            rollingSummary: rollingSummaryContext(),
            previousNotes: previousNoteContextPayload(),
            previousActions: previousActionContextPayload(),
            documentTitle: googleDocsConnectedTitle,
            documentSummary: googleDocsPreview,
            documentSnippets: googleDocsSnippets,
            documentBriefing: googleDocsBriefing
        )

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            guard self.autoSummaryRequestGeneration == requestGeneration else {
                return
            }

            do {
                let response = try await self.assistantClient.respond(request)
                guard self.autoSummaryRequestGeneration == requestGeneration else {
                    return
                }
                self.applyAutomaticSummaryResponse(response)
                self.summarizedFinalLineIDs.formUnion(lineIDsToMark)
                self.resetAutoSummaryCountdown(status: "Updated \(self.shortTimeLabel())")
            } catch {
                guard self.autoSummaryRequestGeneration == requestGeneration else {
                    return
                }
                self.autoSummaryStatusLabel = "Summary failed"
                self.appendLog("Auto summary failed: \(error.localizedDescription)")
                self.resetAutoSummaryCountdown(status: "Retry in \(self.autoSummaryIntervalSeconds)s")
            }

            self.autoSummaryIsGenerating = false
        }
    }

    func applyAutomaticSummaryResponse(_ response: AssistantRespondResponse) {
        if !response.notes.isEmpty {
            noteDrafts = response.notes.map {
                MeetingNoteDraft(title: $0.title, detail: $0.detail)
            }
        }

        if !response.actions.isEmpty {
            actionDrafts = response.actions.map {
                MeetingActionDraft(title: $0.title, owner: $0.owner, state: $0.state)
            }
        }

        appendLog("Auto summary ready: \(response.provider) \(response.model) \(response.latencyMs)ms.")

        if googleDocsIsConnected {
            updateGoogleDocLiveNotes(triggeredByAutoSummary: true)
        }
    }

    func resetAutoSummaryCountdown(status: String) {
        autoSummaryRemainingSeconds = autoSummaryIntervalSeconds
        autoSummaryStatusLabel = status
    }

    func resetMeetingDrafts() {
        noteDrafts = []
        actionDrafts = []
    }

    func rollingSummaryContext() -> String {
        var lines: [String] = []
        if !noteDrafts.isEmpty {
            lines.append("Current notes:")
            for note in noteDrafts {
                lines.append("- \(note.title): \(note.detail)")
            }
        }

        if !actionDrafts.isEmpty {
            lines.append("Current actions:")
            for action in actionDrafts {
                lines.append("- \(action.title) / owner=\(action.owner) / state=\(action.state)")
            }
        }

        return lines.joined(separator: "\n")
    }

    func previousNoteContextPayload() -> [MeetingNoteContextPayload] {
        noteDrafts.map { MeetingNoteContextPayload(title: $0.title, detail: $0.detail) }
    }

    func previousActionContextPayload() -> [MeetingActionContextPayload] {
        actionDrafts.map {
            MeetingActionContextPayload(title: $0.title, owner: $0.owner, state: $0.state)
        }
    }

    func resetAssistantDrafts() {
        assistantRequestGeneration += 1
        activeAssistantAction = nil
        assistantModeLabel = "Ready"
        assistantStatus = .idle
        assistantDrafts = []
    }

    func latestTranscriptText() -> String {
        guard let text = transcriptLines.last(where: { $0.isFinal })?.text ?? transcriptLines.last?.text else {
            return "對方剛剛提出的重點"
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "對方剛剛提出的重點"
        }

        return trimmed.count > 24 ? "\(trimmed.prefix(24))..." : trimmed
    }

}
