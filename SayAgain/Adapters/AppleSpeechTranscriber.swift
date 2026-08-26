import Foundation
import Speech
import AVFoundation
import NaturalLanguage

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

        // 1. Resolve to framework-supported locales.
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

        // 2. Prepare each module. The iOS 26 install path sometimes returns a spurious
        //    "not subscribed to transcription.<lang>" error even when the model is usable
        //    (particularly on Simulator). We don't reject on install failure here — we let
        //    SpeechAnalyzer.start be the source of truth for whether the locale is actually
        //    functional (step 4).
        var candidatePairs: [(locale: Locale, module: SpeechTranscriber)] = []
        for locale in resolvedLocales {
            // Enable transcriptionConfidence so we can filter out phonetic-garbage results
            // emitted by wrong-locale analyzers in a multi-language session.
            let preset = SpeechTranscriber.Preset.progressiveTranscription
            let module = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: preset.transcriptionOptions,
                reportingOptions: preset.reportingOptions,
                attributeOptions: preset.attributeOptions.union([.transcriptionConfidence])
            )
            let status = await AssetInventory.status(forModules: [module])
            switch status {
            case .installed:
                candidatePairs.append((locale, module))
            case .supported, .downloading:
                do {
                    if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                        try await request.downloadAndInstall()
                    }
                } catch {
                    print("AppleSpeechTranscriber: install for \(locale.identifier) reported \(error) — trying analyzer anyway")
                }
                candidatePairs.append((locale, module))
            case .unsupported:
                print("AppleSpeechTranscriber: \(locale.identifier) unsupported (assets not offered)")
            @unknown default:
                print("AppleSpeechTranscriber: \(locale.identifier) unknown status — skipping")
            }
        }
        guard !candidatePairs.isEmpty else {
            throw TranscriberFailure.assetsUnavailable("No usable locales among \(spokenLanguages)")
        }

        // 3. Audio session + engine.
        try configureAudioSession()
        let engine = AVAudioEngine()
        self.audioEngine = engine

        let candidateModules = candidatePairs.map(\.module)
        guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: candidateModules) else {
            throw TranscriberFailure.assetsUnavailable("No compatible audio format")
        }

        let inputNode = engine.inputNode
        let hwFormat = inputNode.inputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: hwFormat, to: audioFormat) else {
            throw TranscriberFailure.assetsUnavailable("Cannot construct audio converter")
        }

        // 4. One analyzer per locale — the analyzer.start call is the real test of whether
        //    a locale is usable. Failures per-locale are dropped; only survivors are wired up.
        var readyPairs: [(locale: Locale, module: SpeechTranscriber)] = []
        var perAnalyzerBuilders: [AsyncStream<AnalyzerInput>.Continuation] = []
        for pair in candidatePairs {
            let (seq, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
            let analyzer = SpeechAnalyzer(modules: [pair.module])
            do {
                try await analyzer.start(inputSequence: seq)
                analyzers.append(analyzer)
                perAnalyzerBuilders.append(builder)
                readyPairs.append(pair)
            } catch {
                print("AppleSpeechTranscriber: analyzer.start failed for \(pair.locale.identifier) — \(error)")
                builder.finish()
            }
        }
        guard !readyPairs.isEmpty else {
            throw TranscriberFailure.assetsUnavailable("No analyzer could be started for \(spokenLanguages)")
        }
        self.inputBuilders = perAnalyzerBuilders
        let readySummary = readyPairs.map { $0.locale.identifier }.joined(separator: ", ")
        print("AppleSpeechTranscriber: ready for \(readySummary)")

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

        // 5. Spawn one consumer task per module. On each .final, split the text into sentences
        //    so the downstream translator gets smaller chunks (faster round-trip, sentence-
        //    aware boundaries preserve meaning).
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
                            // Drop wrong-locale phonetic garbage: only pass finals whose
                            // mean per-token confidence clears a floor.
                            let confidence = Self.meanConfidence(result.text)
                            guard confidence >= Self.minFinalConfidence else {
                                print("AppleSpeechTranscriber: dropped \(langCode) final (conf \(String(format: "%.2f", confidence))): '\(plain)'")
                                continue
                            }
                            for sentence in Self.splitSentences(plain, languageCode: langCode) {
                                let line = TranscriptLine(time: clockRef.now(), language: langCode, text: sentence, confidence: confidence)
                                cont.yield(.final(line))
                            }
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

    // MARK: - Filtering & sentence splitting

    /// Wrong-locale analyzers hallucinate low-confidence phonetic gibberish from correct
    /// speech in another language. This floor drops those; well-heard speech in the target
    /// locale typically scores well above this.
    private static let minFinalConfidence: Double = 0.5

    /// Average of per-run `ConfidenceAttribute` values in the transcription. If no confidence
    /// data is attached (attribute not enabled or empty result), returns 1.0 so the caller
    /// won't drop the result over missing metadata.
    private static func meanConfidence(_ attributed: AttributedString) -> Double {
        var total: Double = 0
        var count: Int = 0
        for run in attributed.runs {
            if let c = run[AttributeScopes.SpeechAttributes.ConfidenceAttribute.self] {
                total += Double(c)
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 1.0
    }

    private static func looksMeaningful(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }
        return trimmed.contains(where: { $0.isLetter })
    }

    /// Language-aware sentence tokenisation via `NLTokenizer(.sentence)`. Keeps semantic units
    /// intact so translation quality doesn't degrade from arbitrary mid-clause cuts.
    private static func splitSentences(_ text: String, languageCode: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed
        if let lang = NLLanguage(rawValue: languageCode) as NLLanguage? {
            tokenizer.setLanguage(lang)
        }

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            let s = String(trimmed[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        return sentences.isEmpty ? [trimmed] : sentences
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
