import Foundation

@MainActor
extension CaptureViewModel {
    var transcriptionProviderOptions: [TranscriptionProviderDescriptor] {
        transcriptionProviders.isEmpty
            ? [
                TranscriptionProviderDescriptor(
                    id: "mlx-whisper",
                    label: "MLX Whisper",
                    installed: false,
                    available: false,
                    recommended: true,
                    notes: ["後端 STT 選項尚未載入。"],
                    models: []
                )
            ]
            : transcriptionProviders
    }

    var transcriptionModelOptions: [TranscriptionModelDescriptor] {
        transcriptionProviderOptions
            .first(where: { $0.id == transcriptionProviderID })?
            .models
            .filter(\.available) ?? []
    }

    var transcriptionLanguageOptions: [TranscriptionLanguageOption] {
        transcriptionLanguages.isEmpty
            ? [
                TranscriptionLanguageOption(id: "auto", label: "自動偵測", notes: "使用模型語言偵測。"),
                TranscriptionLanguageOption(id: "zh", label: "中文 / 華語", notes: "建議用於台灣華語會議。"),
                TranscriptionLanguageOption(id: "en", label: "英文", notes: "強制使用英文逐字稿。"),
            ]
            : transcriptionLanguages
    }

    var transcriptionSettingsSummary: String {
        let languageLabel = transcriptionLanguageOptions.first(where: { $0.id == transcriptionLanguage })?.label
            ?? transcriptionLanguage
        return "\(transcriptionProviderID) / \(transcriptionModel) / \(languageLabel)"
    }

    func openTranscriptionSettings() {
        transcriptionSettingsIsPresented = true
        refreshTranscriptionOptions()
    }

    func closeTranscriptionSettings() {
        transcriptionSettingsIsPresented = false
    }

    func refreshTranscriptionOptions() {
        transcriptionOptionsStatus = .starting
        transcriptionOptionsMessage = "正在檢查本機 STT 執行環境..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let response = try await self.assistantClient.fetchTranscriptionOptions()
                self.applyTranscriptionOptions(response)
                self.transcriptionOptionsStatus = .running
                self.transcriptionOptionsMessage = "STT 執行環境就緒"
                self.appendLog("STT 選項已載入：\(response.hardware.cpu)。")
            } catch {
                self.transcriptionOptionsStatus = .failed(error.localizedDescription)
                self.transcriptionOptionsMessage = error.localizedDescription
                self.appendLog("STT 選項載入失敗：\(error.localizedDescription)")
            }
        }
    }

    func selectTranscriptionProvider(_ providerID: String) {
        transcriptionProviderID = providerID
        if let model = transcriptionProviderOptions
            .first(where: { $0.id == providerID })?
            .models
            .first(where: { $0.available && $0.recommended })
            ?? transcriptionProviderOptions
                .first(where: { $0.id == providerID })?
                .models
                .first(where: \.available) {
            transcriptionModel = model.id
            if model.languageHint != "auto" {
                transcriptionLanguage = model.languageHint
            }
        }
    }

    func updateTranscriptionModel(_ modelID: String) {
        transcriptionModel = modelID
        if let model = transcriptionModelOptions.first(where: { $0.id == modelID }),
           model.languageHint != "auto" {
            transcriptionLanguage = model.languageHint
        }
    }

    func updateTranscriptionLanguage(_ languageID: String) {
        transcriptionLanguage = languageID
    }

    func applyTranscriptionOptions(_ response: TranscriptionOptionsResponse) {
        transcriptionProviders = response.providers
        transcriptionLanguages = response.languages
        transcriptionHardwareLabel = "\(response.hardware.cpu) / \(String(format: "%.1f", response.hardware.memoryGb)) GB RAM"

        let currentProvider = response.providers.first { $0.id == transcriptionProviderID && $0.available }
        let defaultProvider = response.providers.first { $0.id == response.defaults.provider && $0.available }
        let recommendedProvider = response.providers.first { $0.available && $0.recommended }
        let fallbackProvider = response.providers.first { $0.available }
        let provider = currentProvider ?? defaultProvider ?? recommendedProvider ?? fallbackProvider

        if let provider {
            transcriptionProviderID = provider.id
            let currentModel = provider.models.first { $0.id == transcriptionModel && $0.available }
            let defaultModel = provider.models.first { $0.id == response.defaults.model && $0.available }
            let recommendedModel = provider.models.first { $0.available && $0.recommended }
            let fallbackModel = provider.models.first { $0.available }

            if let model = currentModel ?? defaultModel ?? recommendedModel ?? fallbackModel {
                transcriptionModel = model.id
                if model.languageHint != "auto" {
                    transcriptionLanguage = model.languageHint
                }
            }
        }

        let languageIDs = Set(response.languages.map(\.id))
        if languageIDs.contains(response.defaults.language), transcriptionLanguage.isEmpty {
            transcriptionLanguage = response.defaults.language
        }
        if !languageIDs.contains(transcriptionLanguage) {
            transcriptionLanguage = languageIDs.contains("auto") ? "auto" : response.languages.first?.id ?? "auto"
        }
    }

}
