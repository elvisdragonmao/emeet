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
        .task {
            viewModel.requestScreenRecordingPermissionOnLaunch()
        }
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
            StatusBadge(
                title: "STT",
                status: viewModel.transcriptionStatus,
                detail: viewModel.transcriptionStatusDetailLabel
            )

            Button {
                viewModel.startAll()
            } label: {
                Label("Start Meeting", systemImage: "record.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                viewModel.clearCurrentRecords()
            } label: {
                Label("Delete Records", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                viewModel.exportMeetingRecords()
            } label: {
                Label("Export", systemImage: "square.and.arrow.down")
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
                backendLatencyLabel: viewModel.backendLatencyLabel,
                transcriptionLatencyLabel: viewModel.transcriptionLatencyLabel,
                lines: viewModel.transcriptLines
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
                refreshProvidersAction: viewModel.refreshAssistantProviders,
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(CaptureViewModel())
    }
}
