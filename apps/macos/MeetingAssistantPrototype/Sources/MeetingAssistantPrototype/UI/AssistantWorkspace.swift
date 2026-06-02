import SwiftUI

struct AssistantWorkspace: View {
    let modeLabel: String
    let statusLabel: String
    let providerOptions: [AssistantProviderDescriptor]
    let selectedProviderID: Binding<String>
    let model: Binding<String>
    let modelOptions: [String]
    let thinking: Binding<String>
    let drafts: [AssistantDraft]
    let notes: [MeetingNoteDraft]
    let actions: [MeetingActionDraft]
    let autoSummaryRemainingSeconds: Int
    let autoSummaryProgress: Double
    let autoSummaryStatusLabel: String
    let autoSummaryIsGenerating: Bool
    let refreshProvidersAction: () -> Void
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

                    Text(statusLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                AssistantSettingsBar(
                    providerOptions: providerOptions,
                    selectedProviderID: selectedProviderID,
                    model: model,
                    modelOptions: modelOptions,
                    thinking: thinking,
                    refreshAction: refreshProvidersAction
                )

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

            NotesWorkspace(
                notes: notes,
                actions: actions,
                autoSummaryRemainingSeconds: autoSummaryRemainingSeconds,
                autoSummaryProgress: autoSummaryProgress,
                autoSummaryStatusLabel: autoSummaryStatusLabel,
                autoSummaryIsGenerating: autoSummaryIsGenerating
            )
        }
    }
}

private struct AssistantSettingsBar: View {
    let providerOptions: [AssistantProviderDescriptor]
    let selectedProviderID: Binding<String>
    let model: Binding<String>
    let modelOptions: [String]
    let thinking: Binding<String>
    let refreshAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Picker("Provider", selection: selectedProviderID) {
                    ForEach(providerOptions) { provider in
                        Text(providerLabel(provider))
                            .tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)

                Picker("Thinking", selection: thinking) {
                    ForEach(AssistantThinking.allCases) { item in
                        Text(item.label)
                            .tag(item.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 106)

                Button(action: refreshAction) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh providers")
            }

            HStack(spacing: 8) {
                TextField("Model", text: model)
                    .textFieldStyle(.roundedBorder)

                Menu {
                    if modelOptions.isEmpty {
                        Text("No models")
                    } else {
                        ForEach(modelOptions, id: \.self) { option in
                            Button(option) {
                                model.wrappedValue = option
                            }
                        }
                    }
                } label: {
                    Image(systemName: "cube.box")
                }
                .menuStyle(.borderlessButton)
                .help("Model options")
            }
        }
    }

    private func providerLabel(_ provider: AssistantProviderDescriptor) -> String {
        provider.available ? provider.label : "\(provider.label) unavailable"
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
    let autoSummaryRemainingSeconds: Int
    let autoSummaryProgress: Double
    let autoSummaryStatusLabel: String
    let autoSummaryIsGenerating: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Meeting Notes")
                    .font(.headline)
                Spacer()
                AutoSummaryCountdownView(
                    remainingSeconds: autoSummaryRemainingSeconds,
                    progress: autoSummaryProgress,
                    statusLabel: autoSummaryStatusLabel,
                    isGenerating: autoSummaryIsGenerating
                )
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

private struct AutoSummaryCountdownView: View {
    let remainingSeconds: Int
    let progress: Double
    let statusLabel: String
    let isGenerating: Bool

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 4)

                Circle()
                    .trim(from: 0, to: CGFloat(isGenerating ? 1 : clampedProgress))
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.2), value: clampedProgress)

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                } else {
                    Text("\(remainingSeconds)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Auto summarize")
                    .font(.caption.weight(.semibold))
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 112, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Auto summarize")
        .accessibilityValue(statusLabel)
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}
