//
//  ProcessingViewModel.swift
//  YomiPlay
//
//  処理画面のViewModel
//  音声認識→振り仮名生成の処理フローを管理する
//

import Foundation

// MARK: - 処理画面ViewModel

/// 音声認識と振り仮名生成の処理フローを管理するViewModel
@Observable
final class ProcessingViewModel {
    enum RecognitionTimeoutError: LocalizedError {
        case timedOut

        var errorDescription: String? {
            String(localized: LocalizedStringResource("recognition_runtime_failed_hint", locale: AppLocale.current))
        }
    }
    
    /// 処理状態
    var state: ProcessingState = .idle
    
    /// 生成された字幕ドキュメント
    var document: TranscriptDocument?
    
    /// 処理完了フラグ
    var isCompleted: Bool = false

    /// 语音识别预估总耗时（秒）。仅用于 UI 展示，非精确倒计时。
    var recognitionEstimatedTotalSeconds: Int?
    /// 仅在低性能设备首次显示一次的轻提示文案
    var lowEndDeviceHintMessage: String?
    /// 本次运行实际使用的"降级"识别档位。`nil` 表示按用户设置识别成功，未发生降级。
    /// 不会修改 UserDefaults 中的用户选择，仅用于 UI 提示「本次以更小模型识别，原设置未变」。
    var lastRunFallbackMode: WhisperSpeechRecognitionService.RecognitionMode?
    
    // MARK: - サービス
    
    private let speechService: SpeechRecognitionServiceProtocol
    private let furiganaService: FuriganaServiceProtocol
    private let translationService = TranslationService.shared
    private static let recognitionModeOrder: [WhisperSpeechRecognitionService.RecognitionMode] = [.tiny, .base, .small, .medium, .large]
    private static let lowEndHintShownKey = "didShowLowEndRecognitionHint"

    private var processingTask: Task<Void, Never>?
    
    // MARK: - 初期化
    
    init(
        speechService: SpeechRecognitionServiceProtocol? = nil,
        furiganaService: FuriganaServiceProtocol? = nil
    ) {
        // 本番では Whisper 本地音声認識サービスを使用する
        self.speechService = speechService ?? WhisperSpeechRecognitionService()
        self.furiganaService = furiganaService ?? CFStringTokenizerFuriganaService()
    }
    
    // MARK: - 処理の実行
    
    /// 音声ソースの処理を開始する
    func startProcessing(source: AudioSource) {
        processingTask?.cancel()
        // 清掉上一次任务可能残留的临时降级状态，避免影响下一段音频
        lastRunFallbackMode = nil
        (speechService as? WhisperSpeechRecognitionService)?.clearTransientModelOverride()
        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.process(source: source)
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        recognitionEstimatedTotalSeconds = nil
        lastRunFallbackMode = nil
        (speechService as? WhisperSpeechRecognitionService)?.clearTransientModelOverride()
        state = .idle
    }
    
    /// SRT が提供されているかどうか（ProcessingView の UI 表示に使う）
    var hasSRT: Bool = false
    
    /// 音声認識→振り仮名生成の処理フロー
    @MainActor
    private func process(source: AudioSource) async {
        if Task.isCancelled { return }
        hasSRT = source.srtURL != nil
        
        if let srtURL = source.srtURL {
            if source.type == .remote {
                await processRemoteThenSRT(source: source, srtURL: srtURL)
            } else {
                await processWithSRT(source: source, srtURL: srtURL)
            }
        } else {
            await processWithRecognition(source: source)
        }
    }

