import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: CaptureViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            workspace
        }
        .frame(minWidth: 1180, minHeight: 760)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Meeting Assistant")
                    .font(.system(size: 23, weight: .semibold))
                Text(viewModel.transcriptionEndpointLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusBadge(title: "Mic", status: viewModel.microphoneStatus)
            StatusBadge(title: "System", status: viewModel.systemAudioStatus)
            StatusBadge(title: "STT", status: viewModel.transcriptionStatus)

            Button {
                viewModel.startAll()
            } label: {
                Label("Start Meeting", systemImage: "record.circle")
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
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var workspace: some View {
        HStack(alignment: .top, spacing: 18) {
            sidebar
                .frame(width: 285)

            TranscriptWorkspace(
                status: viewModel.transcriptionStatus,
                countLabel: viewModel.transcriptCountsLabel,
                lines: viewModel.transcriptLines,
                connectAction: viewModel.connectTranscription,
                disconnectAction: viewModel.disconnectTranscription
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AssistantWorkspace(
                modeLabel: viewModel.assistantModeLabel,
                drafts: viewModel.assistantDrafts,
                notes: viewModel.noteDrafts,
                actions: viewModel.actionDrafts,
                whatShouldISayAction: viewModel.prepareWhatShouldISay,
                followUpAction: viewModel.prepareFollowUpQuestions
            )
            .frame(width: 360)
        }
        .padding(18)
    }

    private var sidebar: some View {
        VStack(spacing: 14) {
            CompactInputPanel(
                source: .microphone,
                status: viewModel.microphoneStatus,
                level: viewModel.microphoneLevel,
                history: viewModel.microphoneHistory,
                startAction: viewModel.startMicrophone,
                stopAction: viewModel.stopMicrophone,
                settingsAction: viewModel.openMicrophoneSettings
            )

            CompactInputPanel(
                source: .systemAudio,
                status: viewModel.systemAudioStatus,
                level: viewModel.systemAudioLevel,
                history: viewModel.systemAudioHistory,
                startAction: viewModel.startSystemAudio,
                stopAction: viewModel.stopSystemAudio,
                settingsAction: viewModel.openScreenRecordingSettings
            )

            EventLogPanel(events: viewModel.eventLog)
                .frame(maxHeight: .infinity)
        }
    }
}

private struct StatusBadge: View {
    let title: String
    let status: CaptureStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption.weight(.semibold))
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var color: Color {
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

private struct CompactInputPanel: View {
    let source: CaptureSource
    let status: CaptureStatus
    let level: AudioLevel
    let history: [Float]
    let startAction: () -> Void
    let stopAction: () -> Void
    let settingsAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: source.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(statusColor, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                    Text(source.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            WaveformView(samples: history, tint: statusColor)
                .frame(height: 74)

            HStack(spacing: 10) {
                LevelMeter(title: "RMS", value: level.rms)
                LevelMeter(title: "Peak", value: level.peak)
            }

            HStack(spacing: 8) {
                Button(action: startAction) {
                    Image(systemName: "play.fill")
                }
                .help("Start")

                Button(action: stopAction) {
                    Image(systemName: "stop.fill")
                }
                .help("Stop")

                Button(action: settingsAction) {
                    Image(systemName: "gear")
                }
                .help("Permission")

                Spacer()

                Text(status.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
        }
        .panelStyle()
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

private struct TranscriptWorkspace: View {
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

private struct AssistantWorkspace: View {
    let modeLabel: String
    let drafts: [AssistantDraft]
    let notes: [MeetingNoteDraft]
    let actions: [MeetingActionDraft]
    let whatShouldISayAction: () -> Void
    let followUpAction: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Assistant")
                            .font(.title3.weight(.semibold))
                        Text(modeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(spacing: 10) {
                    AssistantActionButton(
                        title: "What should I say?",
                        iconName: "quote.bubble.fill",
                        color: .blue,
                        action: whatShouldISayAction
                    )

                    AssistantActionButton(
                        title: "Follow-up questions",
                        iconName: "questionmark.bubble.fill",
                        color: .green,
                        action: followUpAction
                    )
                }

                VStack(spacing: 10) {
                    ForEach(drafts) { draft in
                        AssistantDraftView(draft: draft)
                    }
                }
            }
            .panelStyle()

            NotesWorkspace(notes: notes, actions: actions)
        }
    }
}

private struct AssistantActionButton: View {
    let title: String
    let iconName: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AssistantDraftView: View {
    let draft: AssistantDraft

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: draft.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(draft.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(draft.badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(draft.detail)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct NotesWorkspace: View {
    let notes: [MeetingNoteDraft]
    let actions: [MeetingActionDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Meeting Notes")
                    .font(.headline)
                Spacer()
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }

            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(note.detail)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Text("Next Actions")
                    .font(.headline)
                Spacer()
                Image(systemName: "checklist")
                    .foregroundStyle(.secondary)
            }

            ForEach(actions) { item in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.callout.weight(.medium))
                        Text("\(item.owner) · \(item.state)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .panelStyle()
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

private struct WaveformView: View {
    let samples: [Float]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let midY = size.height / 2
                let count = max(samples.count, 1)
                let step = size.width / CGFloat(count)

                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: midY))
                baseline.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(baseline, with: .color(Color(nsColor: .separatorColor)), lineWidth: 1)

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

private struct LevelMeter: View {
    let title: String
    let value: Float

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(2)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(min(max(value * 4.0, 0), 1)))
                .progressViewStyle(.linear)
        }
    }
}

private struct EventLogPanel: View {
    let events: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Event Log")
                    .font(.headline)
                Spacer()
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(events, id: \.self) { event in
                        Text(event)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .panelStyle()
    }
}

private extension View {
    func panelStyle() -> some View {
        padding(14)
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
