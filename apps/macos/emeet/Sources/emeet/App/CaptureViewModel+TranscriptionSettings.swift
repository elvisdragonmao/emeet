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
                    notes: ["Backend STT options are not loaded yet."],
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
                TranscriptionLanguageOption(id: "auto", label: "Auto detect", notes: "Use model language detection."),
                TranscriptionLanguageOption(id: "zh", label: "Chinese / Mandarin", notes: "Recommended for Taiwan Mandarin meetings."),
                TranscriptionLanguageOption(id: "en", label: "English", notes: "Force English transcription."),
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
        transcriptionOptionsMessage = "Checking local STT runtime..."

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let response = try await self.assistantClient.fetchTranscriptionOptions()
                self.applyTranscriptionOptions(response)
                self.transcriptionOptionsStatus = .running
                self.transcriptionOptionsMessage = "STT runtime ready"
                self.appendLog("STT options loaded for \(response.hardware.cpu).")
            } catch {
                self.transcriptionOptionsStatus = .failed(error.localizedDescription)
                self.transcriptionOptionsMessage = error.localizedDescription
                self.appendLog("STT options failed: \(error.localizedDescription)")
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
