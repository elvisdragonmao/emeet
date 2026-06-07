import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension CaptureViewModel {
    var meetingHistoryIsLoading: Bool {
        meetingHistoryStatus == .starting
    }

    func openMeetingHistory() {
        meetingHistoryIsPresented = true
        refreshMeetingHistory()
    }

    func closeMeetingHistory() {
        meetingHistoryIsPresented = false
    }

    func refreshMeetingHistory() {
        meetingHistoryRequestGeneration += 1
        let requestGeneration = meetingHistoryRequestGeneration
        meetingHistoryStatus = .starting
        meetingHistoryMessage = "Loading saved meetings..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let response = try await self.assistantClient.fetchMeetingHistory()
                guard self.meetingHistoryRequestGeneration == requestGeneration else {
                    return
                }

                self.meetingHistory = response.meetings
                if response.meetings.isEmpty {
                    self.selectedMeetingHistoryID = ""
                    self.selectedMeetingRecord = nil
                    self.meetingHistoryStatus = .idle
                    self.meetingHistoryMessage = "No saved meetings yet."
                    return
                }

                self.meetingHistoryMessage = "\(response.meetings.count) saved meetings"
                let selected = response.meetings.first { $0.meetingId == self.selectedMeetingHistoryID }
                    ?? response.meetings.first
                if let selected {
                    self.selectMeetingHistory(selected)
                } else {
                    self.meetingHistoryStatus = .running
                }
            } catch {
                guard self.meetingHistoryRequestGeneration == requestGeneration else {
                    return
                }

                self.meetingHistoryStatus = .failed(error.localizedDescription)
                self.meetingHistoryMessage = error.localizedDescription
            }
        }
    }

    func selectMeetingHistory(_ meeting: MeetingHistorySummary) {
        selectedMeetingHistoryID = meeting.meetingId
        selectedMeetingRecord = nil
        loadMeetingRecord(meetingID: meeting.meetingId)
    }

    func continueMeetingFromHistory(_ record: MeetingHistoryRecordResponse) {
        let wasActive = isMeetingActive
        if isMeetingActive {
            stopAll()
        }

        currentMeetingID = record.meeting.meetingId
        shouldCreateNewMeetingOnNextStart = false
        shouldPreserveLoadedMeetingOnNextStart = true
        let loadedLines = record.transcript.map(Self.transcriptLine(from:))
        finalTranscriptArchive = loadedLines
        transcriptLines = Array(loadedLines.suffix(maxTranscriptLineCount))
        summarizedFinalLineIDs = Set(loadedLines.map(\.id))
        documentEditCheckedFinalLineIDs = Set(loadedLines.map(\.id))
        appliedDocumentEditKeys.removeAll()
        noteDrafts = record.notes.map { MeetingNoteDraft(title: $0.title, detail: $0.detail) }
        actionDrafts = record.actions.map {
            MeetingActionDraft(title: $0.title, owner: $0.owner, state: $0.state)
        }
        assistantDrafts = record.assistantResponses.first?.suggestions.map {
            AssistantDraft(title: $0.title, detail: $0.detail, badge: $0.badge, iconName: $0.iconName)
        } ?? []
        resetLatencyReadings()
        meetingHistoryIsPresented = false
        autoSummaryStatusLabel = "Continuing saved meeting"
        appendLog("Continuing meeting: \(record.meeting.title).")
        if wasActive {
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                self?.connectTranscription()
            }
        } else {
            connectTranscription()
        }
    }

    func renameSelectedMeeting(to title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedMeetingHistoryID.isEmpty else {
            meetingHistoryMessage = "Select a meeting first."
            return
        }
        guard !trimmedTitle.isEmpty else {
            meetingHistoryMessage = "Meeting title cannot be empty."
            return
        }

        let meetingID = selectedMeetingHistoryID
        meetingHistoryStatus = .starting
        meetingHistoryMessage = "Renaming meeting..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let response = try await self.assistantClient.renameMeeting(meetingID: meetingID, title: trimmedTitle)
                self.applyUpdatedMeetingSummary(response.meeting)
                self.meetingHistoryStatus = .running
                self.meetingHistoryMessage = "Meeting renamed"
                self.appendLog("Meeting renamed: \(response.meeting.title).")
            } catch {
                self.meetingHistoryStatus = .failed(error.localizedDescription)
                self.meetingHistoryMessage = error.localizedDescription
                self.appendLog("Meeting rename failed: \(error.localizedDescription)")
            }
        }
    }

    func exportSelectedMeetingRecord(_ record: MeetingHistoryRecordResponse) {
        let panel = NSSavePanel()
        panel.title = "Export Saved Meeting"
        panel.nameFieldStringValue = "\(safeFilename(record.meeting.title))-\(fileTimestamp()).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        meetingHistoryStatus = .starting
        meetingHistoryMessage = "Exporting saved meeting..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let markdown = try await self.assistantClient.exportMeetingMarkdown(meetingID: record.meeting.meetingId)
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                self.meetingHistoryStatus = .running
                self.meetingHistoryMessage = "Meeting exported"
                self.appendLog("Saved meeting exported: \(url.lastPathComponent)")
            } catch {
                self.meetingHistoryStatus = .failed(error.localizedDescription)
                self.meetingHistoryMessage = error.localizedDescription
                self.appendLog("Saved meeting export failed: \(error.localizedDescription)")
            }
        }
    }

    func loadMeetingRecord(meetingID: String) {
        meetingHistoryRequestGeneration += 1
        let requestGeneration = meetingHistoryRequestGeneration
        meetingHistoryStatus = .starting
        meetingHistoryMessage = "Loading meeting record..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let record = try await self.assistantClient.fetchMeetingRecord(meetingID: meetingID)
                guard self.meetingHistoryRequestGeneration == requestGeneration,
                      self.selectedMeetingHistoryID == meetingID else {
                    return
                }

                self.selectedMeetingRecord = record
                self.meetingHistoryStatus = .running
                self.meetingHistoryMessage = "Meeting loaded"
            } catch {
                guard self.meetingHistoryRequestGeneration == requestGeneration else {
                    return
                }

                self.meetingHistoryStatus = .failed(error.localizedDescription)
                self.meetingHistoryMessage = error.localizedDescription
            }
        }
    }

    func requestGeneratedMeetingTitle(meetingID: String) {
        guard !meetingID.isEmpty else {
            return
        }

        let request = MeetingGenerateTitleRequest(
            provider: assistantProviderID,
            model: assistantModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "gpt-5.5"
                : assistantModel,
            thinking: assistantThinking
        )

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            try? await Task.sleep(nanoseconds: 700_000_000)

            do {
                let response = try await self.assistantClient.generateMeetingTitle(
                    meetingID: meetingID,
                    request: request
                )
                self.applyUpdatedMeetingSummary(response.meeting)
                if response.generated {
                    self.appendLog("AI generated meeting title: \(response.meeting.title).")
                }
            } catch {
                self.appendLog("AI meeting title generation failed: \(error.localizedDescription)")
            }
        }
    }

    func applyUpdatedMeetingSummary(_ meeting: MeetingHistorySummary) {
        if let index = meetingHistory.firstIndex(where: { $0.meetingId == meeting.meetingId }) {
            meetingHistory[index] = meeting
        }

        if let record = selectedMeetingRecord, record.meeting.meetingId == meeting.meetingId {
            selectedMeetingRecord = MeetingHistoryRecordResponse(
                meeting: meeting,
                transcript: record.transcript,
                assistantResponses: record.assistantResponses,
                notes: record.notes,
                actions: record.actions
            )
        }
    }

    static func transcriptLine(from historyLine: MeetingHistoryTranscriptLine) -> TranscriptLine {
        TranscriptLine(
            id: historyLine.segmentId,
            source: historyLine.source,
            speakerHint: historyLine.speakerHint,
            speakerID: historyLine.speakerId,
            speakerLabel: historyLine.speakerLabel,
            startMs: historyLine.startMs,
            endMs: historyLine.endMs,
            provider: historyLine.provider,
            revision: historyLine.revision,
            isFinal: historyLine.isFinal,
            text: historyLine.text
        )
    }

    func safeFilename(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.newlines)
            .union(.controlCharacters)
        let parts = title.components(separatedBy: invalidCharacters)
        let normalized = parts.joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-. "))
        return normalized.isEmpty ? "meeting-record" : String(normalized.prefix(64))
    }

}
