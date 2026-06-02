import Foundation

struct TranscriptLine: Identifiable, Equatable {
    let id: String
    let source: String
    let speakerHint: String
    let startMs: Int
    let endMs: Int
    let provider: String
    let revision: Int
    let isFinal: Bool
    let text: String

    var sourceLabel: String {
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

struct AssistantDraft: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
    let badge: String
    let iconName: String
}

struct MeetingNoteDraft: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let detail: String
}

struct MeetingActionDraft: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let owner: String
    let state: String
}

enum AssistantThinking: String, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:
            return "None"
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .xhigh:
            return "XHigh"
        }
    }
}

enum AssistantQuickAction: String, Equatable {
    case whatShouldISay
    case followUpQuestions

    var requestAction: String {
        switch self {
        case .whatShouldISay:
            return "what_should_i_say"
        case .followUpQuestions:
            return "follow_up_questions"
        }
    }

    var label: String {
        switch self {
        case .whatShouldISay:
            return "What should I say?"
        case .followUpQuestions:
            return "Follow-up questions"
        }
    }
}
