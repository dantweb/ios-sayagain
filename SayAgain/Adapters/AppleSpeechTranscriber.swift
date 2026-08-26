import Foundation
import Speech
import AVFoundation

actor AppleSpeechTranscriber: StreamingTranscriber {
    private let clock: any ClockProviding

    private var analyzers: [SpeechAnalyzer] = []
    private var transcribers: [(locale: Locale, module: SpeechTranscriber)] = []
    private var audioEngine: AVAudioEngine?
    private var inputBuilders: [AsyncStream<AnalyzerInput>.Continuation] = []
    private var resultsTasks: [Task<Void, Never>] = []

    private let continuation: AsyncStream<TranscriptionEvent>.Continuation
    nonisolated let events: AsyncStream<TranscriptionEvent>

    init(clock: any ClockProviding) {
        self.clock = clock
        var cont: AsyncStream<TranscriptionEvent>.Continuation!
        self.events = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    func start(spokenLanguages: [String]) async throws {
        guard MicrophonePermission.status() == .granted else {
            throw TranscriberFailure.assetsUnavailable("Microphone permission not granted")
        }

        // 1. Resolve every configured language to a framework-supported locale.
        var resolvedLocales: [Locale] = []
        for spec in spokenLanguages {
            let candidate = Locale(identifier: spec)
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: candidate) {
                if !resolvedLocales.contains(where: { $0.identifier == supported.identifier }) {
                    resolvedLocales.append(supported)
                }
            } else {
                print("AppleSpeechTranscriber: locale '\(spec)' unsupported — skipping")
            }
        }
        guard !resolvedLocales.isEmpty else {
            throw TranscriberFailure.assetsUnavailable("No supported locales in \(spokenLanguages)")
        }

        // 2. For each locale, run the full reserve → create → install cycle serially.
        //    Doing them in phases (all reserves, then all installs) triggers the
        //    "not subscribed to transcription.X" error on iOS 26; the subscription
        //    seems to require the install call to immediately follow the reserve for
        //    the same locale, matching the single-locale pattern that historically worked.
        var readyPairs: [(locale: Locale, module: SpeechTranscriber)] = []
        for locale in resolvedLocales {
            do {
                try await AssetInventory.reserve(locale: locale)
            } catch {
                print("AppleSpeechTranscriber: reserve \(locale.identifier) failed — \(error)")
                continue
            }

            let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    try await request.downloadAndInstall()
                }
                readyPairs.append((locale, module))
            } catch {
                print("AppleSpeechTranscriber: install for \(locale.identifier) failed — \(error)")
            }
        }
        guard !readyPairs.isEmpty else {
            throw TranscriberFailure.assetsUnavailable("None of \(spokenLanguages) could be installed")
        }
        let readySummary = readyPairs.map { $0.locale.identifier }.joined(separator: ", ")
        print("AppleSpeechTranscriber: ready for \(readySummary)")

        // 5. Audio session + engine.
        try configureAudioSession()
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let modules = readyPairs.map(\.module)
        guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
            throw TranscriberFailure.assetsUnavailable("No compatible audio format")
        }

        let inputNode = engine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: hwFormat, to: audioFormat) else {
            throw TranscriberFailure.assetsUnavailable("Cannot construct audio converter")
        }

        // 6. ONE ANALYZER PER LOCALE — each with its own input sequence. The tap broadcasts
        //    the same converted PCM buffer to every builder so all locales receive the audio.
        var perAnalyzerBuilders: [AsyncStream<AnalyzerInput>.Continuation] = []
        for pair in readyPairs {
            let (seq, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let analyzer = SpeechAnalyzer(modules: [pair.module])
            try await analyzer.start(inputSequence: seq)
            analyzers.append(analyzer)
            perAnalyzerBuilders.append(builder)
        }
        self.inputBuilders = perAnalyzerBuilders

        // Snapshot for the tap closure. Sendable — the builders are safe to hold.
        let localBuilders = perAnalyzerBuilders
        let localConverter = converter
        let localFormat = audioFormat
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hwFormat) { buffer, _ in
            guard let out = AVAudioPCMBuffer(pcmFormat: localFormat, frameCapacity: buffer.frameCapacity) else { return }
            var error: NSError?
            var providedOnce = false
            let status = localConverter.convert(to: out, error: &error) { _, statusPtr in
                if providedOnce {
                    statusPtr.pointee = .noDataNow
                    return nil
                }
                providedOnce = true
                statusPtr.pointee = .haveData
                return buffer
            }
            if error == nil, status != .error, out.frameLength > 0 {
                let input = AnalyzerInput(buffer: out)
                for b in localBuilders { b.yield(input) }
            }
        }

        engine.prepare()
        try engine.start()

        self.transcribers = readyPairs

        // 7. Spawn one consumer task per module — all fan out into the shared events stream.
        let cont = self.continuation
        let clockRef = self.clock
        for (locale, module) in readyPairs {
            let langCode = locale.language.languageCode?.identifier ?? locale.identifier
            let task = Task {
                do {
                    for try await result in module.results {
                        let plain = String(result.text.characters)
                        guard Self.looksMeaningful(plain) else { continue }
                        if result.isFinal {
                            let line = TranscriptLine(time: clockRef.now(), language: langCode, text: plain)
                            cont.yield(.final(line))
                        } else {
                            cont.yield(.volatile(plain))
                        }
                    }
                } catch {
                    print("AppleSpeechTranscriber: \(langCode) stream error — \(error)")
                    cont.yield(.failed(.engineFailed("\(langCode): \(error)")))
                }
            }
            resultsTasks.append(task)
        }
    }

    func stop() async {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        for b in inputBuilders { b.finish() }
        inputBuilders.removeAll()

        for a in analyzers { try? await a.finalizeAndFinishThroughEndOfInput() }
        analyzers.removeAll()

        transcribers.removeAll()

        for task in resultsTasks { task.cancel() }
        resultsTasks.removeAll()

        try? deactivateAudioSession()
    }

    // MARK: - Filtering

    private static func looksMeaningful(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        return trimmed.contains(where: { $0.isLetter })
    }

    // MARK: - Audio session

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: [])
    }

    private func deactivateAudioSession() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
