import AVFoundation
import Foundation

final class PCM16AudioConverter {
    static let outputSampleRate = 16_000
    static let outputChannels: AVAudioChannelCount = 1
    static let sampleWidth = 2

    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(outputSampleRate),
        channels: outputChannels,
        interleaved: false
    )!

    private var converter: AVAudioConverter?
    private var inputFormatDescriptor: String?

    func convert(_ inputBuffer: AVAudioPCMBuffer) -> Data? {
        guard inputBuffer.frameLength > 0 else {
            return nil
        }

        let descriptor = formatDescriptor(for: inputBuffer.format)
        if converter == nil || inputFormatDescriptor != descriptor {
            converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat)
            inputFormatDescriptor = descriptor
        }

        guard let converter else {
            return nil
        }

        let ratio = outputFormat.sampleRate / inputBuffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount((Double(inputBuffer.frameLength) * ratio).rounded(.up)) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, conversionError == nil else {
            return nil
        }

        return pcm16Data(from: outputBuffer)
    }

    static func pcm16Data(from samples: [Float]) -> Data? {
        guard !samples.isEmpty else {
            return nil
        }

        return samples.withUnsafeBufferPointer { buffer in
            pcm16Data(from: buffer)
        }
    }

    private func formatDescriptor(for format: AVAudioFormat) -> String {
        [
            String(format.sampleRate),
            String(format.channelCount),
            String(format.commonFormat.rawValue),
            String(format.isInterleaved)
        ].joined(separator: ":")
    }

    private func pcm16Data(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let samples = buffer.floatChannelData?[0] else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return nil
        }

        return Self.pcm16Data(from: UnsafeBufferPointer(start: samples, count: frameLength))
    }

    private static func pcm16Data(from samples: UnsafeBufferPointer<Float>) -> Data {
        var pcm = [Int16]()
        pcm.reserveCapacity(samples.count)

        for sample in samples {
            let clamped = min(max(sample, -1), 1)
            let scaled = clamped < 0
                ? clamped * 32_768
                : clamped * Float(Int16.max)
            pcm.append(Int16(scaled.rounded()).littleEndian)
        }

        return pcm.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                return Data()
            }

            return Data(bytes: baseAddress, count: buffer.count * MemoryLayout<Int16>.size)
        }
    }
}
