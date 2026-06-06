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
    @Published private(set) var googleDocsMode: GoogleDocsSyncMode = .afterMeetingAppend
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
    @Published private(set) var googleDocsFindText = ""
    @Published private(set) var googleDocsReplaceText = ""
    @Published private(set) var googleDocsReplaceOccurrence: GoogleDocsReplaceOccurrence = .first
    @Published private(set) var googleDocsInsertHeading = ""
    @Published private(set) var googleDocsInsertText = ""
    @Published private(set) var googleDocsRewriteAnchor = ""
    @Published private(set) var googleDocsRewriteText = ""
    @Published private(set) var googleBrowserMessage = "Browser helper optional."
    @Published private(set) var googleBrowserSeleniumAvailable = false
    @Published private(set) var googleBrowserChromeDriverAvailable = false
    @Published private(set) var googleBrowserSessionActive = false
    @Published private(set) var googleBrowserFindText = ""
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
    private var autoSummaryTask: Task<Void, Never>?
    private var autoSummaryRequestGeneration = 0
    private var assistantRequestGeneration = 0
    private var didRequestScreenRecordingPermission = false
    private var currentMeetingID = ""
    private var finalTranscriptArchive: [TranscriptLine] = []
    private var summarizedFinalLineIDs = Set<String>()

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
        refreshGoogleAuthStatus()
        refreshGoogleBrowserStatus()
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
        _ = ensureCurrentMeetingID()
        transcriptLines.removeAll()
        finalTranscriptArchive.removeAll()
        summarizedFinalLineIDs.removeAll()
        resetLatencyReadings()
        resetMeetingDrafts()
        appendLog("Connecting transcription backend at \(transcriptionBackend.displayAddress)...")
        microphoneTranscriptionClient.connect(meetingID: currentMeetingID)
        systemTranscriptionClient.connect(meetingID: currentMeetingID)
        startAutoSummaryCountdown()

        if microphoneStatus != .running && microphoneStatus != .starting {
            startMicrophone()
        }

        if systemAudioStatus != .running && systemAudioStatus != .starting {
            startSystemAudio()
        }
    }

    func disconnectTranscription() {
        microphoneTranscriptionClient.disconnect()
        systemTranscriptionClient.disconnect()
        transcriptionStatus = .idle
        resetLatencyReadings()
        stopAutoSummaryCountdown()
        appendLog("Transcription backend disconnected.")
    }

    func clearCurrentRecords() {
        autoSummaryRequestGeneration += 1
        autoSummaryIsGenerating = false
        transcriptLines.removeAll()
        finalTranscriptArchive.removeAll()
        summarizedFinalLineIDs.removeAll()
        resetLatencyReadings()
        resetMeetingDrafts()
        resetAssistantDrafts()

        if transcriptionStatus == .starting || transcriptionStatus == .running {
            resetAutoSummaryCountdown(status: "Records cleared")
        } else {
            autoSummaryRemainingSeconds = autoSummaryIntervalSeconds
            autoSummaryStatusLabel = "Start Meeting to begin"
        }

        appendLog("Current meeting records cleared.")
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

    func updateGoogleDocsMode(_ mode: GoogleDocsSyncMode) {
        googleDocsMode = mode
        appendLog("Google Docs mode set to \(mode.label).")
    }

    func updateGoogleDocsFindText(_ text: String) {
        googleDocsFindText = text
    }

    func updateGoogleDocsReplaceText(_ text: String) {
        googleDocsReplaceText = text
    }

    func updateGoogleDocsReplaceOccurrence(_ occurrence: GoogleDocsReplaceOccurrence) {
        googleDocsReplaceOccurrence = occurrence
    }

    func updateGoogleDocsInsertHeading(_ heading: String) {
        googleDocsInsertHeading = heading
    }

    func updateGoogleDocsInsertText(_ text: String) {
        googleDocsInsertText = text
    }

    func updateGoogleDocsRewriteAnchor(_ anchor: String) {
        googleDocsRewriteAnchor = anchor
    }

    func updateGoogleDocsRewriteText(_ text: String) {
        googleDocsRewriteText = text
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

    func applyGoogleDocsReplacement() {
        guard googleDocsIsConnected else {
            googleDocsMessage = "Connect a Google Doc first."
            return
        }

        let find = googleDocsFindText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !find.isEmpty else {
            googleDocsMessage = "Enter find text before applying an edit."
            return
        }

        googleDocsStatus = .starting
        googleDocsMessage = "Applying direct Google Docs edit..."
        appendLog("Applying Google Docs find/replace edit.")
        let request = GoogleDocReplaceTextRequest(
            meetingID: ensureCurrentMeetingID(),
            find: find,
            replace: googleDocsReplaceText,
            occurrence: googleDocsReplaceOccurrence.rawValue
        )

        Task {
            do {
                let response = try await assistantClient.replaceGoogleDocText(request)
                applyGoogleDocSnapshot(response, fallbackMessage: "Google Doc text replaced.")
                appendLog("Google Doc direct edit applied.")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Doc direct edit failed: \(error.localizedDescription)")
            }
        }
    }

    func insertGoogleDocsTextUnderHeading() {
        guard googleDocsIsConnected else {
            googleDocsMessage = "Connect a Google Doc first."
            return
        }

        let heading = googleDocsInsertHeading.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = googleDocsInsertText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heading.isEmpty else {
            googleDocsMessage = "Enter a heading before inserting text."
            return
        }
        guard !text.isEmpty else {
            googleDocsMessage = "Enter text to insert under the heading."
            return
        }

        googleDocsStatus = .starting
        googleDocsMessage = "Inserting text under heading..."
        appendLog("Inserting Google Docs text under heading.")
        let request = GoogleDocInsertUnderHeadingRequest(
            meetingID: ensureCurrentMeetingID(),
            heading: heading,
            text: text
        )

        Task {
            do {
                let response = try await assistantClient.insertGoogleDocTextUnderHeading(request)
                applyGoogleDocSnapshot(response, fallbackMessage: "Text inserted under heading.")
                appendLog("Google Doc heading insert applied.")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Doc heading insert failed: \(error.localizedDescription)")
            }
        }
    }

    func rewriteGoogleDocsParagraph() {
        guard googleDocsIsConnected else {
            googleDocsMessage = "Connect a Google Doc first."
            return
        }

        let anchor = googleDocsRewriteAnchor.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = googleDocsRewriteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !anchor.isEmpty else {
            googleDocsMessage = "Enter anchor text for the paragraph rewrite."
            return
        }
        guard !text.isEmpty else {
            googleDocsMessage = "Enter the replacement paragraph."
            return
        }

        googleDocsStatus = .starting
        googleDocsMessage = "Rewriting paragraph..."
        appendLog("Rewriting Google Docs paragraph containing anchor.")
        let request = GoogleDocRewriteParagraphRequest(
            meetingID: ensureCurrentMeetingID(),
            anchor: anchor,
            text: text
        )

        Task {
            do {
                let response = try await assistantClient.rewriteGoogleDocParagraph(request)
                applyGoogleDocSnapshot(response, fallbackMessage: "Paragraph rewritten.")
                appendLog("Google Doc paragraph rewrite applied.")
            } catch {
                googleDocsStatus = .failed(error.localizedDescription)
                googleDocsMessage = error.localizedDescription
                appendLog("Google Doc paragraph rewrite failed: \(error.localizedDescription)")
            }
        }
    }

    func openGoogleDocInBrowser() {
        guard googleDocsIsConnected || !googleDocsURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            googleBrowserMessage = "Connect a Google Doc or paste a URL first."
            return
        }

        let request = GoogleBrowserOpenRequest(
            meetingID: ensureCurrentMeetingID(),
            url: googleDocsURL.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        appendLog("Opening Google Doc in browser helper.")
        Task {
            do {
                let response = try await assistantClient.openGoogleDocInBrowser(request)
                applyGoogleBrowserResponse(response)
                appendLog("Google Doc browser open result: \(response.message)")
            } catch {
                googleBrowserMessage = error.localizedDescription
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

        if googleDocsMode == .liveNotes && googleDocsIsConnected {
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

    private func googleDocMeetingNotesRequest() -> GoogleDocMeetingNotesRequest {
        GoogleDocMeetingNotesRequest(
            meetingID: ensureCurrentMeetingID(),
            notes: previousNoteContextPayload(),
            actions: previousActionContextPayload(),
            transcript: assistantTranscriptPayload(finalOnly: true)
        )
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
