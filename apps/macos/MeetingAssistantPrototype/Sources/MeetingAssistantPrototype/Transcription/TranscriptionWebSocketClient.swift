import Foundation

struct TranscriptEvent: Decodable, Equatable {
    let type: String
    let message: String?
    let segmentId: String?
    let source: String?
    let speakerHint: String?
    let startMs: Int?
    let endMs: Int?
    let text: String?
    let revision: Int?
    let isFinal: Bool?
    let confidence: Double?
    let provider: String?
}

final class TranscriptionWebSocketClient {
    var onEvent: ((TranscriptEvent) -> Void)?
    var onError: ((String) -> Void)?

    private let url: URL
    private let session: URLSession
    private let queue = DispatchQueue(label: "MeetingAssistantPrototype.TranscriptionWebSocketClient")
    private let chunkByteCount = PCM16AudioConverter.outputSampleRate * PCM16AudioConverter.sampleWidth / 10
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private var task: URLSessionWebSocketTask?
    private var bufferedAudio = Data()
    private var sessionID = "macos-local"

    init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    func connect() {
        queue.async { [weak self] in
            guard let self, self.task == nil else {
                return
            }

            let task = self.session.webSocketTask(with: self.url)
            self.sessionID = "macos-\(UUID().uuidString.lowercased())"
            self.bufferedAudio.removeAll(keepingCapacity: true)
            self.task = task

            task.resume()
            self.sendSessionStart(on: task)
            self.receiveNext(on: task)
        }
    }

    func disconnect() {
        queue.async { [weak self] in
            guard let self, let task = self.task else {
                return
            }

            self.sendSessionEnd(on: task)
            task.cancel(with: .normalClosure, reason: nil)
            self.task = nil
            self.bufferedAudio.removeAll(keepingCapacity: true)
        }
    }

    func sendAudio(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        queue.async { [weak self] in
            guard let self, let task = self.task else {
                return
            }

            self.bufferedAudio.append(data)

            while self.bufferedAudio.count >= self.chunkByteCount {
                let chunk = self.bufferedAudio.prefix(self.chunkByteCount)
                self.bufferedAudio.removeFirst(self.chunkByteCount)
                self.send(Data(chunk), on: task)
            }
        }
    }

    private func sendSessionStart(on task: URLSessionWebSocketTask) {
        let payload: [String: Any] = [
            "type": "session.start",
            "session_id": sessionID,
            "source": "microphone",
            "sample_rate": PCM16AudioConverter.outputSampleRate,
            "channels": Int(PCM16AudioConverter.outputChannels),
            "sample_width": PCM16AudioConverter.sampleWidth
        ]

        sendJSON(payload, on: task)
    }

    private func sendSessionEnd(on task: URLSessionWebSocketTask) {
        sendJSON(["type": "session.end"], on: task)
    }

    private func sendJSON(_ payload: [String: Any], on task: URLSessionWebSocketTask) {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let text = String(data: data, encoding: .utf8) else {
                return
            }

            task.send(.string(text)) { [weak self] error in
                self?.handleSendError(error, from: task)
            }
        } catch {
            onError?("Encode websocket message failed: \(error.localizedDescription)")
        }
    }

    private func send(_ data: Data, on task: URLSessionWebSocketTask) {
        task.send(.data(data)) { [weak self] error in
            self?.handleSendError(error, from: task)
        }
    }

    private func receiveNext(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else {
                return
            }

            self.queue.async {
                guard self.task === task else {
                    return
                }

                switch result {
                case .failure(let error):
                    self.task = nil
                    self.bufferedAudio.removeAll(keepingCapacity: true)
                    self.onError?("Receive websocket message failed: \(error.localizedDescription)")
                case .success(let message):
                    self.handle(message)
                    self.receiveNext(on: task)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseEvent(Data(text.utf8))
        case .data(let data):
            parseEvent(data)
        @unknown default:
            break
        }
    }

    private func parseEvent(_ data: Data) {
        do {
            let event = try decoder.decode(TranscriptEvent.self, from: data)
            onEvent?(event)
        } catch {
            onError?("Decode transcript event failed: \(error.localizedDescription)")
        }
    }

    private func handleSendError(_ error: Error?, from task: URLSessionWebSocketTask) {
        guard let error else {
            return
        }

        queue.async { [weak self] in
            guard let self, self.task === task else {
                return
            }

            self.task = nil
            self.bufferedAudio.removeAll(keepingCapacity: true)
            self.onError?("Send websocket message failed: \(error.localizedDescription)")
        }
    }
}
