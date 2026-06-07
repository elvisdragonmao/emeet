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
            appendLog("螢幕錄製權限可用。")
            return
        }

        appendLog("正在請求螢幕錄製權限...")
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            appendLog("螢幕錄製權限已授權。")
        } else {
            systemAudioStatus = .failed("螢幕錄製權限尚未授權。授權後通常需要重新啟動 App。")
            appendLog("螢幕錄製權限尚未授權。")
        }
    }

    func stopAll() {
        stopMicrophone()
        stopSystemAudio()
        disconnectTranscription()
    }

    func startMicrophone() {
        microphoneStatus = .starting
        appendLog("正在啟動麥克風擷取...")

        Task {
            do {
                try await microphoneService.start()
                microphoneStatus = .running
                appendLog("麥克風擷取已啟動。")
            } catch {
                microphoneStatus = .failed(error.localizedDescription)
                appendLog("麥克風擷取失敗：\(error.localizedDescription)")
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
        appendLog("麥克風擷取已停止。")
    }

    func startSystemAudio() {
        systemAudioStatus = .starting
        appendLog("正在啟動 ScreenCaptureKit 系統音訊...")

        Task {
            do {
                try await systemAudioService.start()
                systemAudioStatus = .running
                appendLog("系統音訊擷取已啟動。可播放其他 App 的音訊測試。")
            } catch {
                systemAudioStatus = .failed(error.localizedDescription)
                appendLog("系統音訊擷取失敗：\(error.localizedDescription)")
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
            appendLog("系統音訊擷取已停止。")
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
        transcriptMarkers.removeAll()
        finalTranscriptArchive.removeAll()
        summarizedFinalLineIDs.removeAll()
        documentEditCheckedFinalLineIDs.removeAll()
        appliedDocumentEditKeys.removeAll()
        documentPreparedMeetingIDs.removeAll()
        resetLatencyReadings()
        resetMeetingDrafts()
        resetAssistantDrafts()

        if transcriptionStatus == .starting || transcriptionStatus == .running {
            resetAutoSummaryCountdown(status: "紀錄已清除")
        } else {
            autoSummaryRemainingSeconds = autoSummaryIntervalSeconds
            autoSummaryStatusLabel = "開始會議後啟動"
        }

        appendLog("新會議已準備好。")
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
