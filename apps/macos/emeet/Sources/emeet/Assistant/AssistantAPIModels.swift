import Foundation

struct AssistantProviderDescriptor: Decodable, Identifiable, Equatable {
    let id: String
    let label: String
    let kind: String
    let installed: Bool
    let available: Bool
    let models: [String]
    let capabilities: [String]
    let riskLevel: String
    let authMode: String
    let endpoint: String
    let binaryPath: String
    let notes: [String]

    var statusLabel: String {
        available ? "Available" : "Unavailable"
    }
}

struct AssistantProviderDefaults: Decodable, Equatable {
    let provider: String
    let model: String
    let thinking: String
}

struct AssistantProvidersResponse: Decodable, Equatable {
    let defaults: AssistantProviderDefaults
    let providers: [AssistantProviderDescriptor]
}

struct TranscriptionOptionsResponse: Decodable, Equatable {
    let defaults: TranscriptionDefaults
    let hardware: TranscriptionHardware
    let providers: [TranscriptionProviderDescriptor]
    let languages: [TranscriptionLanguageOption]
}

struct TranscriptionDefaults: Decodable, Equatable {
    let provider: String
    let model: String
    let language: String
}

struct TranscriptionHardware: Decodable, Equatable {
    let platform: String
    let platformVersion: String
    let machine: String
    let cpu: String
    let memoryGb: Double
    let appleSilicon: Bool
}

struct TranscriptionProviderDescriptor: Decodable, Identifiable, Equatable {
    let id: String
    let label: String
    let installed: Bool
    let available: Bool
    let recommended: Bool
    let notes: [String]
    let models: [TranscriptionModelDescriptor]
}

struct TranscriptionModelDescriptor: Decodable, Identifiable, Equatable {
    let id: String
    let label: String
    let available: Bool
    let recommended: Bool
    let languageHint: String
    let estimatedSizeGb: Double
    let notes: [String]
}

struct TranscriptionLanguageOption: Decodable, Identifiable, Equatable {
    let id: String
    let label: String
    let notes: String
}

struct AssistantTranscriptLinePayload: Encodable {
    let source: String
    let sourceLabel: String
    let speakerHint: String
    let speakerID: String
    let speakerLabel: String
    let startMs: Int
    let endMs: Int
    let text: String
    let isFinal: Bool
}

struct MeetingNoteContextPayload: Encodable {
    let title: String
    let detail: String
}

struct MeetingActionContextPayload: Encodable {
    let title: String
    let owner: String
    let state: String
}

struct AssistantRespondRequest: Encodable {
    let action: String
    let meetingID: String
    let provider: String
    let model: String
    let thinking: String
    let transcript: [AssistantTranscriptLinePayload]
    let rollingSummary: String
    let previousNotes: [MeetingNoteContextPayload]
    let previousActions: [MeetingActionContextPayload]
    let documentTitle: String
    let documentSummary: String
    let documentSnippets: [String]
    let documentBriefing: String
}

struct AssistantRespondResponse: Decodable, Equatable {
    let provider: String
    let model: String
    let thinking: String
    let latencyMs: Int
    let drafts: [AssistantDraftResponse]
    let notes: [MeetingNoteResponse]
    let actions: [MeetingActionResponse]
    let documentEditPlan: DocumentEditPlanResponse?
}

struct DocumentEditPlanResponse: Decodable, Equatable {
    let intent: String
    let find: String
    let replace: String
    let heading: String
    let text: String
    let anchor: String
    let occurrence: String
    let reason: String
    let requiresUserConfirmation: Bool
}

struct AssistantDraftResponse: Decodable, Equatable {
    let title: String
    let detail: String
    let badge: String
    let iconName: String
}

struct MeetingNoteResponse: Decodable, Equatable {
    let title: String
    let detail: String
}

struct MeetingActionResponse: Decodable, Equatable {
    let title: String
    let owner: String
    let state: String
}

struct GoogleAuthStatusResponse: Decodable, Equatable {
    let ready: Bool
    let clientConfigured: Bool
    let tokenConfigured: Bool
    let dependenciesAvailable: Bool
    let scopes: [String]
}

struct GoogleDocConnectRequest: Encodable {
    let url: String
    let meetingID: String
    let provider: String
    let model: String
    let thinking: String
}

struct GoogleDocMeetingRequest: Encodable {
    let meetingID: String
}

struct GoogleDocAppendRequest: Encodable {
    let meetingID: String
    let text: String
}

