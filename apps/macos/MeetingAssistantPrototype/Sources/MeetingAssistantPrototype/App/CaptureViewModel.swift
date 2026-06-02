import AppKit
import Combine
import CoreGraphics
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

@MainActor
final class CaptureViewModel: ObservableObject {
    @Published private(set) var microphoneStatus: CaptureStatus = .idle
    @Published private(set) var systemAudioStatus: CaptureStatus = .idle
    @Published private(set) var microphoneLevel: AudioLevel = .silent
    @Published private(set) var systemAudioLevel: AudioLevel = .silent
    @Published private(set) var microphoneHistory: [Float] = Array(repeating: 0, count: 96)
    @Published private(set) var systemAudioHistory: [Float] = Array(repeating: 0, count: 96)
    @Published private(set) var eventLog: [String] = [
        "Ready. Start microphone and system audio capture to test inputs."
    ]

    private let microphoneService = MicrophoneCaptureService()
    private let systemAudioService = SystemAudioCaptureService()
    private let maxHistoryCount = 96

    init() {
        microphoneService.onLevel = { [weak self] level in
            Task { @MainActor in
                self?.update(level, for: .microphone)
            }
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

        systemAudioService.onError = { [weak self] message in
            Task { @MainActor in
                self?.systemAudioStatus = .failed(message)
                self?.appendLog("System audio error: \(message)")
            }
        }
    }

    var isAnyRunning: Bool {
        microphoneStatus == .running || systemAudioStatus == .running
    }

    func startAll() {
        startMicrophone()
        startSystemAudio()
    }

    func stopAll() {
        stopMicrophone()
        stopSystemAudio()
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
