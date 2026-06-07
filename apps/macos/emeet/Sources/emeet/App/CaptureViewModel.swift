import AppKit
import Combine
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var microphoneStatus: CaptureStatus = .idle
    @Published private(set) var systemAudioStatus: CaptureStatus = .idle
    @Published private(set) var microphoneLevel: AudioLevel = .silent
    @Published private(set) var systemAudioLevel: AudioLevel = .silent
    @Published private(set) var microphoneHistory: [Float] = Array(repeating: 0, count: 96)
    @Published private(set) var systemAudioHistory: [Float] = Array(repeating: 0, count: 96)
    @Published private(set) var transcriptionStatus: CaptureStatus = .idle
    @Published private(set) var transcriptLines: [TranscriptLine] = []
    @Published private(set) var transcriptionEndpointLabel: String
    @Published private(set) var transcriptionSettingsIsPresented = false
    @Published private(set) var transcriptionOptionsStatus: CaptureStatus = .idle
    @Published private(set) var transcriptionOptionsMessage = "Checking local STT runtime..."
    @Published private(set) var transcriptionHardwareLabel = "Unknown Mac"
    @Published private(set) var transcriptionProviders: [TranscriptionProviderDescriptor] = []
    @Published private(set) var transcriptionLanguages: [TranscriptionLanguageOption] = []
    @Published private(set) var transcriptionProviderID = "mlx-whisper"
    @Published private(set) var transcriptionModel = "breeze-asr-25"
    @Published private(set) var transcriptionLanguage = "zh"
    @Published private(set) var microphoneBackendLatencyMs: Int?
    @Published private(set) var systemBackendLatencyMs: Int?
    @Published private(set) var microphoneTranscriptionLatencyMs: Int?
    @Published private(set) var systemTranscriptionLatencyMs: Int?
    @Published private(set) var assistantModeLabel = "Ready"
    @Published private(set) var assistantStatus: CaptureStatus = .idle
    @Published private(set) var assistantProviders: [AssistantProviderDescriptor] = []
    @Published private(set) var assistantProviderID = "codex-cli"
    @Published private(set) var assistantModel = "gpt-5.5"
    @Published private(set) var assistantThinking = AssistantThinking.medium.rawValue
    @Published private(set) var assistantDrafts: [AssistantDraft] = []
    @Published private(set) var activeAssistantAction: AssistantQuickAction?
    @Published private(set) var noteDrafts: [MeetingNoteDraft] = []
    @Published private(set) var actionDrafts: [MeetingActionDraft] = []
    @Published private(set) var autoSummaryRemainingSeconds = 30
    @Published private(set) var autoSummaryStatusLabel = "Start Meeting to begin"
    @Published private(set) var autoSummaryIsGenerating = false
    @Published private(set) var googleDocsURL = ""
    @Published private(set) var googleDocsStatus: CaptureStatus = .idle
    @Published private(set) var googleDocsAuthReady = false
    @Published private(set) var googleDocsClientConfigured = false
    @Published private(set) var googleDocsDependenciesAvailable = false
    @Published private(set) var googleDocsConnectedTitle = ""
    @Published private(set) var googleDocsDocumentID = ""
    @Published private(set) var googleDocsRevisionID = ""
    @Published private(set) var googleDocsPreview = ""
    @Published private(set) var googleDocsPlainText = ""
    @Published private(set) var googleDocsBriefing = ""
    @Published private(set) var googleDocsSnippets: [String] = []
    @Published private(set) var googleDocsMessage = "Google Docs not connected."
    @Published private(set) var googleBrowserMessage = "Browser helper optional."
    @Published private(set) var googleBrowserSeleniumAvailable = false
    @Published private(set) var googleBrowserChromeDriverAvailable = false
    @Published private(set) var googleBrowserSessionActive = false
    @Published private(set) var googleBrowserFindText = ""
    @Published private(set) var meetingHistoryIsPresented = false
    @Published private(set) var meetingHistoryStatus: CaptureStatus = .idle
    @Published private(set) var meetingHistoryMessage = "Open saved meetings from the backend."
    @Published private(set) var meetingHistory: [MeetingHistorySummary] = []
    @Published private(set) var selectedMeetingHistoryID = ""
    @Published private(set) var selectedMeetingRecord: MeetingHistoryRecordResponse?
    @Published private(set) var eventLog: [String] = [
        "Ready. Start Meeting begins capture, STT, and auto summaries."
    ]

    private let microphoneService = MicrophoneCaptureService()
    private let systemAudioService = SystemAudioCaptureService()
    private let transcriptionBackend: TranscriptionBackendConfig
    private let microphoneTranscriptionClient: TranscriptionWebSocketClient
    private let systemTranscriptionClient: TranscriptionWebSocketClient
    private let assistantClient: AssistantAPIClient
    private let maxHistoryCount = 96
    private let maxTranscriptLineCount = 24
    private let maxFinalTranscriptArchiveCount = 3_000
    private let autoSummaryIntervalSeconds = 30
    private let documentEditIntervalSeconds = 10
    private var autoSummaryTask: Task<Void, Never>?
    private var documentEditTask: Task<Void, Never>?
    private var autoSummaryRequestGeneration = 0
    private var documentEditRequestGeneration = 0
    private var assistantRequestGeneration = 0
    private var meetingHistoryRequestGeneration = 0
    private var didRequestScreenRecordingPermission = false
    private var currentMeetingID = ""
    private var shouldCreateNewMeetingOnNextStart = false
    private var shouldPreserveLoadedMeetingOnNextStart = false
    private var finalTranscriptArchive: [TranscriptLine] = []
    private var summarizedFinalLineIDs = Set<String>()
    private var documentEditCheckedFinalLineIDs = Set<String>()
    private var appliedDocumentEditKeys = Set<String>()
    private var documentEditIsPlanning = false

    init(transcriptionBackend: TranscriptionBackendConfig = .fromEnvironment()) {
        self.transcriptionBackend = transcriptionBackend
        transcriptionEndpointLabel = transcriptionBackend.displayAddress
        assistantClient = AssistantAPIClient(baseURL: transcriptionBackend.httpBaseURL)
        microphoneTranscriptionClient = TranscriptionWebSocketClient(
            url: transcriptionBackend.websocketURL,
            source: "microphone"
        )
        systemTranscriptionClient = TranscriptionWebSocketClient(
            url: transcriptionBackend.websocketURL,
            source: "system"
        )

        microphoneService.onLevel = { [weak self] level in
            Task { @MainActor in
                self?.update(level, for: .microphone)
            }
        }

        microphoneService.onAudioChunk = { [weak self] data in
            self?.microphoneTranscriptionClient.sendAudio(data)
        }

        microphoneService.onError = { [weak self] message in
            Task { @MainActor in
                self?.microphoneStatus = .failed(message)
                self?.appendLog("Microphone error: \(message)")
            }
        }

        systemAudioService.onLevel = { [weak self] level in
            Task { @MainActor in
                self?.update(level, for: .systemAudio)
            }
        }

        systemAudioService.onAudioChunk = { [weak self] data in
            self?.systemTranscriptionClient.sendAudio(data)
        }

        systemAudioService.onError = { [weak self] message in
            Task { @MainActor in
                self?.systemAudioStatus = .failed(message)
                self?.appendLog("System audio error: \(message)")
            }
        }

        configureTranscriptionClient(
            microphoneTranscriptionClient,
            source: .microphone,
            label: "Microphone"
        )
        configureTranscriptionClient(
            systemTranscriptionClient,
            source: .systemAudio,
            label: "System audio"
        )

        refreshAssistantProviders()
        refreshTranscriptionOptions()
        refreshGoogleAuthStatus()
    }

    var isAnyRunning: Bool {
        microphoneStatus == .running || systemAudioStatus == .running
    }

    var isMeetingActive: Bool {
        transcriptionStatus == .starting
            || transcriptionStatus == .running
            || microphoneStatus == .starting
            || microphoneStatus == .running
            || systemAudioStatus == .starting
            || systemAudioStatus == .running
    }

    var transcriptCountsLabel: String {
        let finalCount = transcriptLines.filter(\.isFinal).count
        let partialCount = transcriptLines.count - finalCount
        return "\(finalCount) final / \(partialCount) live"
    }

    var backendLatencyLabel: String {
        formatLatency(averageLatency([microphoneBackendLatencyMs, systemBackendLatencyMs]))
    }

    var transcriptionLatencyLabel: String {
        formatLatency(averageLatency([microphoneTranscriptionLatencyMs, systemTranscriptionLatencyMs]))
    }

    var transcriptionStatusDetailLabel: String? {
        guard transcriptionStatus == .running else {
            return nil
        }

        if let latencyMs = averageLatency([microphoneBackendLatencyMs, systemBackendLatencyMs]) {
            return "\(latencyMs) ms"
        }

        return "Connected"
    }

    var transcriptionProviderOptions: [TranscriptionProviderDescriptor] {
        transcriptionProviders.isEmpty
            ? [
                TranscriptionProviderDescriptor(
                    id: "mlx-whisper",
                    label: "MLX Whisper",
                    installed: false,
                    available: false,
                    recommended: true,
                    notes: ["Backend STT options are not loaded yet."],
                    models: []
                )
            ]
            : transcriptionProviders
    }

    var transcriptionModelOptions: [TranscriptionModelDescriptor] {
        transcriptionProviderOptions
            .first(where: { $0.id == transcriptionProviderID })?
            .models
            .filter(\.available) ?? []
    }

    var transcriptionLanguageOptions: [TranscriptionLanguageOption] {
        transcriptionLanguages.isEmpty
            ? [
                TranscriptionLanguageOption(id: "auto", label: "Auto detect", notes: "Use model language detection."),
                TranscriptionLanguageOption(id: "zh", label: "Chinese / Mandarin", notes: "Recommended for Taiwan Mandarin meetings."),
                TranscriptionLanguageOption(id: "en", label: "English", notes: "Force English transcription."),
            ]
            : transcriptionLanguages
    }

    var transcriptionSettingsSummary: String {
        let languageLabel = transcriptionLanguageOptions.first(where: { $0.id == transcriptionLanguage })?.label
            ?? transcriptionLanguage
        return "\(transcriptionProviderID) / \(transcriptionModel) / \(languageLabel)"
    }

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

    var autoSummaryProgress: Double {
        guard autoSummaryIntervalSeconds > 0 else {
            return 0
        }

        let elapsedSeconds = autoSummaryIntervalSeconds - autoSummaryRemainingSeconds
        return min(max(Double(elapsedSeconds) / Double(autoSummaryIntervalSeconds), 0), 1)
    }

    var meetingHistoryIsLoading: Bool {
        meetingHistoryStatus == .starting
    }

    func startAll() {
        connectTranscription()
    }

    func toggleMeeting() {
        if isMeetingActive {
            stopAll()
        } else {
            startAll()
        }
    }

    func requestScreenRecordingPermissionOnLaunch() {
        guard !didRequestScreenRecordingPermission else {
            return
        }

        didRequestScreenRecordingPermission = true
        guard !CGPreflightScreenCaptureAccess() else {
            appendLog("Screen Recording permission is available.")
            return
        }

        appendLog("Requesting Screen Recording permission...")
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            appendLog("Screen Recording permission granted.")
        } else {
            systemAudioStatus = .failed("螢幕錄製權限尚未授權。授權後通常需要重新啟動 App。")
            appendLog("Screen Recording permission is not granted yet.")
        }
    }

    func openTranscriptionSettings() {
        transcriptionSettingsIsPresented = true
        refreshTranscriptionOptions()
    }

    func closeTranscriptionSettings() {
        transcriptionSettingsIsPresented = false
    }

    func refreshTranscriptionOptions() {
        transcriptionOptionsStatus = .starting
        transcriptionOptionsMessage = "Checking local STT runtime..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let response = try await self.assistantClient.fetchTranscriptionOptions()
                self.applyTranscriptionOptions(response)
                self.transcriptionOptionsStatus = .running
                self.transcriptionOptionsMessage = "STT runtime ready"
                self.appendLog("STT options loaded for \(response.hardware.cpu).")
            } catch {
                self.transcriptionOptionsStatus = .failed(error.localizedDescription)
                self.transcriptionOptionsMessage = error.localizedDescription
                self.appendLog("STT options failed: \(error.localizedDescription)")
            }
        }
    }

    func selectTranscriptionProvider(_ providerID: String) {
        transcriptionProviderID = providerID
        if let model = transcriptionProviderOptions
            .first(where: { $0.id == providerID })?
            .models
            .first(where: { $0.available && $0.recommended })
            ?? transcriptionProviderOptions
                .first(where: { $0.id == providerID })?
                .models
                .first(where: \.available) {
            transcriptionModel = model.id
            if model.languageHint != "auto" {
                transcriptionLanguage = model.languageHint
            }
        }
    }

    func updateTranscriptionModel(_ modelID: String) {
        transcriptionModel = modelID
        if let model = transcriptionModelOptions.first(where: { $0.id == modelID }),
           model.languageHint != "auto" {
            transcriptionLanguage = model.languageHint
        }
    }

    func updateTranscriptionLanguage(_ languageID: String) {
        transcriptionLanguage = languageID
    }

    func stopAll() {
        stopMicrophone()
        stopSystemAudio()
        disconnectTranscription()
    }

    func startMicrophone() {
        microphoneStatus = .starting
        appendLog("Starting microphone capture...")

        Task {
            do {
                try await microphoneService.start()
                microphoneStatus = .running
                appendLog("Microphone capture is running.")
            } catch {
                microphoneStatus = .failed(error.localizedDescription)
                appendLog("Microphone failed: \(error.localizedDescription)")
            }
        }
    }

    func toggleMicrophone() {
        if microphoneStatus == .running || microphoneStatus == .starting {
            stopMicrophone()
        } else {
            startMicrophone()
        }
    }

    func stopMicrophone() {
        microphoneService.stop()
        microphoneStatus = .idle
        appendLog("Microphone capture stopped.")
    }

    func startSystemAudio() {
        systemAudioStatus = .starting
        appendLog("Starting ScreenCaptureKit system audio...")

        Task {
            do {
                try await systemAudioService.start()
                systemAudioStatus = .running
                appendLog("System audio capture is running. Play audio from another app to test it.")
            } catch {
                systemAudioStatus = .failed(error.localizedDescription)
                appendLog("System audio failed: \(error.localizedDescription)")
            }
        }
    }

    func toggleSystemAudio() {
        if systemAudioStatus == .running || systemAudioStatus == .starting {
            stopSystemAudio()
        } else {
            startSystemAudio()
        }
    }

    func stopSystemAudio() {
        Task {
            await systemAudioService.stop()
            systemAudioStatus = .idle
            appendLog("System audio capture stopped.")
        }
    }

    func connectTranscription() {
        guard transcriptionStatus != .starting && transcriptionStatus != .running else {
            return
        }

        transcriptionStatus = .starting
        if shouldCreateNewMeetingOnNextStart {
            currentMeetingID = ""
            shouldCreateNewMeetingOnNextStart = false
        }
        let preserveLoadedMeeting = shouldPreserveLoadedMeetingOnNextStart
        shouldPreserveLoadedMeetingOnNextStart = false
        _ = ensureCurrentMeetingID()
        if preserveLoadedMeeting {
            summarizedFinalLineIDs = Set(finalTranscriptArchive.map(\.id))
            documentEditCheckedFinalLineIDs = Set(finalTranscriptArchive.map(\.id))
            appliedDocumentEditKeys.removeAll()
        } else {
            transcriptLines.removeAll()
            finalTranscriptArchive.removeAll()
            summarizedFinalLineIDs.removeAll()
            documentEditCheckedFinalLineIDs.removeAll()
            appliedDocumentEditKeys.removeAll()
            resetMeetingDrafts()
            resetAssistantDrafts()
        }
        resetLatencyReadings()
        appendLog("Connecting transcription backend at \(transcriptionBackend.displayAddress) for \(currentMeetingID)...")
        microphoneTranscriptionClient.connect(
            meetingID: currentMeetingID,
            sttProvider: transcriptionProviderID,
            sttModel: transcriptionModel,
            sttLanguage: transcriptionLanguage
        )
        systemTranscriptionClient.connect(
            meetingID: currentMeetingID,
            sttProvider: transcriptionProviderID,
            sttModel: transcriptionModel,
            sttLanguage: transcriptionLanguage
        )
        startAutoSummaryCountdown()
        startDocumentEditWatcher()

        if microphoneStatus != .running && microphoneStatus != .starting {
            startMicrophone()
        }

        if systemAudioStatus != .running && systemAudioStatus != .starting {
            startSystemAudio()
        }
    }

    func disconnectTranscription() {
        let endedMeetingID = currentMeetingID
        microphoneTranscriptionClient.disconnect()
        systemTranscriptionClient.disconnect()
        transcriptionStatus = .idle
        resetLatencyReadings()
        stopAutoSummaryCountdown()
        stopDocumentEditWatcher()
        shouldCreateNewMeetingOnNextStart = !currentMeetingID.isEmpty
        appendLog("Transcription backend disconnected.")
        requestGeneratedMeetingTitle(meetingID: endedMeetingID)
    }

    func startNewMeeting() {
        if isMeetingActive {
            stopAll()
        }

        autoSummaryRequestGeneration += 1
        documentEditRequestGeneration += 1
        autoSummaryIsGenerating = false
        documentEditIsPlanning = false
        currentMeetingID = ""
        shouldCreateNewMeetingOnNextStart = false
        shouldPreserveLoadedMeetingOnNextStart = false
        transcriptLines.removeAll()
        finalTranscriptArchive.removeAll()
        summarizedFinalLineIDs.removeAll()
        documentEditCheckedFinalLineIDs.removeAll()
        appliedDocumentEditKeys.removeAll()
        resetLatencyReadings()
        resetMeetingDrafts()
        resetAssistantDrafts()

        if transcriptionStatus == .starting || transcriptionStatus == .running {
            resetAutoSummaryCountdown(status: "Records cleared")
        } else {
            autoSummaryRemainingSeconds = autoSummaryIntervalSeconds
            autoSummaryStatusLabel = "Start Meeting to begin"
        }

        appendLog("New meeting ready.")
    }

    func exportMeetingRecords() {
        let panel = NSSavePanel()
        panel.title = "Export Meeting Record"
        panel.nameFieldStringValue = "meeting-record-\(fileTimestamp()).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
            appendLog("Meeting record exported: \(url.lastPathComponent)")
        } catch {
            appendLog("Export failed: \(error.localizedDescription)")
        }
    }

    func openMeetingHistory() {
        meetingHistoryIsPresented = true
        refreshMeetingHistory()
    }

    func closeMeetingHistory() {
        meetingHistoryIsPresented = false
    }

    func refreshMeetingHistory() {
        meetingHistoryRequestGeneration += 1
        let requestGeneration = meetingHistoryRequestGeneration
        meetingHistoryStatus = .starting
        meetingHistoryMessage = "Loading saved meetings..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let response = try await self.assistantClient.fetchMeetingHistory()
                guard self.meetingHistoryRequestGeneration == requestGeneration else {
                    return
                }

                self.meetingHistory = response.meetings
                if response.meetings.isEmpty {
                    self.selectedMeetingHistoryID = ""
                    self.selectedMeetingRecord = nil
                    self.meetingHistoryStatus = .idle
                    self.meetingHistoryMessage = "No saved meetings yet."
                    return
                }

                self.meetingHistoryMessage = "\(response.meetings.count) saved meetings"
                let selected = response.meetings.first { $0.meetingId == self.selectedMeetingHistoryID }
                    ?? response.meetings.first
                if let selected {
                    self.selectMeetingHistory(selected)
                } else {
                    self.meetingHistoryStatus = .running
                }
            } catch {
                guard self.meetingHistoryRequestGeneration == requestGeneration else {
                    return
                }

                self.meetingHistoryStatus = .failed(error.localizedDescription)
                self.meetingHistoryMessage = error.localizedDescription
            }
        }
    }

    func selectMeetingHistory(_ meeting: MeetingHistorySummary) {
        selectedMeetingHistoryID = meeting.meetingId
        selectedMeetingRecord = nil
        loadMeetingRecord(meetingID: meeting.meetingId)
    }

    func continueMeetingFromHistory(_ record: MeetingHistoryRecordResponse) {
        let wasActive = isMeetingActive
        if isMeetingActive {
            stopAll()
        }

        currentMeetingID = record.meeting.meetingId
        shouldCreateNewMeetingOnNextStart = false
        shouldPreserveLoadedMeetingOnNextStart = true
        let loadedLines = record.transcript.map(Self.transcriptLine(from:))
        finalTranscriptArchive = loadedLines
        transcriptLines = Array(loadedLines.suffix(maxTranscriptLineCount))
        summarizedFinalLineIDs = Set(loadedLines.map(\.id))
        documentEditCheckedFinalLineIDs = Set(loadedLines.map(\.id))
        appliedDocumentEditKeys.removeAll()
        noteDrafts = record.notes.map { MeetingNoteDraft(title: $0.title, detail: $0.detail) }
        actionDrafts = record.actions.map {
            MeetingActionDraft(title: $0.title, owner: $0.owner, state: $0.state)
        }
        assistantDrafts = record.assistantResponses.first?.suggestions.map {
            AssistantDraft(title: $0.title, detail: $0.detail, badge: $0.badge, iconName: $0.iconName)
        } ?? []
        resetLatencyReadings()
        meetingHistoryIsPresented = false
        autoSummaryStatusLabel = "Continuing saved meeting"
        appendLog("Continuing meeting: \(record.meeting.title).")
        if wasActive {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                self?.connectTranscription()
            }
        } else {
            connectTranscription()
        }
    }

    func renameSelectedMeeting(to title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedMeetingHistoryID.isEmpty else {
            meetingHistoryMessage = "Select a meeting first."
            return
        }
        guard !trimmedTitle.isEmpty else {
            meetingHistoryMessage = "Meeting title cannot be empty."
            return
        }

        let meetingID = selectedMeetingHistoryID
        meetingHistoryStatus = .starting
        meetingHistoryMessage = "Renaming meeting..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let response = try await self.assistantClient.renameMeeting(meetingID: meetingID, title: trimmedTitle)
                self.applyUpdatedMeetingSummary(response.meeting)
                self.meetingHistoryStatus = .running
                self.meetingHistoryMessage = "Meeting renamed"
                self.appendLog("Meeting renamed: \(response.meeting.title).")
            } catch {
                self.meetingHistoryStatus = .failed(error.localizedDescription)
                self.meetingHistoryMessage = error.localizedDescription
                self.appendLog("Meeting rename failed: \(error.localizedDescription)")
            }
        }
    }

    func exportSelectedMeetingRecord(_ record: MeetingHistoryRecordResponse) {
        let panel = NSSavePanel()
        panel.title = "Export Saved Meeting"
        panel.nameFieldStringValue = "\(safeFilename(record.meeting.title))-\(fileTimestamp()).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        meetingHistoryStatus = .starting
        meetingHistoryMessage = "Exporting saved meeting..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let markdown = try await self.assistantClient.exportMeetingMarkdown(meetingID: record.meeting.meetingId)
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                self.meetingHistoryStatus = .running
                self.meetingHistoryMessage = "Meeting exported"
                self.appendLog("Saved meeting exported: \(url.lastPathComponent)")
            } catch {
                self.meetingHistoryStatus = .failed(error.localizedDescription)
                self.meetingHistoryMessage = error.localizedDescription
                self.appendLog("Saved meeting export failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadMeetingRecord(meetingID: String) {
        meetingHistoryRequestGeneration += 1
        let requestGeneration = meetingHistoryRequestGeneration
        meetingHistoryStatus = .starting
        meetingHistoryMessage = "Loading meeting record..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let record = try await self.assistantClient.fetchMeetingRecord(meetingID: meetingID)
                guard self.meetingHistoryRequestGeneration == requestGeneration,
                      self.selectedMeetingHistoryID == meetingID else {
                    return
                }

                self.selectedMeetingRecord = record
                self.meetingHistoryStatus = .running
                self.meetingHistoryMessage = "Meeting loaded"
            } catch {
                guard self.meetingHistoryRequestGeneration == requestGeneration else {
                    return
                }

                self.meetingHistoryStatus = .failed(error.localizedDescription)
                self.meetingHistoryMessage = error.localizedDescription
            }
        }
    }

    private func requestGeneratedMeetingTitle(meetingID: String) {
        guard !meetingID.isEmpty else {
            return
        }

        let request = MeetingGenerateTitleRequest(
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

            try? await Task.sleep(nanoseconds: 700_000_000)

            do {
                let response = try await self.assistantClient.generateMeetingTitle(
                    meetingID: meetingID,
                    request: request
                )
                self.applyUpdatedMeetingSummary(response.meeting)
                if response.generated {
                    self.appendLog("AI generated meeting title: \(response.meeting.title).")
                }
            } catch {
                self.appendLog("AI meeting title generation failed: \(error.localizedDescription)")
            }
        }
    }

    private func applyUpdatedMeetingSummary(_ meeting: MeetingHistorySummary) {
        if let index = meetingHistory.firstIndex(where: { $0.meetingId == meeting.meetingId }) {
            meetingHistory[index] = meeting
        }

        if let record = selectedMeetingRecord, record.meeting.meetingId == meeting.meetingId {
            selectedMeetingRecord = MeetingHistoryRecordResponse(
                meeting: meeting,
                transcript: record.transcript,
                assistantResponses: record.assistantResponses,
                notes: record.notes,
                actions: record.actions
            )
        }
    }

    private func applyTranscriptionOptions(_ response: TranscriptionOptionsResponse) {
        transcriptionProviders = response.providers
        transcriptionLanguages = response.languages
        transcriptionHardwareLabel = "\(response.hardware.cpu) / \(String(format: "%.1f", response.hardware.memoryGb)) GB RAM"

        let currentProvider = response.providers.first { $0.id == transcriptionProviderID && $0.available }
        let defaultProvider = response.providers.first { $0.id == response.defaults.provider && $0.available }
        let recommendedProvider = response.providers.first { $0.available && $0.recommended }
        let fallbackProvider = response.providers.first { $0.available }
        let provider = currentProvider ?? defaultProvider ?? recommendedProvider ?? fallbackProvider

        if let provider {
            transcriptionProviderID = provider.id
            let currentModel = provider.models.first { $0.id == transcriptionModel && $0.available }
            let defaultModel = provider.models.first { $0.id == response.defaults.model && $0.available }
            let recommendedModel = provider.models.first { $0.available && $0.recommended }
            let fallbackModel = provider.models.first { $0.available }

            if let model = currentModel ?? defaultModel ?? recommendedModel ?? fallbackModel {
                transcriptionModel = model.id
                if model.languageHint != "auto" {
                    transcriptionLanguage = model.languageHint
                }
            }
        }

        let languageIDs = Set(response.languages.map(\.id))
        if languageIDs.contains(response.defaults.language), transcriptionLanguage.isEmpty {
            transcriptionLanguage = response.defaults.language
        }
        if !languageIDs.contains(transcriptionLanguage) {
            transcriptionLanguage = languageIDs.contains("auto") ? "auto" : response.languages.first?.id ?? "auto"
        }
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

    func openMicrophoneSettings() {
        openSystemSettings(path: "com.apple.preference.security?Privacy_Microphone")
    }

    func openScreenRecordingSettings() {
        openSystemSettings(path: "com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func update(_ level: AudioLevel, for source: CaptureSource) {
        switch source {
        case .microphone:
            microphoneLevel = level
            microphoneHistory.append(level.rms)
            microphoneHistory = Array(microphoneHistory.suffix(maxHistoryCount))
        case .systemAudio:
            systemAudioLevel = level
            systemAudioHistory.append(level.rms)
            systemAudioHistory = Array(systemAudioHistory.suffix(maxHistoryCount))
        }
    }

    private func handleTranscriptionEvent(_ event: TranscriptEvent) {
        if let provider = event.provider, !provider.isEmpty, event.type == "session.status" {
            transcriptionStatus = .running
            appendLog("Transcription backend ready: \(provider).")
            return
        }

        if event.type == "session.error" {
            let message = event.message ?? "Unknown backend error."
            transcriptionStatus = .failed(message)
            appendLog("Transcription backend error: \(message)")
            return
        }

        guard event.type == "transcript.partial" || event.type == "transcript.final",
              let text = event.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        transcriptionStatus = .running

        let line = TranscriptLine(
            id: event.segmentId ?? UUID().uuidString,
            source: event.source ?? "microphone",
            speakerHint: event.speakerHint ?? "self",
            speakerID: event.speakerId ?? event.speakerHint ?? "unknown",
            speakerLabel: event.speakerLabel ?? "",
            startMs: event.startMs ?? 0,
            endMs: event.endMs ?? 0,
            provider: event.provider ?? "backend",
            revision: event.revision ?? 0,
            isFinal: event.isFinal ?? (event.type == "transcript.final"),
            text: text
        )

        if let index = transcriptLines.firstIndex(where: { $0.id == line.id }) {
            transcriptLines[index] = line
        } else {
            transcriptLines.append(line)
            transcriptLines = Array(transcriptLines.suffix(maxTranscriptLineCount))
        }

        if line.isFinal {
            upsertFinalTranscriptArchive(line)
        }

    }

    private func upsertFinalTranscriptArchive(_ line: TranscriptLine) {
        if let index = finalTranscriptArchive.firstIndex(where: { $0.id == line.id }) {
            finalTranscriptArchive[index] = line
        } else {
            finalTranscriptArchive.append(line)
            finalTranscriptArchive = Array(finalTranscriptArchive.suffix(maxFinalTranscriptArchiveCount))
        }
    }

    private func configureTranscriptionClient(
        _ client: TranscriptionWebSocketClient,
        source: CaptureSource,
        label: String
    ) {
        client.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleTranscriptionEvent(event)
            }
        }

        client.onBackendLatency = { [weak self] latencyMs in
            Task { @MainActor in
                self?.updateBackendLatency(latencyMs, for: source)
            }
        }

        client.onTranscriptionLatency = { [weak self] latencyMs in
            Task { @MainActor in
                self?.updateTranscriptionLatency(latencyMs, for: source)
            }
        }

        client.onError = { [weak self] message in
            Task { @MainActor in
                self?.transcriptionStatus = .failed(message)
                self?.appendLog("\(label) transcription error: \(message)")
            }
        }
    }

    private func runAssistant(_ quickAction: AssistantQuickAction) {
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

    private func applyAssistantResponse(_ response: AssistantRespondResponse, label: String) {
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

    private func assistantTranscriptPayload(finalOnly: Bool = false) -> [AssistantTranscriptLinePayload] {
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

    private func assistantTranscriptPayload(lines: [TranscriptLine]) -> [AssistantTranscriptLinePayload] {
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

    private func startAutoSummaryCountdown() {
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

    private func stopAutoSummaryCountdown() {
        autoSummaryTask?.cancel()
        autoSummaryTask = nil
        autoSummaryRequestGeneration += 1
        autoSummaryIsGenerating = false
        autoSummaryRemainingSeconds = autoSummaryIntervalSeconds
        autoSummaryStatusLabel = "Start Meeting to begin"
    }

    private func startDocumentEditWatcher() {
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

    private func stopDocumentEditWatcher() {
        documentEditTask?.cancel()
        documentEditTask = nil
        documentEditRequestGeneration += 1
        documentEditIsPlanning = false
    }

    private func tickDocumentEditWatcher() {
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

    private func tickAutoSummaryCountdown() {
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

    private func runAutomaticMeetingSummary() {
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

    private func applyAutomaticSummaryResponse(_ response: AssistantRespondResponse) {
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

    private func applyGoogleAuthStatus(_ response: GoogleAuthStatusResponse) {
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

    private func applyGoogleDocSnapshot(
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

    private func applyGoogleBrowserResponse(_ response: GoogleBrowserResponse) {
        googleBrowserMessage = response.message
        googleDocsMessage = response.message
        googleBrowserSeleniumAvailable = response.seleniumAvailable
        googleBrowserChromeDriverAvailable = response.chromedriverAvailable
        googleBrowserSessionActive = response.browserSessionActive
    }

    private func runGoogleDocSnapshotAction(
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

    private func updateGoogleDocLiveNotes(triggeredByAutoSummary: Bool) {
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

    private func applyDocumentEditPlan(_ plan: DocumentEditPlanResponse) async throws -> GoogleDocSnapshotResponse {
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

    private func googleDocMeetingNotesRequest() -> GoogleDocMeetingNotesRequest {
        GoogleDocMeetingNotesRequest(
            meetingID: ensureCurrentMeetingID(),
            notes: previousNoteContextPayload(),
            actions: previousActionContextPayload(),
            transcript: assistantTranscriptPayload(finalOnly: true)
        )
    }

    private func documentEditKey(_ plan: DocumentEditPlanResponse) -> String {
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

    private func documentEditLabel(_ intent: String) -> String {
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

    private func ensureCurrentMeetingID() -> String {
        if currentMeetingID.isEmpty {
            currentMeetingID = "mtg-\(UUID().uuidString.lowercased())"
        }
        return currentMeetingID
    }

    private func resetAutoSummaryCountdown(status: String) {
        autoSummaryRemainingSeconds = autoSummaryIntervalSeconds
        autoSummaryStatusLabel = status
    }

    private func updateBackendLatency(_ latencyMs: Int, for source: CaptureSource) {
        switch source {
        case .microphone:
            microphoneBackendLatencyMs = latencyMs
        case .systemAudio:
            systemBackendLatencyMs = latencyMs
        }
    }

    private func updateTranscriptionLatency(_ latencyMs: Int, for source: CaptureSource) {
        switch source {
        case .microphone:
            microphoneTranscriptionLatencyMs = latencyMs
        case .systemAudio:
            systemTranscriptionLatencyMs = latencyMs
        }
    }

    private func resetLatencyReadings() {
        microphoneBackendLatencyMs = nil
        systemBackendLatencyMs = nil
        microphoneTranscriptionLatencyMs = nil
        systemTranscriptionLatencyMs = nil
    }

    private func resetMeetingDrafts() {
        noteDrafts = []
        actionDrafts = []
    }

    private func rollingSummaryContext() -> String {
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

    private func previousNoteContextPayload() -> [MeetingNoteContextPayload] {
        noteDrafts.map { MeetingNoteContextPayload(title: $0.title, detail: $0.detail) }
    }

    private func previousActionContextPayload() -> [MeetingActionContextPayload] {
        actionDrafts.map {
            MeetingActionContextPayload(title: $0.title, owner: $0.owner, state: $0.state)
        }
    }

    private func resetAssistantDrafts() {
        assistantRequestGeneration += 1
        activeAssistantAction = nil
        assistantModeLabel = "Ready"
        assistantStatus = .idle
        assistantDrafts = []
    }

    private func latestTranscriptText() -> String {
        guard let text = transcriptLines.last(where: { $0.isFinal })?.text ?? transcriptLines.last?.text else {
            return "對方剛剛提出的重點"
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "對方剛剛提出的重點"
        }

        return trimmed.count > 24 ? "\(trimmed.prefix(24))..." : trimmed
    }

    private static func transcriptLine(from historyLine: MeetingHistoryTranscriptLine) -> TranscriptLine {
        TranscriptLine(
            id: historyLine.segmentId,
            source: historyLine.source,
            speakerHint: historyLine.speakerHint,
            speakerID: historyLine.speakerId,
            speakerLabel: historyLine.speakerLabel,
            startMs: historyLine.startMs,
            endMs: historyLine.endMs,
            provider: historyLine.provider,
            revision: historyLine.revision,
            isFinal: historyLine.isFinal,
            text: historyLine.text
        )
    }

    private func exportMarkdown() -> String {
        var lines: [String] = []
        lines.append("# Meeting Record")
        lines.append("")
        lines.append("- Exported: \(displayTimestamp())")
        lines.append("- STT endpoint: \(transcriptionEndpointLabel)")
        lines.append("- Assistant provider: \(assistantProviderID)")
        lines.append("- Assistant model: \(assistantModel)")
        lines.append("")
        lines.append("## Meeting Notes")
        lines.append("")
        if noteDrafts.isEmpty {
            lines.append("_No meeting notes yet._")
        } else {
            for note in noteDrafts {
                lines.append("### \(note.title)")
                lines.append(note.detail)
                lines.append("")
            }
        }

        lines.append("## Next Actions")
        lines.append("")
        if actionDrafts.isEmpty {
            lines.append("_No next actions yet._")
        } else {
            for action in actionDrafts {
                lines.append("- [ ] \(action.title)  ")
                lines.append("  Owner: \(action.owner)  ")
                lines.append("  State: \(action.state)")
            }
        }

        lines.append("")
        lines.append("## AI Suggestions")
        lines.append("")
        if assistantDrafts.isEmpty {
            lines.append("_No assistant suggestions yet._")
        } else {
            for draft in assistantDrafts {
                lines.append("### \(draft.title)")
                lines.append("- Badge: \(draft.badge)")
                lines.append("- Suggestion: \(draft.detail)")
                lines.append("")
            }
        }

        lines.append("## Transcript")
        lines.append("")
        let exportTranscript = finalTranscriptArchive.isEmpty ? transcriptLines : finalTranscriptArchive
        if exportTranscript.isEmpty {
            lines.append("_No transcript yet._")
        } else {
            for line in exportTranscript {
                let status = line.isFinal ? "Final" : "Partial"
                lines.append("- `\(line.timeRangeLabel)` **\(line.sourceLabel)** (\(status), \(line.provider)): \(line.text)")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func shortTimeLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private func displayTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    private func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func safeFilename(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let parts = title.components(separatedBy: invalidCharacters)
        let normalized = parts.joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-. "))
        return normalized.isEmpty ? "meeting-record" : String(normalized.prefix(64))
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        eventLog.insert(line, at: 0)
        eventLog = Array(eventLog.prefix(8))
    }

    private func averageLatency(_ values: [Int?]) -> Int? {
        let concreteValues = values.compactMap(\.self)
        guard !concreteValues.isEmpty else {
            return nil
        }

        return concreteValues.reduce(0, +) / concreteValues.count
    }

    private func formatLatency(_ latencyMs: Int?) -> String {
        guard let latencyMs else {
            return "--"
        }

        return "\(latencyMs) ms"
    }

    private func openSystemSettings(path: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(path)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct VoiceEditError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