    /// 远程 + 附带 SRT：先解析并下载音频到本地，再用 SRT 生成字幕（跳过 AI 识别）
    @MainActor
    private func processRemoteThenSRT(source: AudioSource, srtURL: URL) async {
        let loc = AppLocale.current
        if Task.isCancelled { return }
        guard source.type == .remote, let remoteURL = source.playbackURL else {
            state = .error(stage: .resolveRemote, message: String(localized: LocalizedStringResource("audio_url_not_found", locale: loc)))
            return
        }
        state = .resolvingRemoteSource
        let resolved = await RemoteMediaResolver.resolve(originalURL: remoteURL)
        if Task.isCancelled { return }
        guard resolved.isSupported, let audioURL = resolved.resolvedAudioURL else {
            // 优先使用解析层返回的精准失败原因，避免国内网络问题被笼统报为「链接不支持」
            let message = resolved.failureReason?.errorDescription
                ?? String(localized: LocalizedStringResource("podcast_link_unresolvable", locale: loc))
            state = .error(stage: .resolveRemote, message: message)
            return
        }
        state = .downloadingPodcast
        let localAudioURL: URL
        do {
            localAudioURL = try await RemoteAudioFetcher.download(url: audioURL)
        } catch {
            if Task.isCancelled { return }
            state = .error(stage: .downloadRemote, message: Self.userFacingMessage(for: error))
            return
        }
        defer { try? FileManager.default.removeItem(at: localAudioURL) }
        if Task.isCancelled { return }
        let localSource: AudioSource
        do {
            localSource = try Self.persistDownloadedMedia(from: localAudioURL, title: source.title)
        } catch {
            state = .error(stage: .loadAudio, message: Self.userFacingMessage(for: error))
            return
        }
        var sourceForSRT = localSource
        sourceForSRT.folderId = source.folderId
        sourceForSRT.srtRelativeFilePath = source.srtRelativeFilePath
        await processWithSRT(source: sourceForSRT, srtURL: srtURL)
    }
    
