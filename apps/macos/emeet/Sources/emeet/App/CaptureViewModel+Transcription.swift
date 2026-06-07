import Foundation

@MainActor
extension CaptureViewModel {
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

    func connectTranscription() {
        guard transcriptionStatus != .starting && transcriptionStatus != .running else {
            return
        }

        transcriptionStatus = .starting
        if shouldCreateNewMeetingOnNextStart {
            currentMeetingID = ""
            shouldCreateNewMeetingOnNextStart = false
        }
        let preserveLoadedMeeting = shouldPreserveLoadedMeetingOnNextStart
        shouldPreserveLoadedMeetingOnNextStart = false
        _ = ensureCurrentMeetingID()
        if preserveLoadedMeeting {
            summarizedFinalLineIDs = Set(finalTranscriptArchive.map(\.id))
            documentEditCheckedFinalLineIDs = Set(finalTranscriptArchive.map(\.id))
            appliedDocumentEditKeys.removeAll()
        } else {
            transcriptLines.removeAll()
            transcriptMarkers.removeAll()
            finalTranscriptArchive.removeAll()
            summarizedFinalLineIDs.removeAll()
            documentEditCheckedFinalLineIDs.removeAll()
            appliedDocumentEditKeys.removeAll()
            resetMeetingDrafts()
            resetAssistantDrafts()
        }
        resetLatencyReadings()
        appendLog("Connecting transcription backend at \(transcriptionBackend.displayAddress) for \(currentMeetingID)...")
        microphoneTranscriptionClient.connect(
            meetingID: currentMeetingID,
            sttProvider: transcriptionProviderID,
            sttModel: transcriptionModel,
            sttLanguage: transcriptionLanguage
        )
        systemTranscriptionClient.connect(
            meetingID: currentMeetingID,
            sttProvider: transcriptionProviderID,
            sttModel: transcriptionModel,
            sttLanguage: transcriptionLanguage
        )
        startAutoSummaryCountdown()
        startDocumentEditWatcher()
        prepareMeetingFromConnectedDocumentOnStart()

        if microphoneStatus != .running && microphoneStatus != .starting {
            startMicrophone()
        }

        if systemAudioStatus != .running && systemAudioStatus != .starting {
            startSystemAudio()
        }
    }

    func disconnectTranscription() {
        let endedMeetingID = currentMeetingID
        microphoneTranscriptionClient.disconnect()
        systemTranscriptionClient.disconnect()
        transcriptionStatus = .idle
        resetLatencyReadings()
        stopAutoSummaryCountdown()
        stopDocumentEditWatcher()
        shouldCreateNewMeetingOnNextStart = !currentMeetingID.isEmpty
        appendLog("Transcription backend disconnected.")
        requestGeneratedMeetingTitle(meetingID: endedMeetingID)
    }

    func handleTranscriptionEvent(_ event: TranscriptEvent) {
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
            speakerID: event.speakerId ?? event.speakerHint ?? "unknown",
            speakerLabel: event.speakerLabel ?? "",
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
            upsertFinalTranscriptArchive(line)
        }

    }

    func upsertFinalTranscriptArchive(_ line: TranscriptLine) {
        if let index = finalTranscriptArchive.firstIndex(where: { $0.id == line.id }) {
            finalTranscriptArchive[index] = line
        } else {
            finalTranscriptArchive.append(line)
            finalTranscriptArchive = Array(finalTranscriptArchive.suffix(maxFinalTranscriptArchiveCount))
        }
    }

    func configureTranscriptionClient(
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

    func updateBackendLatency(_ latencyMs: Int, for source: CaptureSource) {
        switch source {
        case .microphone:
            microphoneBackendLatencyMs = latencyMs
        case .systemAudio:
            systemBackendLatencyMs = latencyMs
        }
    }

    func updateTranscriptionLatency(_ latencyMs: Int, for source: CaptureSource) {
        switch source {
        case .microphone:
            microphoneTranscriptionLatencyMs = latencyMs
        case .systemAudio:
            systemTranscriptionLatencyMs = latencyMs
        }
    }

    func resetLatencyReadings() {
        microphoneBackendLatencyMs = nil
        systemBackendLatencyMs = nil
        microphoneTranscriptionLatencyMs = nil
        systemTranscriptionLatencyMs = nil
    }

    func recordTranscriptMarker(
        title: String,
        detail: String,
        iconName: String,
        style: TranscriptMarkerStyle
    ) {
        let marker = TranscriptMarker(
            title: title,
            detail: detail,
            iconName: iconName,
            style: style,
            createdAtMs: Int(Date().timeIntervalSince1970 * 1_000)
        )
        transcriptMarkers.append(marker)
        transcriptMarkers = Array(transcriptMarkers.suffix(maxTranscriptMarkerCount))
    }

    func averageLatency(_ values: [Int?]) -> Int? {
        let concreteValues = values.compactMap(\.self)
        guard !concreteValues.isEmpty else {
            return nil
        }

        return concreteValues.reduce(0, +) / concreteValues.count
    }

    func formatLatency(_ latencyMs: Int?) -> String {
        guard let latencyMs else {
            return "--"
        }

        return "\(latencyMs) ms"
    }

}
