import SwiftUI

struct TranscriptWorkspace: View {
    let status: CaptureStatus
    let countLabel: String
    let backendLatencyLabel: String
    let transcriptionLatencyLabel: String
    let lines: [TranscriptLine]

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

                LatencyReadout(title: "Backend", value: backendLatencyLabel)
                LatencyReadout(title: "STT", value: transcriptionLatencyLabel)
                SourceLegend(label: "Self", color: .blue)
                SourceLegend(label: "Speakers", color: .green)
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
                    .fill(sourceColor)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(sourceColor.opacity(0.28))
                    .frame(width: 1)
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(line.sourceLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sourceColor)

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
                    .stroke(sourceColor.opacity(line.isFinal ? 0.55 : 0.9), lineWidth: line.isFinal ? 1 : 1.5)
            )
        }
    }

    private var sourceColor: Color {
        if line.speakerHint == "self" {
            return .blue
        }

        switch line.speakerID {
        case "speaker_1":
            return .green
        case "speaker_2":
            return .orange
        case "speaker_3":
            return .purple
        case "speaker_4":
            return .pink
        default:
            break
        }

        switch line.speakerHint {
        case "other":
            return .green
        default:
            return .purple
        }
    }
}

private struct SourceLegend: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct LatencyReadout: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(value == "--" ? .secondary : .primary)
        }
        .frame(minWidth: 62, alignment: .trailing)
    }
}
