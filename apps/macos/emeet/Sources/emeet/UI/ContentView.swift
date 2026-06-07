import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: CaptureViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            workspace
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            viewModel.requestScreenRecordingPermissionOnLaunch()
        }
        .sheet(
            isPresented: Binding(
                get: { viewModel.meetingHistoryIsPresented },
                set: { presented in
                    if !presented {
                        viewModel.closeMeetingHistory()
                    }
                }
            )
        ) {
            MeetingHistoryView(
                meetings: viewModel.meetingHistory,
                selectedMeetingID: viewModel.selectedMeetingHistoryID,
                record: viewModel.selectedMeetingRecord,
                isLoading: viewModel.meetingHistoryIsLoading,
                message: viewModel.meetingHistoryMessage,
                refreshAction: viewModel.refreshMeetingHistory,
                selectAction: viewModel.selectMeetingHistory,
                closeAction: viewModel.closeMeetingHistory
            )
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                headerTitle
                Spacer()
                statusBadges
                headerActions
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    headerTitle
                    Spacer()
                    headerActions
                }
                statusBadges
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("emeet")
                .font(.system(size: 23, weight: .semibold))
            Text(viewModel.transcriptionEndpointLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusBadges: some View {
        HStack(spacing: 18) {
            StatusBadge(title: "Mic", status: viewModel.microphoneStatus)
            StatusBadge(title: "System", status: viewModel.systemAudioStatus)
            StatusBadge(
                title: "STT",
                status: viewModel.transcriptionStatus,
                detail: viewModel.transcriptionStatusDetailLabel
            )
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.toggleMeeting()
            } label: {
                Label(
                    viewModel.isMeetingActive ? "Stop Meeting" : "Start Meeting",
                    systemImage: viewModel.isMeetingActive ? "stop.fill" : "record.circle"
                )
            }
            .buttonStyle(.borderedProminent)

            Button {
                viewModel.clearCurrentRecords()
            } label: {
                Label("Clear View", systemImage: "xmark.circle")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.openMeetingHistory()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.bordered)

            Button {
                viewModel.exportMeetingRecords()
            } label: {
                Label("Export", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var workspace: some View {
        GeometryReader { proxy in
            if proxy.size.width < 1040 {
                ScrollView {
                    compactWorkspace
                        .padding(18)
                }
            } else {
                regularWorkspace
                    .padding(18)
            }
        }
    }

    private var regularWorkspace: some View {
        HStack(alignment: .top, spacing: 18) {
            sidebar
                .frame(width: 285)

            transcriptPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            assistantPanel
                .frame(width: 360)
        }
    }

    private var compactWorkspace: some View {
        VStack(alignment: .leading, spacing: 18) {
            sidebar
                .frame(maxWidth: .infinity)

            transcriptPanel
                .frame(maxWidth: .infinity, minHeight: 360)

            assistantPanel
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transcriptPanel: some View {
        TranscriptWorkspace(
            status: viewModel.transcriptionStatus,
            countLabel: viewModel.transcriptCountsLabel,
            backendLatencyLabel: viewModel.backendLatencyLabel,
            transcriptionLatencyLabel: viewModel.transcriptionLatencyLabel,
            lines: viewModel.transcriptLines
        )
    }

    private var assistantPanel: some View {
        AssistantWorkspace(
            modeLabel: viewModel.assistantModeLabel,
            statusLabel: viewModel.assistantStatusLabel,
            providerOptions: viewModel.assistantProviderOptions,
            selectedProviderID: Binding(
                get: { viewModel.assistantProviderID },
                set: { viewModel.selectAssistantProvider($0) }
            ),
            model: Binding(
                get: { viewModel.assistantModel },
                set: { viewModel.updateAssistantModel($0) }
            ),
            modelOptions: viewModel.assistantModelOptions,
            thinking: Binding(
                get: { viewModel.assistantThinking },
                set: { viewModel.updateAssistantThinking($0) }
            ),
            drafts: viewModel.assistantDrafts,
            notes: viewModel.noteDrafts,
            actions: viewModel.actionDrafts,
            autoSummaryRemainingSeconds: viewModel.autoSummaryRemainingSeconds,
            autoSummaryProgress: viewModel.autoSummaryProgress,
            autoSummaryStatusLabel: viewModel.autoSummaryStatusLabel,
            autoSummaryIsGenerating: viewModel.autoSummaryIsGenerating,
            quickActionsDisabled: viewModel.isAssistantActionRunning,
            whatShouldISayIsLoading: viewModel.isWhatShouldISayLoading,
            followUpIsLoading: viewModel.isFollowUpQuestionsLoading,
            googleDocsURL: Binding(
                get: { viewModel.googleDocsURL },
                set: { viewModel.updateGoogleDocsURL($0) }
            ),
            googleDocsMode: Binding(
                get: { viewModel.googleDocsMode },
                set: { viewModel.updateGoogleDocsMode($0) }
            ),
            googleDocsStatusLabel: viewModel.googleDocsStatusLabel,
            googleDocsDetailLabel: viewModel.googleDocsDetailLabel,
            googleDocsMessage: viewModel.googleDocsMessage,
            googleDocsPreview: viewModel.googleDocsPreview,
            googleDocsBriefing: viewModel.googleDocsBriefing,
            googleDocsIsConnected: viewModel.googleDocsIsConnected,
            googleDocsIsBusy: viewModel.googleDocsIsBusy,
            googleBrowserMessage: viewModel.googleBrowserMessage,
            googleBrowserSeleniumAvailable: viewModel.googleBrowserSeleniumAvailable,
            googleBrowserSessionActive: viewModel.googleBrowserSessionActive,
            googleBrowserFindText: Binding(
                get: { viewModel.googleBrowserFindText },
                set: { viewModel.updateGoogleBrowserFindText($0) }
            ),
            refreshProvidersAction: viewModel.refreshAssistantProviders,
            whatShouldISayAction: viewModel.prepareWhatShouldISay,
            followUpAction: viewModel.prepareFollowUpQuestions,
            googleAuthAction: viewModel.startGoogleAuth,
            googleConnectAction: viewModel.connectGoogleDoc,
            googleRefreshAction: viewModel.refreshGoogleDocContext,
            googleAppendNotesAction: viewModel.appendMeetingNotesToGoogleDoc,
            googleUpdateLiveNotesAction: viewModel.updateGoogleDocLiveNotes,
            googleBrowserRefreshAction: viewModel.refreshGoogleBrowserStatus,
            googleBrowserOpenAction: viewModel.openGoogleDocInBrowser,
            googleBrowserScrollAction: viewModel.scrollGoogleDocBrowserToBottom,
            googleBrowserFindAction: viewModel.findVisibleTextInGoogleDocBrowser
        )
    }

    private var sidebar: some View {
        VStack(spacing: 14) {
            CompactInputPanel(
                source: .microphone,
                status: viewModel.microphoneStatus,
                level: viewModel.microphoneLevel,
                history: viewModel.microphoneHistory,
                toggleAction: viewModel.toggleMicrophone,
                settingsAction: viewModel.openMicrophoneSettings
            )

            CompactInputPanel(
                source: .systemAudio,
                status: viewModel.systemAudioStatus,
                level: viewModel.systemAudioLevel,
                history: viewModel.systemAudioHistory,
                toggleAction: viewModel.toggleSystemAudio,
                settingsAction: viewModel.openScreenRecordingSettings
            )

            EventLogPanel(events: viewModel.eventLog)
                .frame(maxHeight: .infinity)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CaptureViewModel())
    }
}
