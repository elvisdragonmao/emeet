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
    let googleDocsMode: Binding<GoogleDocsSyncMode>
    let googleDocsStatusLabel: String
    let googleDocsDetailLabel: String
    let googleDocsMessage: String
    let googleDocsPreview: String
    let googleDocsBriefing: String
    let googleDocsIsConnected: Bool
    let googleDocsIsBusy: Bool
    let googleDocsFindText: Binding<String>
    let googleDocsReplaceText: Binding<String>
    let googleDocsReplaceOccurrence: Binding<GoogleDocsReplaceOccurrence>
    let googleDocsInsertHeading: Binding<String>
    let googleDocsInsertText: Binding<String>
    let googleDocsRewriteAnchor: Binding<String>
    let googleDocsRewriteText: Binding<String>
    let googleBrowserMessage: String
    let googleBrowserSeleniumAvailable: Bool
    let googleBrowserSessionActive: Bool
    let googleBrowserFindText: Binding<String>
    let refreshProvidersAction: () -> Void
    let whatShouldISayAction: () -> Void
    let followUpAction: () -> Void
    let googleAuthAction: () -> Void
    let googleConnectAction: () -> Void
    let googleRefreshAction: () -> Void
    let googleAppendNotesAction: () -> Void
    let googleUpdateLiveNotesAction: () -> Void
    let googleApplyReplaceAction: () -> Void
    let googleInsertUnderHeadingAction: () -> Void
    let googleRewriteParagraphAction: () -> Void
    let googleBrowserRefreshAction: () -> Void
    let googleBrowserOpenAction: () -> Void
    let googleBrowserScrollAction: () -> Void
    let googleBrowserFindAction: () -> Void

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
                    mode: googleDocsMode,
                    statusLabel: googleDocsStatusLabel,
                    detailLabel: googleDocsDetailLabel,
                    message: googleDocsMessage,
                    preview: googleDocsPreview,
                    briefing: googleDocsBriefing,
                    isConnected: googleDocsIsConnected,
                    isBusy: googleDocsIsBusy,
                    findText: googleDocsFindText,
                    replaceText: googleDocsReplaceText,
                    occurrence: googleDocsReplaceOccurrence,
                    insertHeading: googleDocsInsertHeading,
                    insertText: googleDocsInsertText,
                    rewriteAnchor: googleDocsRewriteAnchor,
                    rewriteText: googleDocsRewriteText,
                    browserMessage: googleBrowserMessage,
                    browserSeleniumAvailable: googleBrowserSeleniumAvailable,
                    browserSessionActive: googleBrowserSessionActive,
                    browserFindText: googleBrowserFindText,
                    authAction: googleAuthAction,
                    connectAction: googleConnectAction,
                    refreshAction: googleRefreshAction,
                    appendNotesAction: googleAppendNotesAction,
                    updateLiveNotesAction: googleUpdateLiveNotesAction,
                    applyReplaceAction: googleApplyReplaceAction,
                    insertUnderHeadingAction: googleInsertUnderHeadingAction,
                    rewriteParagraphAction: googleRewriteParagraphAction,
                    browserRefreshAction: googleBrowserRefreshAction,
                    browserOpenAction: googleBrowserOpenAction,
                    browserScrollAction: googleBrowserScrollAction,
                    browserFindAction: googleBrowserFindAction
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
    let mode: Binding<GoogleDocsSyncMode>
    let statusLabel: String
    let detailLabel: String
    let message: String
    let preview: String
    let briefing: String
    let isConnected: Bool
    let isBusy: Bool
    let findText: Binding<String>
    let replaceText: Binding<String>
    let occurrence: Binding<GoogleDocsReplaceOccurrence>
    let insertHeading: Binding<String>
    let insertText: Binding<String>
    let rewriteAnchor: Binding<String>
    let rewriteText: Binding<String>
    let browserMessage: String
    let browserSeleniumAvailable: Bool
    let browserSessionActive: Bool
    let browserFindText: Binding<String>
    let authAction: () -> Void
    let connectAction: () -> Void
    let refreshAction: () -> Void
    let appendNotesAction: () -> Void
    let updateLiveNotesAction: () -> Void
    let applyReplaceAction: () -> Void
    let insertUnderHeadingAction: () -> Void
    let rewriteParagraphAction: () -> Void
    let browserRefreshAction: () -> Void
    let browserOpenAction: () -> Void
    let browserScrollAction: () -> Void
    let browserFindAction: () -> Void

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
            }

            Picker("Mode", selection: mode) {
                ForEach(GoogleDocsSyncMode.allCases) { item in
                    Text(item.label)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                GoogleDocSmallButton(
                    title: "Refresh",
                    iconName: "arrow.clockwise",
                    disabled: !isConnected || isBusy,
                    action: refreshAction
                )

                GoogleDocSmallButton(
                    title: "Append",
                    iconName: "text.append",
                    disabled: !isConnected || isBusy,
                    action: appendNotesAction
                )

                GoogleDocSmallButton(
                    title: "Live",
                    iconName: "square.and.pencil",
                    disabled: !isConnected || isBusy,
                    action: updateLiveNotesAction
                )
            }

            if !preview.isEmpty || !briefing.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !briefing.isEmpty {
                        Text("Briefing")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(briefing)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(5)
                    } else if !preview.isEmpty {
                        Text("Preview")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(preview)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            DirectEditPanel(
                findText: findText,
                replaceText: replaceText,
                occurrence: occurrence,
                insertHeading: insertHeading,
                insertText: insertText,
                rewriteAnchor: rewriteAnchor,
                rewriteText: rewriteText,
                isDisabled: !isConnected || isBusy,
                applyAction: applyReplaceAction,
                insertUnderHeadingAction: insertUnderHeadingAction,
                rewriteParagraphAction: rewriteParagraphAction
            )

            BrowserHelperPanel(
                message: browserMessage,
                seleniumAvailable: browserSeleniumAvailable,
                browserSessionActive: browserSessionActive,
                findText: browserFindText,
                isConnected: isConnected,
                isBusy: isBusy,
                refreshAction: browserRefreshAction,
                openAction: browserOpenAction,
                scrollAction: browserScrollAction,
                findAction: browserFindAction
            )

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .panelStyle()
    }
}

