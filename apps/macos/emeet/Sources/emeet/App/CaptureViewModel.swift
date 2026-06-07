import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published var microphoneStatus: CaptureStatus = .idle
    @Published var systemAudioStatus: CaptureStatus = .idle
    @Published var microphoneLevel: AudioLevel = .silent
    @Published var systemAudioLevel: AudioLevel = .silent
    @Published var microphoneHistory: [Float] = Array(repeating: 0, count: 96)
    @Published var systemAudioHistory: [Float] = Array(repeating: 0, count: 96)
    @Published var transcriptionStatus: CaptureStatus = .idle
    @Published var transcriptLines: [TranscriptLine] = []
    @Published var transcriptMarkers: [TranscriptMarker] = []
    @Published var transcriptionEndpointLabel: String
    @Published var transcriptionSettingsIsPresented = false
    @Published var transcriptionOptionsStatus: CaptureStatus = .idle
    @Published var transcriptionOptionsMessage = "正在檢查本機 STT 執行環境..."
    @Published var transcriptionHardwareLabel = "未知 Mac"
    @Published var transcriptionProviders: [TranscriptionProviderDescriptor] = []
    @Published var transcriptionLanguages: [TranscriptionLanguageOption] = []
    @Published var transcriptionProviderID = "mlx-whisper"
    @Published var transcriptionModel = "breeze-asr-25"
    @Published var transcriptionLanguage = "zh"
    @Published var microphoneBackendLatencyMs: Int?
    @Published var systemBackendLatencyMs: Int?
    @Published var microphoneTranscriptionLatencyMs: Int?
    @Published var systemTranscriptionLatencyMs: Int?
    @Published var assistantModeLabel = "就緒"
    @Published var assistantStatus: CaptureStatus = .idle
    @Published var assistantProviders: [AssistantProviderDescriptor] = []
    @Published var assistantProviderID = "codex-cli"
    @Published var assistantModel = "gpt-5.5"
    @Published var assistantThinking = AssistantThinking.medium.rawValue
    @Published var assistantDrafts: [AssistantDraft] = []
    @Published var activeAssistantAction: AssistantQuickAction?
    @Published var noteDrafts: [MeetingNoteDraft] = []
    @Published var actionDrafts: [MeetingActionDraft] = []
    @Published var autoSummaryRemainingSeconds = 30
    @Published var autoSummaryStatusLabel = "開始會議後啟動"
    @Published var autoSummaryIsGenerating = false
    @Published var googleDocsURL = ""
    @Published var googleDocsStatus: CaptureStatus = .idle
    @Published var googleDocsAuthReady = false
    @Published var googleDocsClientConfigured = false
    @Published var googleDocsDependenciesAvailable = false
    @Published var googleDocsConnectedTitle = ""
    @Published var googleDocsDocumentID = ""
    @Published var googleDocsRevisionID = ""
    @Published var googleDocsPreview = ""
    @Published var googleDocsPlainText = ""
    @Published var googleDocsBriefing = ""
    @Published var googleDocsSnippets: [String] = []
    @Published var googleDocsMessage = "尚未連接 Google Docs。"
    @Published var googleBrowserMessage = "瀏覽器輔助工具為選用功能。"
    @Published var googleBrowserSeleniumAvailable = false
    @Published var googleBrowserChromeDriverAvailable = false
    @Published var googleBrowserSessionActive = false
    @Published var googleBrowserFindText = ""
    @Published var meetingHistoryIsPresented = false
    @Published var meetingHistoryStatus: CaptureStatus = .idle
    @Published var meetingHistoryMessage = "從後端開啟已儲存會議。"
    @Published var meetingHistory: [MeetingHistorySummary] = []
    @Published var selectedMeetingHistoryID = ""
    @Published var selectedMeetingRecord: MeetingHistoryRecordResponse?
    @Published var eventLog: [String] = [
        "就緒。開始會議後會啟動擷取、逐字稿與自動摘要。"
    ]

    let microphoneService = MicrophoneCaptureService()
    let systemAudioService = SystemAudioCaptureService()
    let transcriptionBackend: TranscriptionBackendConfig
    let microphoneTranscriptionClient: TranscriptionWebSocketClient
    let systemTranscriptionClient: TranscriptionWebSocketClient
    let assistantClient: AssistantAPIClient
    let maxHistoryCount = 96
    let maxTranscriptLineCount = 24
    let maxTranscriptMarkerCount = 12
    let maxFinalTranscriptArchiveCount = 3_000
    let autoSummaryIntervalSeconds = 30
    let documentEditIntervalSeconds = 10
    var autoSummaryTask: Task<Void, Never>?
    var documentEditTask: Task<Void, Never>?
    var autoSummaryRequestGeneration = 0
    var documentEditRequestGeneration = 0
    var assistantRequestGeneration = 0
    var meetingHistoryRequestGeneration = 0
    var didRequestScreenRecordingPermission = false
    var currentMeetingID = ""
    var shouldCreateNewMeetingOnNextStart = false
    var shouldPreserveLoadedMeetingOnNextStart = false
    var finalTranscriptArchive: [TranscriptLine] = []
    var summarizedFinalLineIDs = Set<String>()
    var documentEditCheckedFinalLineIDs = Set<String>()
    var appliedDocumentEditKeys = Set<String>()
    var documentPreparedMeetingIDs = Set<String>()
    var documentEditIsPlanning = false

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
                self?.appendLog("麥克風錯誤：\(message)")
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
                self?.appendLog("系統音訊錯誤：\(message)")
            }
        }

        configureTranscriptionClient(
            microphoneTranscriptionClient,
            source: .microphone,
            label: "麥克風"
        )
        configureTranscriptionClient(
            systemTranscriptionClient,
            source: .systemAudio,
            label: "系統音訊"
        )

        refreshAssistantProviders()
        refreshTranscriptionOptions()
        refreshGoogleAuthStatus()
    }

}

struct VoiceEditError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
