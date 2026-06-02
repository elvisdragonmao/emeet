import SwiftUI

struct TranscriptWorkspace: View {
    let status: CaptureStatus
    let countLabel: String
    let lines: [TranscriptLine]
    let connectAction: () -> Void
    let disconnectAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Transcript")
                        .font(.title3.weight(.semibold))
                    Text(countLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: connectAction) {
                    Label("Connect", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)

                Button(action: disconnectAction) {
                    Image(systemName: "link.badge.minus")
                }
                .buttonStyle(.bordered)
                .help("Disconnect")
            }

            Divider()

            if lines.isEmpty {
                EmptyTranscriptView(status: status)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(lines) { line in
                            TranscriptLineView(line: line)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .panelStyle()
    }
}

private struct EmptyTranscriptView: View {
    let status: CaptureStatus

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text(status == .running ? "Listening" : "No transcript yet")
                .font(.headline)
            Text(status.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TranscriptLineView: View {
    let line: TranscriptLine

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 6) {
                Circle()
                    .fill(line.isFinal ? Color.blue : Color.orange)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(line.sourceLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(line.isFinal ? .blue : .orange)

                    Text(line.timeRangeLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(line.isFinal ? "Final" : "Partial")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(line.isFinal ? Color.secondary : Color.orange)
                }

                Text(line.text)
                    .font(.body)
                    .foregroundStyle(line.isFinal ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }
}