    /// SRT 付き：語音識別をスキップし、SRT を解析して振り仮名を生成する
    @MainActor
    private func processWithSRT(source: AudioSource, srtURL: URL) async {
        do {
            if Task.isCancelled { return }
            state = .parsingSRT
            
            let srtSegments = try SubtitleImportService.parseSRT(from: srtURL)
            guard !srtSegments.isEmpty else {
                state = .error(stage: .parseSRT, message: String(localized: LocalizedStringResource("failed_to_parse_srt_file", locale: AppLocale.current)))
                return
            }
            
            print("ProcessingViewModel: SRT 解析完了 セグメント数=\(srtSegments.count)")
            
            let lang = UserDefaults.standard.string(forKey: WhisperSpeechRecognitionService.sourceLanguageDefaultsKey) ?? "ja"
            let forceNonJa = WhisperSpeechRecognitionService.forcesNonJapaneseSegments(lang: lang)
            var transcriptSegments: [TranscriptSegment] = []
            
            if forceNonJa {
                for seg in srtSegments {
                    if Task.isCancelled { return }
                    let lineLang = WhisperSpeechRecognitionService.storedOriginalTextLanguageCode(
                        recognitionUserSetting: lang,
                        lineLooksJapanese: false,
                        whisperDetectedLanguageCode: nil
                    )
                    transcriptSegments.append(TranscriptSegment(
                        startTime: seg.startTime,
                        endTime: seg.endTime,
                        originalText: seg.text,
                        tokens: [],
                        skipFurigana: true,
                        originalTextLanguageCode: lineLang
                    ))
                }
            } else {
                state = .generatingFurigana
                for seg in srtSegments {
                    if Task.isCancelled { return }
                    let isJapanese = WhisperSpeechRecognitionService.isLikelyJapanese(seg.text)
                    let tokens = isJapanese ? await furiganaService.generateFurigana(for: seg.text) : []
                    let lineLang = WhisperSpeechRecognitionService.storedOriginalTextLanguageCode(
                        recognitionUserSetting: lang,
                        lineLooksJapanese: isJapanese,
                        whisperDetectedLanguageCode: nil
                    )
                    transcriptSegments.append(TranscriptSegment(
                        startTime: seg.startTime,
                        endTime: seg.endTime,
                        originalText: seg.text,
                        tokens: tokens,
                        skipFurigana: !isJapanese,
                        originalTextLanguageCode: lineLang
                    ))
                }
                print("ProcessingViewModel: 振り仮名生成完了")
            }

            state = .translating
            let inferredDocNonJa = SubtitleRecognitionLanguage.inferNonJapaneseDocumentFlag(
                recognitionSetting: lang,
                segments: transcriptSegments,
                forcedNonJapanese: forceNonJa
            )
            let docNonJaResolved: Bool? = forceNonJa ? true : inferredDocNonJa
            let outcome = await runTranslationIfNeeded(transcriptSegments, documentNonJapanese: docNonJaResolved)
            let doc = TranscriptDocument(
                source: source,
                segments: outcome.segments,
                folderId: source.folderId,
                isNonJapaneseRecognitionSource: docNonJaResolved,
                translationStatus: outcome.status
            )
            document = doc
            state = .completed

            do {
                try DocumentStore.shared.save(doc)
            } catch {
                print("ProcessingViewModel: 保存失敗: \(error)")
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
            isCompleted = true

        } catch {
            if Task.isCancelled { return }
            print("ProcessingViewModel: SRT エラー: \(error)")
            state = .error(stage: .parseSRT, message: String(localized: LocalizedStringResource("failed_to_parse_srt_file", locale: AppLocale.current)))
        }
    }
    
    /// 流程：远程则 解析链接 → 下载到本地 → Whisper 识别 → 假名；本地则直接识别。
    @MainActor
    private func processWithRecognition(source: AudioSource) async {
        if Task.isCancelled { return }
        let authorized = await speechService.requestAuthorization()
        guard authorized else {
            state = .error(stage: .permission, message: String(localized: LocalizedStringResource("speech_recognition_permission_denied_please_enable_it_in_settings", locale: AppLocale.current)))
            return
        }

        guard let url = source.playbackURL else {
            // playbackURL 缺失：远程是解析阶段，本地是加载阶段
            let stage: ProcessingStage = (source.type == .remote) ? .resolveRemote : .loadAudio
            state = .error(stage: stage, message: String(localized: LocalizedStringResource("audio_url_not_found", locale: AppLocale.current)))
            return
        }

        var tempDownloadURL: URL?
        let localAudioURL: URL
        if source.type == .remote {
            state = .resolvingRemoteSource
            let resolved = await RemoteMediaResolver.resolve(originalURL: url)
            if Task.isCancelled { return }
            guard resolved.isSupported, let audioURL = resolved.resolvedAudioURL else {
                let message = resolved.failureReason?.errorDescription
                    ?? String(localized: LocalizedStringResource("podcast_link_unresolvable", locale: AppLocale.current))
                state = .error(stage: .resolveRemote, message: message)
                return
            }

            state = .downloadingPodcast
            do {
                localAudioURL = try await RemoteAudioFetcher.download(url: audioURL)
                tempDownloadURL = localAudioURL
            } catch {
                if Task.isCancelled { return }
                state = .error(stage: .downloadRemote, message: Self.userFacingMessage(for: error))
                return
            }
            state = .loadingAudio
        } else {
            state = .loadingAudio
            localAudioURL = url
        }

        if Task.isCancelled {
            if let temp = tempDownloadURL { try? FileManager.default.removeItem(at: temp) }
            return
        }

        // 进入识别前估算耗时（仅作 UI 参考）
        alignRecognitionModeForCurrentDevice()
        recognitionEstimatedTotalSeconds = await estimateRecognitionSeconds(for: localAudioURL)
        state = .recognizing

        var recognitionSegments: [RecognitionSegment]
        do {
            recognitionSegments = try await recognizeWithFallback(audioURL: localAudioURL)
        } catch {
            if let temp = tempDownloadURL { try? FileManager.default.removeItem(at: temp) }
            if Task.isCancelled { return }
            state = .error(stage: .recognize, message: Self.userFacingMessage(for: error))
            return
        }

        guard !recognitionSegments.isEmpty else {
            if let temp = tempDownloadURL { try? FileManager.default.removeItem(at: temp) }
            let emptyMessage = String(localized: LocalizedStringResource("could_not_recognize_speech_please_check_that_the_audio_contains_japanese_speech", locale: AppLocale.current))
                + (source.type == .remote ? "\n\n" + String(localized: LocalizedStringResource("recognition_error_podcast_hint", locale: AppLocale.current)) : "")
            state = .error(stage: .recognize, message: emptyMessage)
            return
        }

        if Task.isCancelled {
            if let temp = tempDownloadURL { try? FileManager.default.removeItem(at: temp) }
            return
        }

        let recLang = UserDefaults.standard.string(forKey: WhisperSpeechRecognitionService.sourceLanguageDefaultsKey) ?? "ja"
        let forceNonJa = WhisperSpeechRecognitionService.forcesNonJapaneseSegments(lang: recLang)
        var transcriptSegments: [TranscriptSegment] = []
        
        if forceNonJa {
            for segment in recognitionSegments {
                if Task.isCancelled {
                    if let temp = tempDownloadURL { try? FileManager.default.removeItem(at: temp) }
                    return
                }
                let baseTokens: [FuriganaToken]
                if let wordTimings = segment.wordTimings, !wordTimings.isEmpty {
                    baseTokens = wordTimings.map {
                        FuriganaToken(
                            surface: $0.word,
                            reading: "",
                            romaji: "",
                            isKanji: false,
                            isKatakana: false,
                            englishMeaning: nil,
                            startTime: $0.start,
                            endTime: $0.end,
                            partOfSpeech: nil
                        )
                    }
                } else {
                    baseTokens = []
                }
                let lineLang = WhisperSpeechRecognitionService.storedOriginalTextLanguageCode(
                    recognitionUserSetting: recLang,
                    lineLooksJapanese: segment.isJapanese,
                    whisperDetectedLanguageCode: segment.whisperLanguageCode
                )
                transcriptSegments.append(TranscriptSegment(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    originalText: segment.text,
                    tokens: baseTokens,
                    confidence: segment.confidence,
                    skipFurigana: true,
                    originalTextLanguageCode: lineLang
                ))
            }
        } else {
            state = .generatingFurigana
            for segment in recognitionSegments {
                if Task.isCancelled {
                    if let temp = tempDownloadURL { try? FileManager.default.removeItem(at: temp) }
                    return
                }
                let baseTokens: [FuriganaToken]
                if segment.isJapanese {
                    let tokens = await furiganaService.generateFurigana(for: segment.text)
                    baseTokens = Self.attachWordTimingsIfAvailable(
                        tokens: tokens,
                        text: segment.text,
                        wordTimings: segment.wordTimings
                    )
                } else if let wordTimings = segment.wordTimings, !wordTimings.isEmpty {
                    baseTokens = wordTimings.map {
                        FuriganaToken(
                            surface: $0.word,
                            reading: "",
                            romaji: "",
                            isKanji: false,
                            isKatakana: false,
                            englishMeaning: nil,
                            startTime: $0.start,
                            endTime: $0.end,
                            partOfSpeech: nil
                        )
                    }
                } else {
                    baseTokens = []
                }
                
                let lineLang = WhisperSpeechRecognitionService.storedOriginalTextLanguageCode(
                    recognitionUserSetting: recLang,
                    lineLooksJapanese: segment.isJapanese,
                    whisperDetectedLanguageCode: segment.whisperLanguageCode
                )
                transcriptSegments.append(TranscriptSegment(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    originalText: segment.text,
                    tokens: baseTokens,
                    confidence: segment.confidence,
                    skipFurigana: !segment.isJapanese,
                    originalTextLanguageCode: lineLang
                ))
            }
        }

        var finalSource: AudioSource
        if let temp = tempDownloadURL {
            do {
                finalSource = try Self.persistDownloadedMedia(from: temp, title: source.title)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                state = .error(stage: .loadAudio, message: Self.userFacingMessage(for: error))
                return
            }
            finalSource.folderId = source.folderId
        } else {
            finalSource = source
        }

        state = .translating
        let inferredDocNonJa = SubtitleRecognitionLanguage.inferNonJapaneseDocumentFlag(
            recognitionSetting: recLang,
            segments: transcriptSegments,
            forcedNonJapanese: forceNonJa
        )
        let docNonJaResolved: Bool? = forceNonJa ? true : inferredDocNonJa
        let outcome = await runTranslationIfNeeded(transcriptSegments, documentNonJapanese: docNonJaResolved)
        let doc = TranscriptDocument(
            source: finalSource,
            segments: outcome.segments,
            folderId: finalSource.folderId,
            isNonJapaneseRecognitionSource: docNonJaResolved,
            translationStatus: outcome.status
        )
        document = doc
        state = .completed
        // 按音视频实际时长统计（与播放页显示、配额预检一致），不再用最后一条字幕的 endTime
        let usedSeconds: Int
        if let url = doc.source.playbackURL {
            usedSeconds = await SubscriptionManager.durationSeconds(of: url)
        } else {
            usedSeconds = doc.segments.last.map { Int(ceil($0.endTime)) } ?? 0
        }
        SubscriptionManager.shared.addUsedSeconds(usedSeconds)
        do {
            try DocumentStore.shared.save(doc)
        } catch {
            print("ProcessingViewModel: 保存失敗: \(error)")
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        isCompleted = true
    }

    private func estimateRecognitionSeconds(for audioURL: URL) async -> Int? {
        guard audioURL.isFileURL else { return nil }
        let duration = await SubscriptionManager.durationSeconds(of: audioURL)
        guard duration > 0 else { return nil }
        let raw = UserDefaults.standard.string(forKey: WhisperSpeechRecognitionService.modelVariantDefaultsKey)
            ?? WhisperSpeechRecognitionService.recommendedModeForDevice.rawValue
        let mode = WhisperSpeechRecognitionService.RecognitionMode(rawValue: raw) ?? .small
        // 经验系数：仅供“预估”，不承诺准确。系数越大代表越慢。
        let factor: Double = switch mode {
        case .tiny: 0.18
        case .base: 0.25
        case .small: 0.40
        case .medium: 0.65
        case .large: 0.95
        }
        // 给一点启动/IO 开销
        let estimated = Int(Double(duration) * factor + 8.0)
        return max(10, estimated)
    }

    private func recognizeWithFallback(audioURL: URL) async throws -> [RecognitionSegment] {
        let originalMode = currentRecognitionMode()
        var mode = originalMode
        var lastError: Error?
        var attempts = 0
        // 仅在确实降级到了比用户设置更小的档位时，最终保留为 transient override；
        // 完成后 cleanup 时根据"是否真的降过级"决定是否清除 override 并对外提示。
        let whisperService = speechService as? WhisperSpeechRecognitionService
        defer {
            // 如果本次没有有效的"成功降级"，把 transient override 清掉，避免影响后续别的识别任务
            if mode == originalMode {
                whisperService?.clearTransientModelOverride()
                lastRunFallbackMode = nil
            }
        }

        while attempts < 3 {
            do {
                let timeoutSeconds = recognitionTimeoutSeconds(for: mode)
                let segments = try await withTimeout(seconds: timeoutSeconds) { [speechService] in
                    try await speechService.recognize(audioURL: audioURL)
                }
                // 成功；如果用了降级档位，更新对外可见的 lastRunFallbackMode 但不写 UserDefaults
                lastRunFallbackMode = (mode == originalMode) ? nil : mode
                return segments
            } catch {
                lastError = error
                guard shouldDowngradeAndRetry(for: error),
                      let lower = lowerRecognitionMode(than: mode) else {
                    throw error
                }
                mode = lower
                // 关键：仅设置本次运行的 transient override，不再修改 UserDefaults，
                // 避免悄悄改写用户在设置页选择的档位。
                whisperService?.setTransientModelOverride(mode)
                attempts += 1
            }
        }
        throw lastError ?? NSError(
            domain: "YomiPlayRecognition",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: String(localized: LocalizedStringResource("unknown_error", locale: AppLocale.current))]
        )
    }

    private func recognitionTimeoutSeconds(for mode: WhisperSpeechRecognitionService.RecognitionMode) -> TimeInterval {
        // iPad 等设备在模型初始化或推理异常时，可能出现长时间无返回；设置超时避免无限等待。
        switch mode {
        case .tiny: return 120
        case .base: return 180
        case .small: return 300
        case .medium: return 420
        case .large: return 600
        }
    }

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw RecognitionTimeoutError.timedOut
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func alignRecognitionModeForCurrentDevice() {
        let current = currentRecognitionMode()
        let safe = safeRecognitionModeForCurrentDevice(preferred: current)
        maybePrepareLowEndHint(modeChanged: safe != current)
        if safe != current {
            UserDefaults.standard.set(safe.rawValue, forKey: WhisperSpeechRecognitionService.modelVariantDefaultsKey)
        }
    }

    private func safeRecognitionModeForCurrentDevice(preferred: WhisperSpeechRecognitionService.RecognitionMode) -> WhisperSpeechRecognitionService.RecognitionMode {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0 * 1024.0)
        let maxMode: WhisperSpeechRecognitionService.RecognitionMode
        if gb < 4.0 {
            maxMode = .tiny
        } else if gb < 6.0 {
            maxMode = .base
        } else {
            maxMode = .small
        }
        guard let preferredIdx = Self.recognitionModeOrder.firstIndex(of: preferred),
              let maxIdx = Self.recognitionModeOrder.firstIndex(of: maxMode) else {
            return .small
        }
        return preferredIdx > maxIdx ? maxMode : preferred
    }

