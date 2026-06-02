import Foundation

enum CaptureSource: String, CaseIterable, Identifiable {
    case microphone
    case systemAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .systemAudio:
            return "System Audio"
        }
    }

    var subtitle: String {
        switch self {
        case .microphone:
            return "AVAudioEngine input"
        case .systemAudio:
            return "ScreenCaptureKit audio"
        }
    }

    var iconName: String {
        switch self {
        case .microphone:
            return "mic.fill"
        case .systemAudio:
            return "display.and.speaker.wave.2.fill"
        }
    }
}

enum CaptureStatus: Equatable {
    case idle
    case starting
    case running
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .starting:
            return "Starting"
        case .running:
            return "Running"
        case .failed:
            return "Error"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "尚未開始"
        case .starting:
            return "正在啟動"
        case .running:
            return "正在擷取"
        case .failed(let message):
            return message
        }
    }
}

enum CaptureError: LocalizedError {
    case permissionDenied(String)
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let message):
            return message
        case .noDisplay:
            return "找不到可擷取的螢幕。"
        }
    }
}
