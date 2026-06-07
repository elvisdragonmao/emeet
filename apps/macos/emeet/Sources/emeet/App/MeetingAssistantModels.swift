import Foundation

struct TranscriptLine: Identifiable, Equatable {
    let id: String
    let source: String
    let speakerHint: String
    let speakerID: String
    let speakerLabel: String
    let startMs: Int
    let endMs: Int
    let provider: String
    let revision: Int
    let isFinal: Bool
    let text: String

    var sourceLabel: String {
        if !speakerLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return speakerLabel
        }

        switch speakerHint {
        case "self":
            return "自己"
        case "other":
            return "對方"
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

struct TranscriptMarker: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let iconName: String
    let style: TranscriptMarkerStyle
    let createdAtMs: Int
    let anchorLineID: String?
    let anchorMs: Int

    var timeLabel: String {
        let date = Date(timeIntervalSince1970: TimeInterval(createdAtMs) / 1_000)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

enum TranscriptMarkerStyle: String, Equatable {
    case info
    case progress
    case success
    case warning
    case failure
}

enum DocumentEditCommandHint {
    case explicit
    case missingWakeWord
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
            return "無"
        case .low:
            return "低"
        case .medium:
            return "中"
        case .high:
            return "高"
        case .xhigh:
            return "最高"
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
            return "我該怎麼說？"
        case .followUpQuestions:
            return "追問問題"
        }
    }
}