    private func currentRecognitionMode() -> WhisperSpeechRecognitionService.RecognitionMode {
        let raw = UserDefaults.standard.string(forKey: WhisperSpeechRecognitionService.modelVariantDefaultsKey)
            ?? WhisperSpeechRecognitionService.recommendedModeForDevice.rawValue
        return WhisperSpeechRecognitionService.RecognitionMode(rawValue: raw) ?? .small
    }

    private func maybePrepareLowEndHint(modeChanged: Bool) {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / (1024.0 * 1024.0 * 1024.0)
        guard gb < 6.0 else {
            lowEndDeviceHintMessage = nil
            return
        }
        let ud = UserDefaults.standard
        guard ud.bool(forKey: Self.lowEndHintShownKey) == false else {
            lowEndDeviceHintMessage = nil
            return
        }
        if modeChanged {
            lowEndDeviceHintMessage = String(
                localized: LocalizedStringResource("recognition_low_end_device_first_hint", locale: AppLocale.current)
            )
            ud.set(true, forKey: Self.lowEndHintShownKey)
        }
    }

    private func lowerRecognitionMode(than mode: WhisperSpeechRecognitionService.RecognitionMode) -> WhisperSpeechRecognitionService.RecognitionMode? {
        guard let idx = Self.recognitionModeOrder.firstIndex(of: mode), idx > 0 else { return nil }
        return Self.recognitionModeOrder[idx - 1]
    }

