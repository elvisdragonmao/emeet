import AppKit
import Combine
import CoreGraphics
import Foundation

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
    @Published private(set) var assistantProviderID = "mock"
    @Published private(set) var assistantModel = "mock-conversation"
    @Published private(set) var assistantThinking = AssistantThinking.medium.rawValue
    @Published private(set) var assistantDrafts: [AssistantDraft] = [
        AssistantDraft(
            title: "回覆策略",
            detail: "等待逐字稿事件後，這裡會放可直接說出口的短句草稿。",
            badge: "Draft",
            iconName: "quote.bubble"
        )
    ]
    @Published private(set) var noteDrafts: [MeetingNoteDraft] = [
        MeetingNoteDraft(title: "討論重點", detail: "逐字稿定稿後會累積 highlights。"),
        MeetingNoteDraft(title: "未決問題", detail: "尚未確認的風險、限制與依賴會放在這裡。")
    ]
    @Published private(set) var actionDrafts: [MeetingActionDraft] = [
        MeetingActionDraft(title: "整理下一步", owner: "Unassigned", state: "Pending")
    ]
    @Published private(set) var eventLog: [String] = [
        "Ready. Start microphone and system audio capture to test inputs."
    ]

    private let microphoneService = MicrophoneCaptureService()
    private let systemAudioService = SystemAudioCaptureService()
    private let transcriptionBackend: TranscriptionBackendConfig
    private let microphoneTranscriptionClient: TranscriptionWebSocketClient
    private let systemTranscriptionClient: TranscriptionWebSocketClient
    private let assistantClient: AssistantAPIClient
    private let maxHistoryCount = 96
    private let maxTranscriptLineCount = 24

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
    }

    var isAnyRunning: Bool {
        microphoneStatus == .running || systemAudioStatus == .running
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
                    id: "mock",
                    label: "Mock Assistant",
                    kind: "local_server",
                    installed: true,
                    available: true,
                    models: ["mock-conversation"],
                    capabilities: ["chat"],
                    riskLevel: "low",
                    authMode: "none",
                    endpoint: "",
                    binaryPath: "",
                    notes: []
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

    func startAll() {
        startMicrophone()
        startSystemAudio()
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
        transcriptLines.removeAll()
        resetLatencyReadings()
        appendLog("Connecting transcription backend at \(transcriptionBackend.displayAddress)...")
        microphoneTranscriptionClient.connect()
        systemTranscriptionClient.connect()

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
        appendLog("Transcription backend disconnected.")
    }

    func prepareWhatShouldISay() {
        runAssistant(action: "what_should_i_say", label: "What should I say?")
    }

    func prepareFollowUpQuestions() {
        runAssistant(action: "follow_up_questions", label: "Follow-up questions")
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
            refreshDraftNotes(with: line)
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

    private func runAssistant(action: String, label: String) {
        assistantStatus = .starting
        assistantModeLabel = "\(label) · \(assistantProviderID)"
        assistantDrafts = [
            AssistantDraft(
                title: "Generating",
                detail: "AI 正在根據最近逐字稿產生建議。",
                badge: assistantThinking,
                iconName: "sparkles"
            )
        ]
        appendLog("Requesting assistant response: \(label).")

        let request = AssistantRespondRequest(
            action: action,
            provider: assistantProviderID,
            model: assistantModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "mock-conversation"
                : assistantModel,
            thinking: assistantThinking,
            transcript: assistantTranscriptPayload()
        )

        Task {
            do {
                let response = try await assistantClient.respond(request)
                applyAssistantResponse(response, label: label)
            } catch {
                assistantStatus = .failed(error.localizedDescription)
                assistantModeLabel = "AI error"
                assistantDrafts = [
                    AssistantDraft(
                        title: "Assistant error",
                        detail: error.localizedDescription,
                        badge: "Error",
                        iconName: "exclamationmark.triangle"
                    )
                ]
                appendLog("Assistant response failed: \(error.localizedDescription)")
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

        appendLog("Assistant response ready: \(response.provider) \(response.model) \(response.latencyMs)ms.")
    }

    private func assistantTranscriptPayload() -> [AssistantTranscriptLinePayload] {
        transcriptLines.suffix(16).map {
            AssistantTranscriptLinePayload(
                source: $0.source,
                sourceLabel: $0.sourceLabel,
                speakerHint: $0.speakerHint,
                startMs: $0.startMs,
                endMs: $0.endMs,
                text: $0.text,
                isFinal: $0.isFinal
            )
        }
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

    private func refreshDraftNotes(with line: TranscriptLine) {
        noteDrafts = [
            MeetingNoteDraft(title: "最新重點", detail: line.text),
            MeetingNoteDraft(title: "時間範圍", detail: "\(line.timeRangeLabel) · \(line.sourceLabel)")
        ]
        actionDrafts = [
            MeetingActionDraft(title: "Review transcript segment", owner: line.sourceLabel, state: "Draft")
        ]
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
