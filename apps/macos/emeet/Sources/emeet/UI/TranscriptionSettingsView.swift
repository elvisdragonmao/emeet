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
                Section("本機執行環境") {
                    LabeledContent("機器", value: hardwareLabel)
                    LabeledContent("狀態") {
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

                Section("會議逐字稿") {
                    Picker("供應商", selection: selectedProviderID) {
                        ForEach(providers.filter(\.available)) { provider in
                            Text(providerLabel(provider))
                                .tag(provider.id)
                        }
                    }
                    .disabled(isMeetingActive)

                    Picker("模型", selection: selectedModelID) {
                        ForEach(models) { model in
                            Text(modelLabel(model))
                                .tag(model.id)
                        }
                    }
                    .disabled(isMeetingActive || models.isEmpty)

                    Picker("會議語言", selection: selectedLanguageID) {
                        ForEach(languages) { language in
                            Text(language.label)
                                .tag(language.id)
                        }
                    }
                    .disabled(isMeetingActive)
                }

                Section("模型備註") {
                    if let model = models.first(where: { $0.id == selectedModelID.wrappedValue }) {
                        LabeledContent("預估大小", value: sizeLabel(model.estimatedSizeGb))
                        if !model.notes.isEmpty {
                            Text(model.notes.joined(separator: "\n"))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("此供應商目前沒有可用模型。")
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
                Text("應用程式設定")
                    .font(.title3.weight(.semibold))
                Text(isMeetingActive ? "請先停止會議，再變更逐字稿設定。" : "設定會在下一次開始會議時套用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: refreshAction) {
                Label("檢查", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)

            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.bordered)
            .help("關閉")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func providerLabel(_ provider: TranscriptionProviderDescriptor) -> String {
        provider.recommended ? "\(provider.label)（建議）" : provider.label
    }

    private func modelLabel(_ model: TranscriptionModelDescriptor) -> String {
        model.recommended ? "\(model.label)（建議）" : model.label
    }

    private func sizeLabel(_ size: Double) -> String {
        size > 0 ? String(format: "%.1f GB", size) : "依模型而定"
    }
}
