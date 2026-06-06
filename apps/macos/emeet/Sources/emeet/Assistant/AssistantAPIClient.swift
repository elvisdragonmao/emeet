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
    let documentTitle: String
    let documentSummary: String
    let documentSnippets: [String]
    let documentBriefing: String
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

struct GoogleAuthStatusResponse: Decodable, Equatable {
    let ready: Bool
    let clientConfigured: Bool
    let tokenConfigured: Bool
    let dependenciesAvailable: Bool
    let scopes: [String]
}

struct GoogleDocConnectRequest: Encodable {
    let url: String
    let meetingID: String
    let provider: String
    let model: String
    let thinking: String
}

struct GoogleDocMeetingRequest: Encodable {
    let meetingID: String
}

struct GoogleDocAppendRequest: Encodable {
    let meetingID: String
    let text: String
}

struct GoogleDocReplaceTextRequest: Encodable {
    let meetingID: String
    let find: String
    let replace: String
    let occurrence: String
}

struct GoogleDocInsertUnderHeadingRequest: Encodable {
    let meetingID: String
    let heading: String
    let text: String
}

struct GoogleDocRewriteParagraphRequest: Encodable {
    let meetingID: String
    let anchor: String
    let text: String
}

struct GoogleBrowserOpenRequest: Encodable {
    let meetingID: String
    let url: String
}

struct GoogleBrowserMeetingRequest: Encodable {
    let meetingID: String
}

struct GoogleBrowserFindRequest: Encodable {
    let meetingID: String
    let text: String
}

struct GoogleDocMeetingNotesRequest: Encodable {
    let meetingID: String
    let notes: [MeetingNoteContextPayload]
    let actions: [MeetingActionContextPayload]
    let transcript: [AssistantTranscriptLinePayload]
}

struct GoogleDocSnapshotResponse: Decodable, Equatable {
    let connected: Bool?
    let meetingId: String?
    let documentId: String
    let title: String
    let revisionId: String
    let preview: String
    let plainText: String?
    let documentBriefing: String?
    let briefingError: String?
    let snippets: [String]?
    let status: String?
    let message: String?
}

struct GoogleBrowserResponse: Decodable, Equatable {
    let ok: Bool
    let message: String
    let seleniumAvailable: Bool
    let chromedriverAvailable: Bool
    let browserSessionActive: Bool
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

    func fetchGoogleAuthStatus() async throws -> GoogleAuthStatusResponse {
        let (data, response) = try await session.data(from: url(path: "/v1/google/auth/status"))
        try validate(response: response, data: data)
        return try decoder.decode(GoogleAuthStatusResponse.self, from: data)
    }

    func startGoogleAuth() async throws -> GoogleAuthStatusResponse {
        let (data, response) = try await post(path: "/v1/google/auth/start", body: EmptyRequest())
        try validate(response: response, data: data)
        return try decoder.decode(GoogleAuthStatusResponse.self, from: data)
    }

    func connectGoogleDoc(_ request: GoogleDocConnectRequest) async throws -> GoogleDocSnapshotResponse {
        let (data, response) = try await post(path: "/v1/google/docs/connect", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(GoogleDocSnapshotResponse.self, from: data)
    }

    func refreshGoogleDoc(_ request: GoogleDocMeetingRequest) async throws -> GoogleDocSnapshotResponse {
        let (data, response) = try await post(path: "/v1/google/docs/refresh", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(GoogleDocSnapshotResponse.self, from: data)
    }

    func appendMeetingNotesToGoogleDoc(
        _ request: GoogleDocMeetingNotesRequest
    ) async throws -> GoogleDocSnapshotResponse {
        let (data, response) = try await post(path: "/v1/google/docs/append-meeting-notes", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(GoogleDocSnapshotResponse.self, from: data)
    }

    func updateGoogleDocLiveNotes(
        _ request: GoogleDocMeetingNotesRequest
    ) async throws -> GoogleDocSnapshotResponse {
        let (data, response) = try await post(path: "/v1/google/docs/update-live-notes", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(GoogleDocSnapshotResponse.self, from: data)
    }

    func replaceGoogleDocText(_ request: GoogleDocReplaceTextRequest) async throws -> GoogleDocSnapshotResponse {
        let (data, response) = try await post(path: "/v1/google/docs/replace-text", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(GoogleDocSnapshotResponse.self, from: data)
    }

    func insertGoogleDocTextUnderHeading(
        _ request: GoogleDocInsertUnderHeadingRequest
    ) async throws -> GoogleDocSnapshotResponse {
        let (data, response) = try await post(path: "/v1/google/docs/insert-under-heading", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(GoogleDocSnapshotResponse.self, from: data)
    }

    func rewriteGoogleDocParagraph(
        _ request: GoogleDocRewriteParagraphRequest
    ) async throws -> GoogleDocSnapshotResponse {
        let (data, response) = try await post(path: "/v1/google/docs/rewrite-paragraph", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(GoogleDocSnapshotResponse.self, from: data)
    }

    func fetchGoogleBrowserStatus() async throws -> GoogleBrowserResponse {
        let (data, response) = try await session.data(from: url(path: "/v1/google/browser/status"))
        try validate(response: response, data: data)
        return try decoder.decode(GoogleBrowserResponse.self, from: data)
    }

    func openGoogleDocInBrowser(_ request: GoogleBrowserOpenRequest) async throws -> GoogleBrowserResponse {
        let (data, response) = try await post(path: "/v1/google/browser/open", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(GoogleBrowserResponse.self, from: data)
    }

    func scrollGoogleDocBrowserToBottom(
        _ request: GoogleBrowserMeetingRequest
    ) async throws -> GoogleBrowserResponse {
        let (data, response) = try await post(path: "/v1/google/browser/scroll-bottom", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(GoogleBrowserResponse.self, from: data)
    }

    func findVisibleGoogleDocText(_ request: GoogleBrowserFindRequest) async throws -> GoogleBrowserResponse {
        let (data, response) = try await post(path: "/v1/google/browser/find-visible-text", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(GoogleBrowserResponse.self, from: data)
    }

    private func post<T: Encodable>(path: String, body: T) async throws -> (Data, URLResponse) {
        var urlRequest = URLRequest(url: url(path: path))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(body)
        return try await session.data(for: urlRequest)
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

private struct EmptyRequest: Encodable {}
