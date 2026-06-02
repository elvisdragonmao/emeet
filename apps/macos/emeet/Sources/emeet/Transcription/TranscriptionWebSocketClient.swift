import Foundation

struct TranscriptEvent: Decodable, Equatable {
    let type: String
    let message: String?
    let pingId: String?
    let clientSentAtMs: Int?
    let serverSentAtMs: Int?
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
    var onBackendLatency: ((Int) -> Void)?
    var onTranscriptionLatency: ((Int) -> Void)?
    var onError: ((String) -> Void)?

    private let url: URL
    private let source: String
    private let session: URLSession
    private let queue = DispatchQueue(label: "emeet.TranscriptionWebSocketClient")
    private let chunkByteCount = PCM16AudioConverter.outputSampleRate * PCM16AudioConverter.sampleWidth / 10
    private let heartbeatInterval: TimeInterval = 5
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private var task: URLSessionWebSocketTask?
    private var heartbeatTimer: DispatchSourceTimer?
    private var pendingPings: [String: DispatchTime] = [:]
    private var bufferedAudio = Data()
    private var audioTimelineStartNanoseconds: UInt64?
    private var sessionID = "macos-local"

    init(url: URL, source: String = "microphone", session: URLSession = .shared) {
        self.url = url
        self.source = source
        self.session = session
    }

    func connect() {
        queue.async { [weak self] in
            guard let self, self.task == nil else {
                return
            }

            let task = self.session.webSocketTask(with: self.url)
            self.sessionID = "macos-\(self.source)-\(UUID().uuidString.lowercased())"
            self.bufferedAudio.removeAll(keepingCapacity: true)
            self.pendingPings.removeAll(keepingCapacity: true)
            self.audioTimelineStartNanoseconds = nil
            self.task = task

            task.resume()
            self.sendSessionStart(on: task)
            self.startHeartbeat(on: task)
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
            self.stopHeartbeat()
            self.bufferedAudio.removeAll(keepingCapacity: true)
            self.audioTimelineStartNanoseconds = nil
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
                let chunkData = Data(chunk)
                self.noteAudioChunkSent(chunkData)
                self.send(chunkData, on: task)
            }
        }
    }

    private func startHeartbeat(on task: URLSessionWebSocketTask) {
        stopHeartbeat()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: heartbeatInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.task === task else {
                return
            }

            self.sendPing(on: task)
        }

        heartbeatTimer = timer
        timer.resume()
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        pendingPings.removeAll(keepingCapacity: true)
    }

    private func sendPing(on task: URLSessionWebSocketTask) {
        pruneExpiredPings()

        let pingID = UUID().uuidString.lowercased()
        pendingPings[pingID] = .now()
        sendJSON(
            [
                "type": "client.ping",
                "ping_id": pingID,
                "client_sent_at_ms": Self.currentEpochMilliseconds()
            ],
            on: task
        )
    }

    private func sendSessionStart(on task: URLSessionWebSocketTask) {
        let payload: [String: Any] = [
            "type": "session.start",
            "session_id": sessionID,
            "source": source,
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
                    self.stopHeartbeat()
                    self.bufferedAudio.removeAll(keepingCapacity: true)
                    self.audioTimelineStartNanoseconds = nil
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
            if event.type == "server.pong" {
                handlePong(event)
                return
            }

            handleTranscriptionLatency(event)
            onEvent?(event)
        } catch {
            onError?("Decode transcript event failed: \(error.localizedDescription)")
        }
    }

    private func handlePong(_ event: TranscriptEvent) {
        guard let pingID = event.pingId,
              let startedAt = pendingPings.removeValue(forKey: pingID) else {
            return
        }

        let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - startedAt.uptimeNanoseconds
        onBackendLatency?(Int(elapsedNanoseconds / 1_000_000))
    }

    private func handleTranscriptionLatency(_ event: TranscriptEvent) {
        guard event.type == "transcript.partial" || event.type == "transcript.final",
              let endMs = event.endMs,
              let audioTimelineStartNanoseconds else {
            return
        }

        let audioEndNanoseconds = audioTimelineStartNanoseconds + UInt64(max(0, endMs)) * 1_000_000
        let now = DispatchTime.now().uptimeNanoseconds
        let latencyNanoseconds = now > audioEndNanoseconds ? now - audioEndNanoseconds : 0
        onTranscriptionLatency?(Int(latencyNanoseconds / 1_000_000))
    }

    private func noteAudioChunkSent(_ chunk: Data) {
        guard audioTimelineStartNanoseconds == nil else {
            return
        }

        let bytesPerSecond = PCM16AudioConverter.outputSampleRate * PCM16AudioConverter.sampleWidth
        let chunkDurationNanoseconds = UInt64(Double(chunk.count) / Double(bytesPerSecond) * 1_000_000_000)
        let now = DispatchTime.now().uptimeNanoseconds
        audioTimelineStartNanoseconds = now > chunkDurationNanoseconds ? now - chunkDurationNanoseconds : now
    }

    private func pruneExpiredPings() {
        let now = DispatchTime.now().uptimeNanoseconds
        let timeoutNanoseconds: UInt64 = 30_000_000_000
        pendingPings = pendingPings.filter { _, startedAt in
            now >= startedAt.uptimeNanoseconds
                && now - startedAt.uptimeNanoseconds < timeoutNanoseconds
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
            self.stopHeartbeat()
            self.bufferedAudio.removeAll(keepingCapacity: true)
            self.audioTimelineStartNanoseconds = nil
            self.onError?("Send websocket message failed: \(error.localizedDescription)")
        }
    }

    private static func currentEpochMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1_000)
    }
}
