import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

struct AudioLevel: Equatable {
    var rms: Float
    var peak: Float

    static let silent = AudioLevel(rms: 0, peak: 0)
}

enum AudioLevelAnalyzer {
    static func levels(from buffer: AVAudioPCMBuffer) -> AudioLevel {
        guard let channels = buffer.floatChannelData else {
            return .silent
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return .silent
        }

        var sumSquares: Float = 0
        var peak: Float = 0
        var sampleCount = 0

        for channel in 0..<channelCount {
            let samples = channels[channel]
            for frame in 0..<frameLength {
                let sample = samples[frame]
                sumSquares += sample * sample
                peak = max(peak, abs(sample))
                sampleCount += 1
            }
        }

        return normalizedLevel(sumSquares: sumSquares, peak: peak, sampleCount: sampleCount)
    }

    static func levels(from sampleBuffer: CMSampleBuffer) -> AudioLevel {
        guard CMSampleBufferIsValid(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return .silent
        }

        let streamDescription = streamDescriptionPointer.pointee
        let maxBuffers = max(1, Int(streamDescription.mChannelsPerFrame))
        let audioBufferListSize = audioBufferListByteCount(maximumBuffers: maxBuffers)
        let audioBufferList = allocateAudioBufferList(maximumBuffers: maxBuffers)
        defer {
            audioBufferList.unsafeMutablePointer.deallocate()
        }

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList.unsafeMutablePointer,
            bufferListSize: audioBufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard status == noErr else {
            return .silent
        }

        return levels(from: audioBufferList, streamDescription: streamDescription)
    }

    private static func audioBufferListByteCount(maximumBuffers: Int) -> Int {
        let bufferCount = max(1, maximumBuffers)
        return MemoryLayout<AudioBufferList>.size
            + MemoryLayout<AudioBuffer>.size * (bufferCount - 1)
    }

    private static func allocateAudioBufferList(maximumBuffers: Int) -> UnsafeMutableAudioBufferListPointer {
        let bufferCount = max(1, maximumBuffers)
        let audioBufferListSize = audioBufferListByteCount(maximumBuffers: bufferCount)
        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: audioBufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        rawPointer.initializeMemory(as: UInt8.self, repeating: 0, count: audioBufferListSize)

        let pointer = rawPointer.bindMemory(to: AudioBufferList.self, capacity: 1)
        pointer.pointee.mNumberBuffers = UInt32(bufferCount)
        return UnsafeMutableAudioBufferListPointer(pointer)
    }

    private static func levels(
        from audioBufferList: UnsafeMutableAudioBufferListPointer,
        streamDescription: AudioStreamBasicDescription
    ) -> AudioLevel {
        let flags = streamDescription.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = flags & kAudioFormatFlagIsSignedInteger != 0
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)
        let bytesPerSample = max(1, bitsPerChannel / 8)

        var sumSquares: Float = 0
        var peak: Float = 0
        var sampleCount = 0

        for audioBuffer in audioBufferList {
            guard let data = audioBuffer.mData else {
                continue
            }

            let byteCount = Int(audioBuffer.mDataByteSize)
            let count = byteCount / bytesPerSample
            guard count > 0 else {
                continue
            }

            if isFloat && bitsPerChannel == 32 {
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<count {
                    let sample = samples[index]
                    sumSquares += sample * sample
                    peak = max(peak, abs(sample))
                    sampleCount += 1
                }
            } else if isSignedInteger && bitsPerChannel == 16 {
                let samples = data.assumingMemoryBound(to: Int16.self)
                let scale = Float(Int16.max)
                for index in 0..<count {
                    let sample = Float(samples[index]) / scale
                    sumSquares += sample * sample
                    peak = max(peak, abs(sample))
                    sampleCount += 1
                }
            } else if isSignedInteger && bitsPerChannel == 32 {
                let samples = data.assumingMemoryBound(to: Int32.self)
                let scale = Float(Int32.max)
                for index in 0..<count {
                    let sample = Float(samples[index]) / scale
                    sumSquares += sample * sample
                    peak = max(peak, abs(sample))
                    sampleCount += 1
                }
            }
        }

        return normalizedLevel(sumSquares: sumSquares, peak: peak, sampleCount: sampleCount)
    }

    private static func normalizedLevel(sumSquares: Float, peak: Float, sampleCount: Int) -> AudioLevel {
        guard sampleCount > 0 else {
            return .silent
        }

        let rms = sqrt(sumSquares / Float(sampleCount))
        return AudioLevel(
            rms: min(max(rms, 0), 1),
            peak: min(max(peak, 0), 1)
        )
    }
}
