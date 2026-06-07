import SwiftUI

struct TranscriptWorkspace: View {
    let status: CaptureStatus
    let countLabel: String
    let backendLatencyLabel: String
    let transcriptionLatencyLabel: String
    let markers: [TranscriptMarker]
    let lines: [TranscriptLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("即時逐字稿")
                        .font(.title3.weight(.semibold))
                    Text(countLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                LatencyReadout(title: "後端", value: backendLatencyLabel)
                LatencyReadout(title: "辨識", value: transcriptionLatencyLabel)
                SourceLegend(label: "自己", color: .blue)
                SourceLegend(label: "講者", color: .green)
            }

            Divider()

            if lines.isEmpty && markers.isEmpty {
                EmptyTranscriptView(status: status)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(lines) { line in
                            TranscriptLineView(line: line)
                            ForEach(markersAnchored(to: line)) { marker in
                                TranscriptMarkerView(marker: marker)
                            }
                        }

                        ForEach(unplacedMarkers) { marker in
                            TranscriptMarkerView(marker: marker)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .panelStyle()
    }

    private func markersAnchored(to line: TranscriptLine) -> [TranscriptMarker] {
        markers
            .filter { $0.anchorLineID == line.id }
            .sorted { $0.anchorMs < $1.anchorMs }
    }

    private var unplacedMarkers: [TranscriptMarker] {
        let visibleLineIDs = Set(lines.map(\.id))
        return markers
            .filter { marker in
                guard let anchorLineID = marker.anchorLineID else {
                    return true
                }
                return !visibleLineIDs.contains(anchorLineID)
            }
            .sorted { $0.anchorMs < $1.anchorMs }
    }
}

private struct TranscriptMarkerView: View {
    let marker: TranscriptMarker

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 6) {
                Image(systemName: marker.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(markerColor)
                    .frame(width: 18, height: 18)
                Rectangle()
                    .fill(markerColor.opacity(0.28))
                    .frame(width: 1)
            }
            .frame(width: 14)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text("AI 動作")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(markerColor)
                    Text(marker.timeLabel)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(markerColor)
                }

                Text(marker.title)
                    .font(.callout.weight(.semibold))
                if !marker.detail.isEmpty {
                    Text(marker.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(markerColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(markerColor.opacity(0.55), lineWidth: 1)
            )
        }
    }

    private var markerColor: Color {
        switch marker.style {
        case .info:
            return .blue
        case .progress:
            return .orange
        case .success:
            return .green
        case .warning:
            return .yellow
        case .failure:
            return .red
        }
    }

    private var statusLabel: String {
        switch marker.style {
        case .info:
            return "已記錄"
        case .progress:
            return "處理中"
        case .success:
            return "已完成"
        case .warning:
            return "需確認"
        case .failure:
            return "失敗"
        }
    }
}

private struct EmptyTranscriptView: View {
    let status: CaptureStatus

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text(status == .running ? "聆聽中" : "尚無逐字稿")
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

                    Text(line.isFinal ? "完成" : "即時")
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
