import SwiftUI

struct TranscriptionSettingsView: View {
    let hardwareLabel: String
    let message: String
    let isLoading: Bool
    let isMeetingActive: Bool
    let providers: [TranscriptionProviderDescriptor]
    let selectedProviderID: Binding<String>
    let models: [TranscriptionModelDescriptor]
    let selectedModelID: Binding<String>
    let languages: [TranscriptionLanguageOption]
    let selectedLanguageID: Binding<String>
    let refreshAction: () -> Void
    let closeAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section("Local Runtime") {
                    LabeledContent("Machine", value: hardwareLabel)
                    LabeledContent("Status") {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(message)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Meeting Transcription") {
                    Picker("Provider", selection: selectedProviderID) {
                        ForEach(providers.filter(\.available)) { provider in
                            Text(providerLabel(provider))
                                .tag(provider.id)
                        }
                    }
                    .disabled(isMeetingActive)

                    Picker("Model", selection: selectedModelID) {
                        ForEach(models) { model in
                            Text(modelLabel(model))
                                .tag(model.id)
                        }
                    }
                    .disabled(isMeetingActive || models.isEmpty)

                    Picker("Meeting Language", selection: selectedLanguageID) {
                        ForEach(languages) { language in
                            Text(language.label)
                                .tag(language.id)
                        }
                    }
                    .disabled(isMeetingActive)
                }

                Section("Model Notes") {
                    if let model = models.first(where: { $0.id == selectedModelID.wrappedValue }) {
                        LabeledContent("Estimated size", value: sizeLabel(model.estimatedSizeGb))
                        if !model.notes.isEmpty {
                            Text(model.notes.joined(separator: "\n"))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("No available model for the selected provider.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(16)
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("App Settings")
                    .font(.title3.weight(.semibold))
                Text(isMeetingActive ? "Stop the meeting before changing STT settings." : "Settings apply when the next meeting starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: refreshAction) {
                Label("Check", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func providerLabel(_ provider: TranscriptionProviderDescriptor) -> String {
        provider.recommended ? "\(provider.label) (Recommended)" : provider.label
    }

    private func modelLabel(_ model: TranscriptionModelDescriptor) -> String {
        model.recommended ? "\(model.label) (Recommended)" : model.label
    }

    private func sizeLabel(_ size: Double) -> String {
        size > 0 ? String(format: "%.1f GB", size) : "Varies"
    }
}
