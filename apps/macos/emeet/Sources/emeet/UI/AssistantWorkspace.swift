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
    let quickActionsDisabled: Bool
    let whatShouldISayIsLoading: Bool
    let followUpIsLoading: Bool
    let googleDocsURL: Binding<String>
    let googleDocsStatusLabel: String
    let googleDocsDetailLabel: String
    let googleDocsMessage: String
    let googleDocsIsBusy: Bool
    let refreshProvidersAction: () -> Void
    let whatShouldISayAction: () -> Void
    let followUpAction: () -> Void
    let googleAuthAction: () -> Void
    let googleConnectAction: () -> Void
    let googleBrowserOpenAction: () -> Void

    var body: some View {
        ScrollView {
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
                            isLoading: whatShouldISayIsLoading,
                            isDisabled: quickActionsDisabled,
                            action: whatShouldISayAction
                        )

                        AssistantActionButton(
                            title: "Follow-up questions",
                            iconName: "questionmark.bubble.fill",
                            color: .green,
                            isLoading: followUpIsLoading,
                            isDisabled: quickActionsDisabled,
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

                GoogleDocsWorkspace(
                    url: googleDocsURL,
                    statusLabel: googleDocsStatusLabel,
                    detailLabel: googleDocsDetailLabel,
                    message: googleDocsMessage,
                    isBusy: googleDocsIsBusy,
                    authAction: googleAuthAction,
                    connectAction: googleConnectAction,
                    browserOpenAction: googleBrowserOpenAction
                )

                NotesWorkspace(
                    notes: notes,
                    actions: actions,
                    autoSummaryRemainingSeconds: autoSummaryRemainingSeconds,
                    autoSummaryProgress: autoSummaryProgress,
                    autoSummaryStatusLabel: autoSummaryStatusLabel,
                    autoSummaryIsGenerating: autoSummaryIsGenerating
                )
            }
            .frame(maxWidth: .infinity)
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
    let isLoading: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isDisabled && !isLoading ? .secondary : color)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if isLoading {
                            Text("Thinking")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                        .padding(10)
                }
            }
            .background(buttonBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(isLoading ? 0.75 : 0.35), lineWidth: isLoading ? 1.5 : 1)
            )
            .opacity(isDisabled && !isLoading ? 0.55 : 1)
            .animation(.easeInOut(duration: 0.2), value: isLoading)
            .animation(.easeInOut(duration: 0.2), value: isDisabled)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var buttonBackground: Color {
        isLoading
            ? color.opacity(0.08)
            : Color(nsColor: .textBackgroundColor)
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

private struct GoogleDocsWorkspace: View {
    let url: Binding<String>
    let statusLabel: String
    let detailLabel: String
    let message: String
    let isBusy: Bool
    let authAction: () -> Void
    let connectAction: () -> Void
    let browserOpenAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Google Docs")
                        .font(.headline)
                    Text(detailLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(statusLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                TextField("Google Docs URL", text: url)
                    .textFieldStyle(.roundedBorder)

                Button(action: authAction) {
                    Image(systemName: "person.badge.key")
                }
                .help("Authorize Google Docs")
                .disabled(isBusy)

                Button(action: connectAction) {
                    Image(systemName: "link")
                }
                .help("Connect Google Doc")
                .disabled(isBusy)

                GoogleDocSmallButton(
                    title: "Open",
                    iconName: "safari",
                    disabled: isBusy,
                    action: browserOpenAction
                )
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

private struct GoogleDocSmallButton: View {
    let title: String
    let iconName: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: iconName)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .frame(minWidth: 76)
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
