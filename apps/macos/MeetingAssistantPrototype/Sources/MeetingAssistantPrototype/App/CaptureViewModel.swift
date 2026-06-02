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
    @Published private(set) var assistantModeLabel = "Ready"
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
    private let maxHistoryCount = 96
    private let maxTranscriptLineCount = 24

    init(transcriptionBackend: TranscriptionBackendConfig = .fromEnvironment()) {
        self.transcriptionBackend = transcriptionBackend
        transcriptionEndpointLabel = transcriptionBackend.displayAddress
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

        configureTranscriptionClient(microphoneTranscriptionClient, label: "Microphone")
        configureTranscriptionClient(systemTranscriptionClient, label: "System audio")
    }

    var isAnyRunning: Bool {
        microphoneStatus == .running || systemAudioStatus == .running
    }

    var transcriptCountsLabel: String {
        let finalCount = transcriptLines.filter(\.isFinal).count
        let partialCount = transcriptLines.count - finalCount
        return "\(finalCount) final / \(partialCount) live"
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
        appendLog("Transcription backend disconnected.")
    }

    func prepareWhatShouldISay() {
        assistantModeLabel = "What should I say?"
        let context = latestTranscriptText()
        assistantDrafts = [
            AssistantDraft(
                title: "先確認問題",
                detail: "我先確認一下，你目前最想釐清的是 \(context)，對嗎？",
                badge: "Placeholder",
                iconName: "quote.bubble"
            ),
            AssistantDraft(
                title: "保守回覆",
                detail: "我可以先給一個初步方向，細節我會再確認後補上。",
                badge: "Safe",
                iconName: "checkmark.seal"
            )
        ]
        appendLog("Prepared What should I say placeholders.")
    }

    func prepareFollowUpQuestions() {
        assistantModeLabel = "Follow-up questions"
        assistantDrafts = [
            AssistantDraft(
                title: "釐清目標",
                detail: "你希望我們優先解決的是時程、品質，還是成本？",
                badge: "Clarify",
                iconName: "questionmark.bubble"
            ),
            AssistantDraft(
                title: "確認下一步",
                detail: "下一步誰負責、什麼時間前需要完成？",
                badge: "Action",
                iconName: "arrowshape.turn.up.right"
            ),
            AssistantDraft(
                title: "補齊風險",
                detail: "目前有沒有任何限制或依賴，是我們還沒討論到的？",
                badge: "Risk",
                iconName: "exclamationmark.triangle"
            )
        ]
        appendLog("Prepared Follow-up question placeholders.")
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

    private func configureTranscriptionClient(_ client: TranscriptionWebSocketClient, label: String) {
        client.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleTranscriptionEvent(event)
            }
        }

        client.onError = { [weak self] message in
            Task { @MainActor in
                self?.transcriptionStatus = .failed(message)
                self?.appendLog("\(label) transcription error: \(message)")
            }
        }
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

    private func openSystemSettings(path: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(path)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
