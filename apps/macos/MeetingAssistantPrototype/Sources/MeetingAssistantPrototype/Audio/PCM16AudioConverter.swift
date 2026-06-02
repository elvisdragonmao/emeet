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

        var pcm = [Int16]()
        pcm.reserveCapacity(frameLength)

        for frame in 0..<frameLength {
            let clamped = min(max(samples[frame], -1), 1)
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
