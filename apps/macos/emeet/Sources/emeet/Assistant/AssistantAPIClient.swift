import Foundation

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

    func fetchTranscriptionOptions() async throws -> TranscriptionOptionsResponse {
        let (data, response) = try await session.data(from: url(path: "/v1/transcribe/options"))
        try validate(response: response, data: data)
        return try decoder.decode(TranscriptionOptionsResponse.self, from: data)
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

    func appendGoogleDocText(_ request: GoogleDocAppendRequest) async throws -> GoogleDocSnapshotResponse {
        let (data, response) = try await post(path: "/v1/google/docs/append", body: request)
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

    func fetchMeetingHistory(limit: Int = 50) async throws -> MeetingHistoryListResponse {
        let (data, response) = try await session.data(from: url(path: "/v1/meetings", queryItems: [
            URLQueryItem(name: "limit", value: String(limit))
        ]))
        try validate(response: response, data: data)
        return try decoder.decode(MeetingHistoryListResponse.self, from: data)
    }

    func fetchMeetingRecord(meetingID: String) async throws -> MeetingHistoryRecordResponse {
        let (data, response) = try await session.data(from: url(path: "/v1/meetings/\(meetingID)"))
        try validate(response: response, data: data)
        return try decoder.decode(MeetingHistoryRecordResponse.self, from: data)
    }

    func renameMeeting(meetingID: String, title: String) async throws -> MeetingMutationResponse {
        let (data, response) = try await patch(
            path: "/v1/meetings/\(meetingID)",
            body: MeetingRenameRequest(title: title)
        )
        try validate(response: response, data: data)
        return try decoder.decode(MeetingMutationResponse.self, from: data)
    }

    func generateMeetingTitle(
        meetingID: String,
        request: MeetingGenerateTitleRequest
    ) async throws -> MeetingGenerateTitleResponse {
        let (data, response) = try await post(path: "/v1/meetings/\(meetingID)/generate-title", body: request)
        try validate(response: response, data: data)
        return try decoder.decode(MeetingGenerateTitleResponse.self, from: data)
    }

    func exportMeetingMarkdown(meetingID: String) async throws -> String {
        let (data, response) = try await session.data(from: url(path: "/v1/meetings/\(meetingID)/export"))
        try validate(response: response, data: data)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func post<T: Encodable>(path: String, body: T) async throws -> (Data, URLResponse) {
        var urlRequest = URLRequest(url: url(path: path))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(body)
        return try await session.data(for: urlRequest)
    }

    private func patch<T: Encodable>(path: String, body: T) async throws -> (Data, URLResponse) {
        var urlRequest = URLRequest(url: url(path: path))
        urlRequest.httpMethod = "PATCH"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try encoder.encode(body)
        return try await session.data(for: urlRequest)
    }

    private func url(path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
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
