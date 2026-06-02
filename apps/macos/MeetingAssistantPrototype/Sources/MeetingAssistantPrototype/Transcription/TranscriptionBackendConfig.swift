import Foundation

struct TranscriptionBackendConfig {
    let websocketURL: URL

    var displayAddress: String {
        let components = URLComponents(url: websocketURL, resolvingAgainstBaseURL: false)
        if let host = components?.host, let port = components?.port {
            return "\(host):\(port)"
        }

        return websocketURL.absoluteString
    }

    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TranscriptionBackendConfig {
        if let explicitURL = environment["MEETING_BACKEND_WS_URL"],
           let url = URL(string: explicitURL) {
            return TranscriptionBackendConfig(websocketURL: url)
        }

        let host = environment["MEETING_BACKEND_HOST"] ?? "127.0.0.1"
        let port = environment["MEETING_BACKEND_PORT"] ?? "8765"
        let url = URL(string: "ws://\(host):\(port)/v1/transcribe/ws")!
        return TranscriptionBackendConfig(websocketURL: url)
    }
}
