import SwiftUI

struct MeetingHistoryView: View {
    let meetings: [MeetingHistorySummary]
    let selectedMeetingID: String
    let record: MeetingHistoryRecordResponse?
    let isLoading: Bool
    let message: String
    let refreshAction: () -> Void
    let selectAction: (MeetingHistorySummary) -> Void
    let renameAction: (String) -> Void
    let exportAction: (MeetingHistoryRecordResponse) -> Void
    let continueAction: (MeetingHistoryRecordResponse) -> Void
    let closeAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 900, idealWidth: 980, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meeting History")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Button(action: refreshAction) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var content: some View {
        HStack(spacing: 0) {
            meetingList
                .frame(width: 300)
            Divider()
            MeetingHistoryDetail(
                record: record,
                isLoading: isLoading,
                renameAction: renameAction,
                exportAction: exportAction,
                continueAction: continueAction
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var meetingList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if meetings.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(isLoading ? "Loading meetings" : "No saved meetings")
                        .font(.headline)
                    Text("Meetings appear here after Start Meeting creates transcript or assistant results.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(meetings) { meeting in
                            MeetingHistoryRow(
                                meeting: meeting,
                                isSelected: meeting.meetingId == selectedMeetingID,
                                action: {
                                    selectAction(meeting)
                                }
                            )
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct MeetingHistoryRow: View {
    let meeting: MeetingHistorySummary
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(meeting.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }

                Text(historyDate(milliseconds: meeting.startedAtMs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    HistoryMetric(icon: "text.quote", value: "\(meeting.transcriptCount)")
                    HistoryMetric(icon: "sparkles", value: "\(meeting.assistantResponseCount)")
                    HistoryMetric(icon: "checklist", value: "\(meeting.actionsCount)")
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
