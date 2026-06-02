import AVFoundation
import Foundation

final class MicrophoneCaptureService {
    var onLevel: ((AudioLevel) -> Void)?
    var onAudioChunk: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let pcm16Converter = PCM16AudioConverter()
    private var isRunning = false

    func start() async throws {
        guard !isRunning else {
            return
        }

        let granted = await requestMicrophonePermission()
        guard granted else {
            throw CaptureError.permissionDenied("麥克風權限尚未授權。")
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.onLevel?(AudioLevelAnalyzer.levels(from: buffer))

            if let chunk = self?.pcm16Converter.convert(buffer), !chunk.isEmpty {
                self?.onAudioChunk?(chunk)
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else {
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        onLevel?(.silent)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
