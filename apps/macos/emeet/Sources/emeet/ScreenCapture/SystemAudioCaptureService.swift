import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCaptureService: NSObject {
    var onLevel: ((AudioLevel) -> Void)?
    var onAudioChunk: ((Data) -> Void)?
    var onError: ((String) -> Void)?

    private let sampleQueue = DispatchQueue(label: "emeet.SystemAudioCapture")
    private let pcm16Converter = SampleBufferPCM16AudioConverter()
    private var stream: SCStream?
    private var isRunning = false

    func start() async throws {
        guard !isRunning else {
            return
        }

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw CaptureError.permissionDenied("螢幕錄製權限尚未授權。授權後通常需要重新啟動 App。")
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.excludesCurrentProcessAudio = false

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try await stream.startCapture()

        self.stream = stream
        isRunning = true
    }

    func stop() async {
        guard let stream else {
            return
        }

        do {
            try await stream.stopCapture()
        } catch {
            onError?("停止系統音訊擷取失敗：\(error.localizedDescription)")
        }

        self.stream = nil
        isRunning = false
        onLevel?(.silent)
    }
}

extension SystemAudioCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else {
            return
        }

        onLevel?(AudioLevelAnalyzer.levels(from: sampleBuffer))

        if let chunk = pcm16Converter.convert(sampleBuffer), !chunk.isEmpty {
            onAudioChunk?(chunk)
        }
    }
}

extension SystemAudioCaptureService: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
        onError?("ScreenCaptureKit 串流已停止：\(error.localizedDescription)")
    }
}
