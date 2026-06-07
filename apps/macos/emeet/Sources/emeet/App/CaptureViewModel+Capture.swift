import AppKit
import Foundation

@MainActor
extension CaptureViewModel {
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
        documentPreparedMeetingIDs.removeAll()
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

    func openMicrophoneSettings() {
        openSystemSettings(path: "com.apple.preference.security?Privacy_Microphone")
    }

    func openScreenRecordingSettings() {
        openSystemSettings(path: "com.apple.preference.security?Privacy_ScreenCapture")
    }

    func update(_ level: AudioLevel, for source: CaptureSource) {
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

    func ensureCurrentMeetingID() -> String {
        if currentMeetingID.isEmpty {
            currentMeetingID = "mtg-\(UUID().uuidString.lowercased())"
        }
        return currentMeetingID
    }

    func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        eventLog.insert(line, at: 0)
        eventLog = Array(eventLog.prefix(8))
    }

    func openSystemSettings(path: String) {
        guard let url = URL(string: "x-apple.systempreferences:\(path)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

}
