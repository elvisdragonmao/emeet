import SwiftUI

struct MeetingHistoryDetail: View {
    let record: MeetingHistoryRecordResponse?
    let isLoading: Bool
    let renameAction: (String) -> Void
    let exportAction: (MeetingHistoryRecordResponse) -> Void
    let continueAction: (MeetingHistoryRecordResponse) -> Void
    @State private var selectedTab: MeetingHistoryTab = .transcript
    @State private var titleDraft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let record {
                summary(record)
                Picker("History section", selection: $selectedTab) {
                    ForEach(MeetingHistoryTab.allCases) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Divider()

                selectedContent(record)
            } else {
                VStack(spacing: 12) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.regular)
                    } else {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(isLoading ? "Loading meeting" : "Select a meeting")
                        .font(.headline)
                    Text("Transcript, reply history, meeting notes, and next actions will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(18)
        .onAppear {
            titleDraft = record?.meeting.title ?? ""
        }
        .onChange(of: record?.meeting.meetingId) { _, _ in
            titleDraft = record?.meeting.title ?? ""
        }
        .onChange(of: record?.meeting.title) { _, _ in
            titleDraft = record?.meeting.title ?? ""
        }
    }

    func summary(_ record: MeetingHistoryRecordResponse) -> some View {
        let meeting = record.meeting
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(meeting.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text(historyDuration(milliseconds: meeting.durationMs))
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Label(historyDate(milliseconds: meeting.startedAtMs), systemImage: "calendar")
                Label(providerLabel(meeting), systemImage: "cpu")
                Label("\(meeting.transcriptCount) transcript", systemImage: "text.quote")
                Label("\(meeting.assistantResponseCount) responses", systemImage: "sparkles")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: 8) {
                TextField("Meeting name", text: $titleDraft)
                    .textFieldStyle(.roundedBorder)

                Button {
                    renameAction(titleDraft)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .disabled(titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    exportAction(record)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }

                Button {
                    continueAction(record)
                } label: {
                    Label("Continue", systemImage: "arrowshape.turn.up.right")
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.regular)

            Label(meeting.titleIsManual ? "Manual name" : "AI/generated name", systemImage: meeting.titleIsManual ? "person.fill" : "sparkles")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    func selectedContent(_ record: MeetingHistoryRecordResponse) -> some View {
        switch selectedTab {
        case .transcript:
            HistoryTranscriptList(lines: record.transcript)
        case .responses:
            HistoryAssistantResponses(responses: record.assistantResponses)
        case .notes:
            HistoryNotes(notes: record.notes)
        case .actions:
            HistoryActions(actions: record.actions)
        }
    }
}

enum MeetingHistoryTab: String, CaseIterable, Identifiable {
    case transcript
    case responses
    case notes
    case actions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .transcript:
            return "Transcript"
        case .responses:
            return "Replies"
        case .notes:
            return "Notes"
        case .actions:
            return "Actions"
        }
    }
}

struct HistoryTranscriptList: View {
    let lines: [MeetingHistoryTranscriptLine]

    var body: some View {
        if lines.isEmpty {
            HistoryEmptyState(icon: "text.quote", title: "No transcript", detail: "Final transcript segments are saved after STT emits them.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(lines) { line in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(sourceColor(line))
                                .frame(width: 8, height: 8)
                                .padding(.top, 7)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(line.sourceLabel)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(sourceColor(line))
                                    Text(line.timeRangeLabel)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }

                                Text(line.text)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(sourceColor(line).opacity(0.45), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    func sourceColor(_ line: MeetingHistoryTranscriptLine) -> Color {
        if line.speakerHint == "self" {
            return .blue
        }
        switch line.speakerId {
        case "speaker_1":
            return .green
        case "speaker_2":
            return .orange
        case "speaker_3":
            return .purple
        case "speaker_4":
            return .pink
        default:
            return line.speakerHint == "other" ? .green : .purple
        }
    }
}

struct HistoryAssistantResponses: View {
    let responses: [MeetingHistoryAssistantResponse]

    var body: some View {
        if responses.isEmpty {
            HistoryEmptyState(
                icon: "sparkles",
                title: "No reply history",
                detail: "Use What should I say? or Follow-up questions during a meeting to save replies."
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(responses) { response in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(actionLabel(response.action))
                                    .font(.headline)
                                Spacer()
                                Text(historyDate(milliseconds: response.createdAtMs))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("\(response.provider) / \(response.model) / \(response.latencyMs) ms")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(response.suggestions) { suggestion in
                                VStack(alignment: .leading, spacing: 5) {
                                    Label(suggestion.title, systemImage: suggestion.iconName.isEmpty ? "quote.bubble" : suggestion.iconName)
                                        .font(.callout.weight(.semibold))
                                    Text(suggestion.detail)
                                        .font(.body)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(.bottom, 4)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct HistoryNotes: View {
    let notes: [MeetingNoteResponse]

    var body: some View {
        if notes.isEmpty {
            HistoryEmptyState(icon: "note.text", title: "No meeting notes", detail: "Meeting notes are saved from the latest automatic summary.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { pair in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pair.element.title)
                                .font(.headline)
                            Text(pair.element.detail)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct HistoryActions: View {
    let actions: [MeetingActionResponse]

    var body: some View {
        if actions.isEmpty {
            HistoryEmptyState(icon: "checklist", title: "No next actions", detail: "Explicit TODOs from meeting notes appear here.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(actions.enumerated()), id: \.offset) { pair in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "circle")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 3)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(pair.element.title)
                                    .font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("Owner: \(pair.element.owner.isEmpty ? "Unassigned" : pair.element.owner) / State: \(pair.element.state)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct HistoryMetric: View {
    let icon: String
    let value: String

    var body: some View {
        Label(value, systemImage: icon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
    }
}

struct HistoryEmptyState: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func actionLabel(_ action: String) -> String {
    switch action {
    case "what_should_i_say":
        return "What should I say?"
    case "follow_up_questions":
        return "Follow-up questions"
    case "chat":
        return "Chat"
    default:
        return action.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func providerLabel(_ meeting: MeetingHistorySummary) -> String {
    if !meeting.assistantProvider.isEmpty {
        return "\(meeting.assistantProvider) / \(meeting.assistantModel)"
    }
    if !meeting.sttProvider.isEmpty {
        return "\(meeting.sttProvider) / \(meeting.sttModel)"
    }
    return "Provider unavailable"
}

func historyDate(milliseconds: Int?) -> String {
    guard let milliseconds, milliseconds > 0 else {
        return "Unknown time"
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000))
}

func historyDuration(milliseconds: Int) -> String {
    let totalSeconds = max(0, milliseconds / 1_000)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}
