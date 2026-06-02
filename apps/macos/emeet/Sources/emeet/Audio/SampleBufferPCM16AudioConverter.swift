import CoreAudio
import CoreMedia
import Foundation

final class SampleBufferPCM16AudioConverter {
    private enum SampleFormat {
        case float32
        case signedInt16
        case signedInt32
    }

    func convert(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard CMSampleBufferIsValid(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            return nil
        }

        let streamDescription = streamDescriptionPointer.pointee
        guard streamDescription.mFormatID == kAudioFormatLinearPCM,
              streamDescription.mSampleRate > 0,
              let sampleFormat = sampleFormat(from: streamDescription) else {
            return nil
        }

        guard let monoSamples = monoSamples(
            from: sampleBuffer,
            streamDescription: streamDescription,
            sampleFormat: sampleFormat
        ), !monoSamples.isEmpty else {
            return nil
        }

        let resampled = resample(
            monoSamples,
            from: streamDescription.mSampleRate,
            to: Double(PCM16AudioConverter.outputSampleRate)
        )

        return PCM16AudioConverter.pcm16Data(from: resampled)
    }

    private func monoSamples(
        from sampleBuffer: CMSampleBuffer,
        streamDescription: AudioStreamBasicDescription,
        sampleFormat: SampleFormat
    ) -> [Float]? {
        let channelCount = max(1, Int(streamDescription.mChannelsPerFrame))
        let audioBufferListSize = Self.audioBufferListByteCount(maximumBuffers: channelCount)
        let audioBufferList = Self.allocateAudioBufferList(maximumBuffers: channelCount)
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
            return nil
        }

        let sampleFrameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        if streamDescription.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0 {
            return nonInterleavedMonoSamples(
                from: audioBufferList,
                streamDescription: streamDescription,
                sampleFormat: sampleFormat,
                sampleFrameCount: sampleFrameCount
            )
        }

        return interleavedMonoSamples(
            from: audioBufferList,
            streamDescription: streamDescription,
            sampleFormat: sampleFormat,
            sampleFrameCount: sampleFrameCount
        )
    }

    private func interleavedMonoSamples(
        from audioBufferList: UnsafeMutableAudioBufferListPointer,
        streamDescription: AudioStreamBasicDescription,
        sampleFormat: SampleFormat,
        sampleFrameCount: Int
    ) -> [Float]? {
        guard let audioBuffer = audioBufferList.first,
              let data = audioBuffer.mData else {
            return nil
        }

        let channelCount = max(1, Int(streamDescription.mChannelsPerFrame))
        let bytesPerSample = Self.bytesPerSample(for: streamDescription)
        let availableFrameCount = Int(audioBuffer.mDataByteSize) / bytesPerSample / channelCount
        let frameCount = sampleFrameCount > 0
            ? min(sampleFrameCount, availableFrameCount)
            : availableFrameCount
        guard frameCount > 0 else {
            return nil
        }

        var samples = [Float]()
        samples.reserveCapacity(frameCount)

        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<channelCount {
                let sampleIndex = frame * channelCount + channel
                sum += Self.normalizedSample(from: data, index: sampleIndex, format: sampleFormat)
            }
            samples.append(sum / Float(channelCount))
        }

        return samples
    }

    private func nonInterleavedMonoSamples(
        from audioBufferList: UnsafeMutableAudioBufferListPointer,
        streamDescription: AudioStreamBasicDescription,
        sampleFormat: SampleFormat,
        sampleFrameCount: Int
    ) -> [Float]? {
        let bytesPerSample = Self.bytesPerSample(for: streamDescription)
        let requestedFrameCount = sampleFrameCount > 0 ? sampleFrameCount : Int.max
        var frameCount = requestedFrameCount
        var availableChannelCount = 0

        for audioBuffer in audioBufferList {
            guard audioBuffer.mData != nil else {
                continue
            }

            let availableFrameCount = Int(audioBuffer.mDataByteSize) / bytesPerSample
            guard availableFrameCount > 0 else {
                continue
            }

            frameCount = min(frameCount, availableFrameCount)
            availableChannelCount += 1
        }

        guard availableChannelCount > 0, frameCount > 0, frameCount != Int.max else {
            return nil
        }

        var samples = Array(repeating: Float(0), count: frameCount)
        var mixedChannelCount = 0

        for audioBuffer in audioBufferList {
            guard let data = audioBuffer.mData else {
                continue
            }

            let availableFrameCount = min(frameCount, Int(audioBuffer.mDataByteSize) / bytesPerSample)
            guard availableFrameCount > 0 else {
                continue
            }

            for frame in 0..<availableFrameCount {
                samples[frame] += Self.normalizedSample(from: data, index: frame, format: sampleFormat)
            }
            mixedChannelCount += 1
        }

        guard mixedChannelCount > 0 else {
            return nil
        }

        for index in samples.indices {
            samples[index] /= Float(mixedChannelCount)
        }

        return samples
    }

    private func resample(_ samples: [Float], from sourceRate: Double, to targetRate: Double) -> [Float] {
        guard sourceRate > 0, targetRate > 0, !samples.isEmpty else {
            return []
        }

        guard sourceRate != targetRate else {
            return samples
        }

        let targetCount = max(1, Int((Double(samples.count) * targetRate / sourceRate).rounded(.toNearestOrAwayFromZero)))
        guard samples.count > 1 else {
            return Array(repeating: samples[0], count: targetCount)
        }

        var resampled = [Float]()
        resampled.reserveCapacity(targetCount)

        for targetIndex in 0..<targetCount {
            let sourcePosition = Double(targetIndex) * sourceRate / targetRate
            let lowerIndex = min(Int(sourcePosition), samples.count - 1)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            let lower = samples[lowerIndex]
            let upper = samples[upperIndex]
            resampled.append(lower + (upper - lower) * fraction)
        }

        return resampled
    }

    private func sampleFormat(from streamDescription: AudioStreamBasicDescription) -> SampleFormat? {
        let flags = streamDescription.mFormatFlags
        let isFloat = flags & kAudioFormatFlagIsFloat != 0
        let isSignedInteger = flags & kAudioFormatFlagIsSignedInteger != 0
        let bitsPerChannel = Int(streamDescription.mBitsPerChannel)

        if isFloat && bitsPerChannel == 32 {
            return .float32
        }

        if isSignedInteger && bitsPerChannel == 16 {
            return .signedInt16
        }

        if isSignedInteger && bitsPerChannel == 32 {
            return .signedInt32
        }

        return nil
    }

    private static func normalizedSample(
        from data: UnsafeMutableRawPointer,
        index: Int,
        format: SampleFormat
    ) -> Float {
        switch format {
        case .float32:
            return data.assumingMemoryBound(to: Float.self)[index]
        case .signedInt16:
            return Float(data.assumingMemoryBound(to: Int16.self)[index]) / Float(Int16.max)
        case .signedInt32:
            return Float(data.assumingMemoryBound(to: Int32.self)[index]) / Float(Int32.max)
        }
    }

    private static func bytesPerSample(for streamDescription: AudioStreamBasicDescription) -> Int {
        max(1, Int(streamDescription.mBitsPerChannel) / 8)
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
}
