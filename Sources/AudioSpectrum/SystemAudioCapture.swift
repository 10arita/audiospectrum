import CoreAudio
import Foundation

/// Captures the system output without changing the output device or using the microphone.
/// Configure callbacks before starting. Call start/stop on the main thread; callbacks run
/// on the serial audio queue and must hand UI work to the main queue asynchronously.
@available(macOS 14.2, *)
final class SystemAudioCapture {
    /// Synchronized, channel-major PCM. Keep channels separate until FFT power
    /// aggregation so opposite-phase stereo cannot disappear through averaging.
    var onSamples: (([[Float]], Double) -> Void)?
    var onError: ((Error) -> Void)?

    private let audioQueue = DispatchQueue(label: "AudioSpectrum.SystemAudio", qos: .userInitiated)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var sessionID: UUID?
    private var listeners: [PropertyListener] = []

    private struct PropertyListener {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    func start() throws {
        precondition(Thread.isMainThread, "Start audio capture on the main thread.")
        guard sessionID == nil else { return }

        let session = UUID()
        sessionID = session
        do {
            // An empty exclusion list includes all output processes. Unmuted keeps
            // the normal speaker/headphone playback path intact.
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            description.name = "AudioSpectrum System Output"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tapID), operation: "システム音声の取得準備")

            let format = try readTapFormat()
            try validate(format)

            // This private, temporary HAL object only exposes the tap as input.
            // It is never selected as the Mac's default audio output.
            let aggregateDescription: [String: Any] = [
                kAudioAggregateDeviceNameKey: "AudioSpectrum Capture",
                kAudioAggregateDeviceUIDKey: "AudioSpectrum.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try check(
                AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateID),
                operation: "音声取得デバイスの作成"
            )

            let sampleHandler = onSamples
            try check(
                AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, audioQueue) { _, input, _, _, _ in
                    let channels = Self.channelSamples(from: input, format: format)
                    if !channels.isEmpty {
                        sampleHandler?(channels, format.mSampleRate)
                    }
                },
                operation: "音声コールバックの準備"
            )

            try addRestartListener(
                objectID: AudioObjectID(kAudioObjectSystemObject),
                selector: kAudioHardwarePropertyDefaultOutputDevice,
                session: session
            )
            try addRestartListener(objectID: tapID, selector: kAudioTapPropertyFormat, session: session)

            // macOS requests system-audio permission here when needed. There is
            // deliberately no tap/aggregate creation during application launch.
            try check(AudioDeviceStart(aggregateID, ioProcID), operation: "システム音声の取得開始")
        } catch {
            releaseResources()
            throw error
        }
    }

    func stop() {
        precondition(Thread.isMainThread, "Stop audio capture on the main thread.")
        releaseResources()
    }

    deinit {
        releaseResources()
    }

    private func releaseResources() {
        // Invalidate already-enqueued property notifications before removing them.
        sessionID = nil
        for var listener in listeners {
            AudioObjectRemovePropertyListenerBlock(listener.objectID, &listener.address, .main, listener.block)
        }
        listeners.removeAll()

        if aggregateID != kAudioObjectUnknown, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            // Core Audio no longer submits callbacks after destroying the IOProc.
            // Finish any dispatched callback before returning to the UI.
            audioQueue.sync {}
        }
        ioProcID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private func addRestartListener(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        session: UUID
    ) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.sessionID == session else { return }
            let errorHandler = self.onError
            self.stop()
            self.audioQueue.async { errorHandler?(CaptureError.outputChanged) }
        }
        try check(
            AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block),
            operation: "音声デバイス変更の監視"
        )
        listeners.append(PropertyListener(objectID: objectID, address: address, block: block))
    }

    private func readTapFormat() throws -> AudioStreamBasicDescription {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(
            AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format),
            operation: "音声フォーマットの取得"
        )
        guard size == MemoryLayout<AudioStreamBasicDescription>.size else {
            throw CaptureError.unsupportedFormat
        }
        return format
    }

    private func validate(_ format: AudioStreamBasicDescription) throws {
        let noninterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let expectedFrameBytes = UInt32(MemoryLayout<Float>.size) * (noninterleaved ? 1 : format.mChannelsPerFrame)
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              format.mBitsPerChannel == 32,
              format.mChannelsPerFrame > 0,
              format.mBytesPerFrame == expectedFrameBytes,
              format.mSampleRate.isFinite, format.mSampleRate > 0 else {
            throw CaptureError.unsupportedFormat
        }
    }

    /// Reads both planar and interleaved Float32 buffers using the tap's ASBD.
    /// All returned channels have the same frame count; missing data is silence.
    private static func channelSamples(
        from input: UnsafePointer<AudioBufferList>,
        format: AudioStreamBasicDescription
    ) -> [[Float]] {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var frameCount = Int.max
        var channelCount = 0
        for buffer in buffers where buffer.mNumberChannels > 0 {
            let channels = Int(buffer.mNumberChannels)
            frameCount = min(frameCount, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            channelCount += channels
        }
        guard channelCount == Int(format.mChannelsPerFrame), frameCount > 0, frameCount != Int.max else {
            return []
        }

        var samples = (0..<channelCount).map { _ in [Float](repeating: 0, count: frameCount) }
        var firstChannel = 0
        for buffer in buffers {
            let channels = Int(buffer.mNumberChannels)
            if let data = buffer.mData {
                let source = data.assumingMemoryBound(to: Float.self)
                for channel in 0..<channels {
                    for frame in 0..<frameCount {
                        let sample = source[frame * channels + channel]
                        samples[firstChannel + channel][frame] = sample.isFinite ? sample : 0
                    }
                }
            }
            firstChannel += channels
        }
        return samples
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else { throw CaptureError.system(operation: operation, status: status) }
    }

    private enum CaptureError: LocalizedError {
        case system(operation: String, status: OSStatus)
        case unsupportedFormat
        case outputChanged

        var errorDescription: String? {
            switch self {
            case let .system(operation, status):
                return "\(operation)に失敗しました（Core Audio: \(status)）。システム設定の「プライバシーとセキュリティ」→「画面収録とシステムオーディオ録音」で AudioSpectrum の音声取得を許可し、再起動してください。"
            case .unsupportedFormat:
                return "この出力デバイスの音声形式に対応していません。別の出力デバイスを選び、もう一度開始してください。"
            case .outputChanged:
                return "出力デバイスまたは音声形式が変更されたため停止しました。もう一度「開始」を押してください。"
            }
        }
    }
}