    /// 播客下载的临时文件移动到 Documents/Media，返回本地 AudioSource。移动失败时抛出，避免保存「有字幕无音频」的文档。
    private static func persistDownloadedMedia(from tempURL: URL, title: String) throws -> AudioSource {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mediaDir = docs.appendingPathComponent("Media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: mediaDir.path) {
            try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        }
        let ext = tempURL.pathExtension.isEmpty ? "mp3" : tempURL.pathExtension
        let fileName = UUID().uuidString + "." + ext
        let destURL = mediaDir.appendingPathComponent(fileName)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
        let relativePath = "Media/" + fileName
        return AudioSource(
            type: .local,
            localURL: destURL,
            relativeFilePath: relativePath,
            title: title
        )
    }

    /// 翻译执行结果与字幕的合并产物。
    /// `status` 用于 UI 在播放页提示「翻译失败」「未启用翻译」等；`segments` 是最终入库的字幕。
    private struct TranslationOutcome {
        let segments: [TranscriptSegment]
        let status: TranslationStatus
    }

    /// 使用设置中的主+副目标语对字幕做一次翻译，失败则返回原 segments（不阻塞导入），并回传执行结果。
    /// 仅当用户已在设置中开启「翻译」时执行；未开启则返回 `.skipped`。
    private func runTranslationIfNeeded(
        _ segments: [TranscriptSegment],
        documentNonJapanese: Bool? = nil
    ) async -> TranslationOutcome {
        guard !segments.isEmpty else {
            return TranslationOutcome(segments: segments, status: .skipped)
        }
        guard UserDefaults.standard.bool(forKey: "translationEnabled") else {
            return TranslationOutcome(segments: segments, status: .skipped)
        }
        let primary = TranslationTargetLanguageOptions.resolvedStoredOrDefault()
        var targets: [String] = [primary]
        if let secondaryRaw = UserDefaults.standard.string(forKey: "secondaryTargetLanguageCode"),
           !secondaryRaw.isEmpty {
            let secondary = TranslationTargetLanguageOptions.normalizedCode(secondaryRaw)
            if secondary != primary {
                targets.append(secondary)
            }
        }
        do {
            let result = try await translationService.translateSegments(
                segments,
                targetLanguageCodes: targets,
                documentNonJapaneseRecognitionSource: documentNonJapanese
            )
            print("ProcessingViewModel: 自动翻译完成 targets=\(targets)")
            return TranslationOutcome(segments: result, status: .success)
        } catch {
            print("ProcessingViewModel: 自动翻译跳过 \(error)")
            return TranslationOutcome(segments: segments, status: .failed)
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let downloadErr = error as? DownloadError {
            return downloadErr.errorDescription ?? String(localized: LocalizedStringResource("failed_to_download_audio", locale: AppLocale.current))
        }
        if let remoteErr = error as? RemoteSourceError {
            // 走具体 case 的本地化文案，而不是统一的「链接不支持」
            return remoteErr.errorDescription ?? String(localized: LocalizedStringResource("podcast_link_unresolvable", locale: AppLocale.current))
        }
        let raw = error.localizedDescription
        let lowerRaw = raw.lowercased()
        if lowerRaw.contains("resource path does not exist") || lowerRaw.contains("no such file") {
            return String(localized: LocalizedStringResource("recognition_source_file_missing_hint", locale: AppLocale.current))
        }
        if lowerRaw.contains("model not found") || lowerRaw.contains("broken/unsupported model") || lowerRaw.contains("downloaderror") {
            return String(localized: LocalizedStringResource("recognition_model_unavailable_hint", locale: AppLocale.current))
        }
        if lowerRaw.contains("unable to compute the asynchronous prediction") || lowerRaw.contains("ml program") || lowerRaw.contains("invalid input data") {
            return String(localized: LocalizedStringResource("recognition_runtime_failed_hint", locale: AppLocale.current))
        }
        let isRecognitionEmpty = raw.contains("空でした") || raw.contains("empty") || raw.contains("音声認識") || raw.contains("recognition")
        if isRecognitionEmpty {
            return String(localized: LocalizedStringResource("could_not_recognize_speech_please_check_that_the_audio_contains_japanese_speech", locale: AppLocale.current))
        }
        return raw
    }

    private func shouldDowngradeAndRetry(for error: Error) -> Bool {
        let lowerRaw = error.localizedDescription.lowercased()
        if error is RecognitionTimeoutError {
            return true
        }
        return lowerRaw.contains("unable to compute the asynchronous prediction")
            || lowerRaw.contains("ml program")
            || lowerRaw.contains("broken/unsupported model")
            || lowerRaw.contains("model not found")
            || lowerRaw.contains("downloaderror")
    }

    /// 将 Whisper 提供的逐词时间戳近似映射到 FuriganaToken 上，用于更精确的卡拉 OK 高亮。
    /// - 注意：这里按文本顺序做启发式对齐，足够提升体验，但并非逐字符完美对齐。
    static func attachWordTimingsIfAvailable(
        tokens: [FuriganaToken],
        text: String,
        wordTimings: [WordTimingInfo]?
    ) -> [FuriganaToken] {
        guard let wordTimings, !wordTimings.isEmpty, !tokens.isEmpty, !text.isEmpty else {
            return tokens
        }
        
        // 1. 为每个 word 在原文中找出 Range
        var wordRanges: [(range: Range<String.Index>, start: TimeInterval, end: TimeInterval)] = []
        var searchIndex = text.startIndex
        for wt in wordTimings {
            guard !wt.word.isEmpty else { continue }
            if let r = text.range(of: wt.word, range: searchIndex..<text.endIndex) ?? text.range(of: wt.word) {
                wordRanges.append((r, wt.start, wt.end))
                searchIndex = r.upperBound
            }
        }
        guard !wordRanges.isEmpty else { return tokens }
        
        // 2. 按文本顺序，将 token.surface 在原文中定位，并根据与 wordRanges 的重叠估算时间
        var newTokens: [FuriganaToken] = []
        searchIndex = text.startIndex
        for token in tokens {
            var start: TimeInterval? = nil
            var end: TimeInterval? = nil
            
            if let tokenRange = text.range(of: token.surface, range: searchIndex..<text.endIndex)
                ?? text.range(of: token.surface) {
                // 找到所有与该 token 范围有重叠的 word
                let overlapped = wordRanges.filter { wr in
                    tokenRange.lowerBound < wr.range.upperBound && tokenRange.upperBound > wr.range.lowerBound
                }
                if !overlapped.isEmpty {
                    start = overlapped.map { $0.start }.min()
                    end = overlapped.map { $0.end }.max()
                }
                searchIndex = tokenRange.upperBound
            }
            
            if let s = start, let e = end, e > s {
                newTokens.append(FuriganaToken(
                    id: token.id,
                    surface: token.surface,
                    reading: token.reading,
                    romaji: token.romaji,
                    isKanji: token.isKanji,
                    isKatakana: token.isKatakana,
                    englishMeaning: token.englishMeaning,
                    startTime: s,
                    endTime: e,
                    partOfSpeech: token.partOfSpeech
                ))
            } else {
                newTokens.append(token)
            }
        }
        return newTokens
    }
}