struct GoogleDocReplaceTextRequest: Encodable {
    let meetingID: String
    let find: String
    let replace: String
    let occurrence: String
}

struct GoogleDocInsertUnderHeadingRequest: Encodable {
    let meetingID: String
    let heading: String
    let text: String
}

struct GoogleDocRewriteParagraphRequest: Encodable {
    let meetingID: String
    let anchor: String
    let text: String
}

struct GoogleBrowserOpenRequest: Encodable {
    let meetingID: String
    let url: String
}

struct GoogleBrowserMeetingRequest: Encodable {
    let meetingID: String
}

struct GoogleBrowserFindRequest: Encodable {
    let meetingID: String
    let text: String
}

struct GoogleDocMeetingNotesRequest: Encodable {
    let meetingID: String
    let notes: [MeetingNoteContextPayload]
    let actions: [MeetingActionContextPayload]
    let transcript: [AssistantTranscriptLinePayload]
}

struct GoogleDocSnapshotResponse: Decodable, Equatable {
    let connected: Bool?
    let meetingId: String?
    let documentId: String
    let title: String
    let revisionId: String
    let preview: String
    let plainText: String?
    let documentBriefing: String?
    let briefingError: String?
    let snippets: [String]?
    let status: String?
    let message: String?
}

struct GoogleBrowserResponse: Decodable, Equatable {
    let ok: Bool
    let message: String
    let seleniumAvailable: Bool
    let chromedriverAvailable: Bool
    let browserSessionActive: Bool
}

struct MeetingHistoryListResponse: Decodable, Equatable {
    let meetings: [MeetingHistorySummary]
}

struct MeetingHistorySummary: Decodable, Identifiable, Equatable {
    let meetingId: String
    let title: String
    let titleIsManual: Bool
    let startedAtMs: Int
    let endedAtMs: Int?
    let durationMs: Int
    let sttProvider: String
    let sttModel: String
    let assistantProvider: String
    let assistantModel: String
    let transcriptCount: Int
    let assistantResponseCount: Int
    let notesCount: Int
    let actionsCount: Int
    let createdAtMs: Int
    let updatedAtMs: Int

    var id: String { meetingId }
}

struct MeetingHistoryRecordResponse: Decodable, Equatable {
    let meeting: MeetingHistorySummary
    let transcript: [MeetingHistoryTranscriptLine]
    let assistantResponses: [MeetingHistoryAssistantResponse]
    let notes: [MeetingNoteResponse]
    let actions: [MeetingActionResponse]
}

struct MeetingHistoryTranscriptLine: Decodable, Identifiable, Equatable {
    let segmentId: String
    let source: String
    let speakerHint: String
    let speakerId: String
    let speakerLabel: String
    let startMs: Int
    let endMs: Int
    let text: String
    let revision: Int
    let isFinal: Bool
    let confidence: Double
    let provider: String
    let createdAtMs: Int

    var id: String { segmentId }

    var sourceLabel: String {
        let trimmedSpeakerLabel = speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSpeakerLabel.isEmpty {
            return trimmedSpeakerLabel
        }

        switch speakerHint {
        case "self":
            return "Self"
        case "other":
            return "Other"
        default:
            return source.capitalized
        }
    }

    var timeRangeLabel: String {
        "\(Self.format(milliseconds: startMs)) - \(Self.format(milliseconds: endMs))"
    }

    private static func format(milliseconds: Int) -> String {
        let totalSeconds = max(0, milliseconds / 1_000)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct MeetingHistoryAssistantResponse: Decodable, Identifiable, Equatable {
    let id: Int
    let action: String
    let provider: String
    let model: String
    let thinking: String
    let latencyMs: Int
    let createdAtMs: Int
    let suggestions: [MeetingHistorySuggestion]
}

struct MeetingHistorySuggestion: Decodable, Identifiable, Equatable {
    let id: Int
    let title: String
    let detail: String
    let badge: String
    let iconName: String
}

struct MeetingRenameRequest: Encodable {
    let title: String
}

struct MeetingGenerateTitleRequest: Encodable {
    let provider: String
    let model: String
    let thinking: String
}

struct MeetingMutationResponse: Decodable, Equatable {
    let meeting: MeetingHistorySummary
}

struct MeetingGenerateTitleResponse: Decodable, Equatable {
    let meeting: MeetingHistorySummary
    let generated: Bool
}
