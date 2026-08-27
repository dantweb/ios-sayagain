#if SAYAGAINPLUS_TIER
import Foundation
import AVFoundation

/// `StreamingTranscriber` backed by WhisperKit (batch) + the domain `EndpointedTranscriber`.
///
/// - Owns an `AVAudioEngine` mic tap.
/// - Converts hardware format → 16 kHz mono Float32 (WhisperKit's expected input).
/// - Feeds converted `AudioBuffer`s to an internal `EndpointedTranscriber`, which segments
///   on silence and dispatches whole utterances to `WhisperTranscriptionEngine`.
/// - Emits `.final` only (batch engines don't stream volatile results). The UI already
///   handles the volatile-optional case gracefully.
actor WhisperStreamingTranscriber: StreamingTranscriber {

    static let audioSampleRate: Double = 16_000

    private let engine: WhisperTranscriptionEngine
    private let endpointerConfig: EndpointerConfig
    private let clock: any ClockProviding

    private var endpointed: EndpointedTranscriber?
    private var audioEngine: AVAudioEngine?
    private var forwardingTask: Task<Void, Never>?

    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    nonisolated let events: AsyncStream<TranscriptionEvent>

    init(
        engine: WhisperTranscriptionEngine,
        endpointerConfig: EndpointerConfig,
        clock: any ClockProviding
    ) {
        self.engine = engine
        self.endpointerConfig = endpointerConfig
        self.clock = clock

        var cont: AsyncStream<TranscriptionEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func start(spokenLanguages: [String]) async throws {
        guard MicrophonePermission.status() == .granted else {
            throw TranscriberFailure.assetsUnavailable("Microphone permission not granted")
        }

        // Pin the language when the user picked exactly one; nil means whisper auto-detects.
        let pinnedLanguage: String? = spokenLanguages.count == 1 ? spokenLanguages.first : nil

        let inner = EndpointedTranscriber(
            engine: engine,
            language: pinnedLanguage,
            endpointerConfig: endpointerConfig,
            audioSampleRate: Self.audioSampleRate,
            clock: clock
        )
        endpointed = inner
        try await inner.start(spokenLanguages: spokenLanguages)

        // Forward inner events to our stream so the coordinator sees them.
        let cont = self.continuation
        let innerEvents = inner.events
        forwardingTask = Task {
            for await event in innerEvents {
                cont.yield(event)
            }
        }

        try startMicrophone(feeding: inner)
    }

    func stop() async {
        if let engineTap = audioEngine, engineTap.isRunning {
            engineTap.stop()
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        await endpointed?.stop()
        endpointed = nil

        forwardingTask?.cancel()
        forwardingTask = nil

        try? deactivateAudioSession()
    }

    // MARK: - Microphone

    private func startMicrophone(feeding inner: EndpointedTranscriber) throws {
        try configureAudioSession()
        let engineTap = AVAudioEngine()
        self.audioEngine = engineTap

        // Target format: 16 kHz mono Float32 — WhisperKit's expected input.
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.audioSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw TranscriberFailure.assetsUnavailable("Cannot build target audio format for whisper")
        }

        let inputNode = engineTap.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: hwFormat, to: targetFormat) else {
            throw TranscriberFailure.assetsUnavailable("Cannot construct audio converter for whisper")
        }

        let clockRef = self.clock
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
            guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: buffer.frameCapacity) else { return }
            var error: NSError?
            var provided = false
            let status = converter.convert(to: out, error: &error) { _, statusPtr in
                if provided {
                    statusPtr.pointee = .noDataNow
                    return nil
                }
                provided = true
                statusPtr.pointee = .haveData
                return buffer
            }
            guard error == nil, status != .error, out.frameLength > 0 else { return }

            // Copy the float samples out and hand them to the endpointed transcriber.
            guard let ptr = out.floatChannelData?[0] else { return }
            let count = Int(out.frameLength)
            let samples = Array(UnsafeBufferPointer(start: ptr, count: count))

            let audioBuffer = AudioBuffer(
                samples: samples,
                sampleRate: Self.audioSampleRate,
                channelCount: 1,
                timestamp: clockRef.now()
            )
            Task { await inner.feed(audioBuffer) }
        }

        engineTap.prepare()
        try engineTap.start()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: [])
    }

    private func deactivateAudioSession() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
#endif
