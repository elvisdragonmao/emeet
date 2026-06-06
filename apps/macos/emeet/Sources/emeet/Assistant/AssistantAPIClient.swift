import Foundation

struct AssistantProviderDescriptor: Decodable, Identifiable, Equatable {
    let id: String
    let label: String
    let kind: String
    let installed: Bool
    let available: Bool
    let models: [String]
    let capabilities: [String]
    let riskLevel: String
    let authMode: String
    let endpoint: String
    let binaryPath: String
    let notes: [String]

    var statusLabel: String {
        available ? "Available" : "Unavailable"
    }
}

struct AssistantProviderDefaults: Decodable, Equatable {
    let provider: String
    let model: String
    let thinking: String
}

struct AssistantProvidersResponse: Decodable, Equatable {
    let defaults: AssistantProviderDefaults
    let providers: [AssistantProviderDescriptor]
}

struct AssistantTranscriptLinePayload: Encodable {
    let source: String
    let sourceLabel: String
    let speakerHint: String
    let speakerID: String
    let speakerLabel: String
    let startMs: Int
    let endMs: Int
    let text: String
    let isFinal: Bool
}

struct MeetingNoteContextPayload: Encodable {
    let title: String
    let detail: String
}

struct MeetingActionContextPayload: Encodable {
    let title: String
    let owner: String
    let state: String
}

struct AssistantRespondRequest: Encodable {
    let action: String
    let meetingID: String
    let provider: String
    let model: String
    let thinking: String
    let transcript: [AssistantTranscriptLinePayload]
    let rollingSummary: String
    let previousNotes: [MeetingNoteContextPayload]
    let previousActions: [MeetingActionContextPayload]
}

struct AssistantRespondResponse: Decodable, Equatable {
    let provider: String
    let model: String
    let thinking: String
    let latencyMs: Int
    let drafts: [AssistantDraftResponse]
    let notes: [MeetingNoteResponse]
    let actions: [MeetingActionResponse]
}

struct AssistantDraftResponse: Decodable, Equatable {
    let title: String
    let detail: String
    let badge: String
    let iconName: String
}

struct MeetingNoteResponse: Decodable, Equatable {
    let title: String
    let detail: String
}

struct MeetingActionResponse: Decodable, Equatable {
    let title: String
    let owner: String
    let state: String
}

final class AssistantAPIClient {
    private let baseURL: URL
    private let session: URLSession
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func fetchProviders() async throws -> AssistantProvidersResponse {
        let (data, response) = try await session.data(from: url(path: "/v1/assistant/providers"))
        try validate(response: response, data: data)
        return try decoder.decode(AssistantProvidersResponse.self, from: data)
    }

    func respond(_ request: AssistantRespondRequest) async throws -> AssistantRespondResponse {
        var urlRequest = URLRequest(url: url(path: "/v1/assistant/respond"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        try validate(response: response, data: data)
        return try decoder.decode(AssistantRespondResponse.self, from: data)
    }

    private func url(path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        return components?.url ?? baseURL.appendingPathComponent(path)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown backend error"
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