private struct BrowserHelperPanel: View {
    let message: String
    let seleniumAvailable: Bool
    let browserSessionActive: Bool
    let findText: Binding<String>
    let isConnected: Bool
    let isBusy: Bool
    let refreshAction: () -> Void
    let openAction: () -> Void
    let scrollAction: () -> Void
    let findAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Browser helper")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: refreshAction) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh browser helper status")
            }

            HStack(spacing: 8) {
                GoogleDocSmallButton(
                    title: "Open",
                    iconName: "safari",
                    disabled: isBusy,
                    action: openAction
                )

                GoogleDocSmallButton(
                    title: "Bottom",
                    iconName: "arrow.down.to.line",
                    disabled: isBusy || !seleniumAvailable || !browserSessionActive,
                    action: scrollAction
                )
            }

            HStack(spacing: 8) {
                TextField("Find visible text", text: findText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isBusy || !seleniumAvailable || !browserSessionActive)

                Button(action: findAction) {
                    Image(systemName: "magnifyingglass")
                }
                .disabled(isBusy || !seleniumAvailable || !browserSessionActive)
                .help("Find visible text in browser")
            }

            Text(statusLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusLine: String {
        if !isConnected {
            return "Connect a doc first. \(message)"
        }
        return message
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
        .frame(maxWidth: .infinity)
    }
}

private struct DirectEditPanel: View {
    let findText: Binding<String>
    let replaceText: Binding<String>
    let occurrence: Binding<GoogleDocsReplaceOccurrence>
    let insertHeading: Binding<String>
    let insertText: Binding<String>
    let rewriteAnchor: Binding<String>
    let rewriteText: Binding<String>
    let isDisabled: Bool
    let applyAction: () -> Void
    let insertUnderHeadingAction: () -> Void
    let rewriteParagraphAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Direct edit")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("Find text", text: findText)
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled)

            TextField("Replace with", text: replaceText)
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled)

            HStack(spacing: 8) {
                Picker("Occurrence", selection: occurrence) {
                    ForEach(GoogleDocsReplaceOccurrence.allCases) { item in
                        Text(item.label)
                            .tag(item)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .disabled(isDisabled)

                Button(action: applyAction) {
                    Label("Apply", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled)
            }

            Divider()

            TextField("Heading", text: insertHeading)
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled)

            TextField("Text to insert under heading", text: insertText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .disabled(isDisabled)

            Button(action: insertUnderHeadingAction) {
                Label("Insert Under Heading", systemImage: "text.insert")
            }
            .buttonStyle(.bordered)
            .disabled(isDisabled)

            Divider()

            TextField("Paragraph anchor text", text: rewriteAnchor)
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled)

            TextField("Replacement paragraph", text: rewriteText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .disabled(isDisabled)

            Button(action: rewriteParagraphAction) {
                Label("Rewrite Paragraph", systemImage: "paragraphsign")
            }
            .buttonStyle(.bordered)
            .disabled(isDisabled)
        }
        .padding(9)
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
