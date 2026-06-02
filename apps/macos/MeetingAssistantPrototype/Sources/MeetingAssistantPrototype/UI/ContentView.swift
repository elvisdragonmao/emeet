import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: CaptureViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mainContent
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meeting Assistant Capture Test")
                    .font(.system(size: 22, weight: .semibold))
                Text("Verify microphone, ScreenCaptureKit system audio, and local live transcription.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.startAll()
            } label: {
                Label("Start All", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                viewModel.connectTranscription()
            } label: {
                Label("Connect STT", systemImage: "text.bubble.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                viewModel.stopAll()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(24)
    }

    private var mainContent: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 18) {
                CaptureSourcePanel(
                    source: .microphone,
                    status: viewModel.microphoneStatus,
                    level: viewModel.microphoneLevel,
                    history: viewModel.microphoneHistory,
                    primaryAction: viewModel.startMicrophone,
                    stopAction: viewModel.stopMicrophone,
                    settingsAction: viewModel.openMicrophoneSettings,
                    note: "對著麥克風說話，RMS 和波形應該會立即變化。"
                )

                CaptureSourcePanel(
                    source: .systemAudio,
                    status: viewModel.systemAudioStatus,
                    level: viewModel.systemAudioLevel,
                    history: viewModel.systemAudioHistory,
                    primaryAction: viewModel.startSystemAudio,
                    stopAction: viewModel.stopSystemAudio,
                    settingsAction: viewModel.openScreenRecordingSettings,
                    note: "播放 YouTube、音樂或會議聲音來測試；第一次授權螢幕錄製後可能要重開 App。"
                )
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 18) {
                TranscriptionPanel(
                    status: viewModel.transcriptionStatus,
                    lines: viewModel.transcriptLines,
                    connectAction: viewModel.connectTranscription,
                    disconnectAction: viewModel.disconnectTranscription
                )

                EventLogPanel(events: viewModel.eventLog)
            }
            .frame(width: 360)
        }
        .padding(24)
    }
}

private struct CaptureSourcePanel: View {
    let source: CaptureSource
    let status: CaptureStatus
    let level: AudioLevel
    let history: [Float]
    let primaryAction: () -> Void
    let stopAction: () -> Void
    let settingsAction: () -> Void
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: source.iconName)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(statusColor, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title)
                        .font(.headline)
                    Text(source.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusPill(status: status, color: statusColor)
            }

            WaveformView(samples: history, tint: statusColor)
                .frame(height: 112)

            HStack(spacing: 14) {
                LevelReadout(title: "RMS", value: level.rms)
                LevelReadout(title: "Peak", value: level.peak)
            }

            HStack(spacing: 10) {
                Button(action: primaryAction) {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(action: stopAction) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)

                Button(action: settingsAction) {
                    Label("Permission", systemImage: "gear")
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch status {
        case .idle:
            return .gray
        case .starting:
            return .orange
        case .running:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct StatusPill: View {
    let status: CaptureStatus
    let color: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(status.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(status.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 230, alignment: .trailing)
        }
    }
}

private struct WaveformView: View {
    let samples: [Float]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let midY = size.height / 2
                let count = max(samples.count, 1)
                let step = size.width / CGFloat(count)

                var centerLine = Path()
                centerLine.move(to: CGPoint(x: 0, y: midY))
                centerLine.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(centerLine, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1)

                var path = Path()
                for index in samples.indices {
                    let x = CGFloat(index) * step
                    let normalized = CGFloat(min(max(samples[index] * 5.0, 0), 1))
                    let height = max(2, normalized * size.height * 0.88)
                    let rect = CGRect(
                        x: x,
                        y: midY - height / 2,
                        width: max(2, step * 0.62),
                        height: height
                    )
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: 2, height: 2))
                }

                context.fill(path, with: .color(tint.opacity(0.82)))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct LevelReadout: View {
    let title: String
    let value: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(3)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(min(max(value * 4.0, 0), 1)))
                .progressViewStyle(.linear)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TranscriptionPanel: View {
    let status: CaptureStatus
    let lines: [TranscriptLine]
    let connectAction: () -> Void
    let disconnectAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(statusColor, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Transcript")
                        .font(.headline)
                    Text("Local websocket STT")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusPill(status: status, color: statusColor)
            }

            HStack(spacing: 10) {
                Button(action: connectAction) {
                    Label("Connect", systemImage: "link")
                }
                .buttonStyle(.borderedProminent)

                Button(action: disconnectAction) {
                    Label("Disconnect", systemImage: "link.badge.minus")
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            Divider()

            if lines.isEmpty {
                Text("啟動 backend 後按 Connect STT，對著麥克風說話，逐字稿會顯示在這裡。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(lines) { line in
                            TranscriptLineView(line: line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 180, maxHeight: 300)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch status {
        case .idle:
            return .gray
        case .starting:
            return .orange
        case .running:
            return .blue
        case .failed:
            return .red
        }
    }
}

private struct TranscriptLineView: View {
    let line: TranscriptLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                .font(.callout)
                .foregroundStyle(line.isFinal ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct EventLogPanel: View {
    let events: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                Text("Event Log")
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(events, id: \.self) { event in
                    Text(event)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CaptureViewModel())
    }
}
