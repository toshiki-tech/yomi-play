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
    
    /// 処理状態
    var state: ProcessingState = .idle
    
    /// 生成された字幕ドキュメント
    var document: TranscriptDocument?
    
    /// 処理完了フラグ
    var isCompleted: Bool = false

    /// 语音识别预估总耗时（秒）。仅用于 UI 展示，非精确倒计时。
    var recognitionEstimatedTotalSeconds: Int?
    
    // MARK: - サービス
    
    private let speechService: SpeechRecognitionServiceProtocol
    private let furiganaService: FuriganaServiceProtocol
    private let translationService = TranslationService.shared

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
        processingTask = Task { [weak self] in
            guard let self else { return }
            await self.process(source: source)
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
        recognitionEstimatedTotalSeconds = nil
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
            state = .error(String(localized: LocalizedStringResource("audio_url_not_found", locale: loc)))
            return
        }
        state = .resolvingRemoteSource
        let resolved = await RemoteMediaResolver.resolve(originalURL: remoteURL)
        if Task.isCancelled { return }
        guard resolved.isSupported, let audioURL = resolved.resolvedAudioURL else {
            state = .error(String(localized: LocalizedStringResource("podcast_link_unresolvable", locale: loc)))
            return
        }
        state = .downloadingPodcast
        let localAudioURL: URL
        do {
            localAudioURL = try await RemoteAudioFetcher.download(url: audioURL)
        } catch {
            if Task.isCancelled { return }
            state = .error(Self.userFacingMessage(for: error))
            return
        }
        defer { try? FileManager.default.removeItem(at: localAudioURL) }
        if Task.isCancelled { return }
        let localSource: AudioSource
        do {
            localSource = try Self.persistDownloadedMedia(from: localAudioURL, title: source.title)
        } catch {
            state = .error(Self.userFacingMessage(for: error))
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
                state = .error(String(localized: LocalizedStringResource("failed_to_parse_srt_file", locale: AppLocale.current)))
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
                        lineLooksJapanese: false
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
                        lineLooksJapanese: isJapanese
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
            let segmentsToSave = await runTranslationIfNeeded(transcriptSegments)
            let doc = TranscriptDocument(
                source: source,
                segments: segmentsToSave,
                folderId: source.folderId,
                isNonJapaneseRecognitionSource: forceNonJa ? true : nil
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
            state = .error(String(localized: LocalizedStringResource("failed_to_parse_srt_file", locale: AppLocale.current)))
        }
    }
    
    /// 流程：远程则 解析链接 → 下载到本地 → Whisper 识别 → 假名；本地则直接识别。
    @MainActor
    private func processWithRecognition(source: AudioSource) async {
        if Task.isCancelled { return }
        let authorized = await speechService.requestAuthorization()
        guard authorized else {
            state = .error(String(localized: LocalizedStringResource("speech_recognition_permission_denied_please_enable_it_in_settings", locale: AppLocale.current)))
            return
        }

        guard let url = source.playbackURL else {
            state = .error(String(localized: LocalizedStringResource("audio_url_not_found", locale: AppLocale.current)))
            return
        }

        var tempDownloadURL: URL?
        let localAudioURL: URL
        if source.type == .remote {
            state = .resolvingRemoteSource
            let resolved = await RemoteMediaResolver.resolve(originalURL: url)
            if Task.isCancelled { return }
            guard resolved.isSupported, let audioURL = resolved.resolvedAudioURL else {
                state = .error(String(localized: LocalizedStringResource("podcast_link_unresolvable", locale: AppLocale.current)))
                return
            }

            state = .downloadingPodcast
            do {
                localAudioURL = try await RemoteAudioFetcher.download(url: audioURL)
                tempDownloadURL = localAudioURL
            } catch {
                if Task.isCancelled { return }
                state = .error(Self.userFacingMessage(for: error))
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
        recognitionEstimatedTotalSeconds = await estimateRecognitionSeconds(for: localAudioURL)
        state = .recognizing

        var recognitionSegments: [RecognitionSegment]
        do {
            recognitionSegments = try await speechService.recognize(audioURL: localAudioURL)
        } catch {
            if let temp = tempDownloadURL { try? FileManager.default.removeItem(at: temp) }
            if Task.isCancelled { return }
            state = .error(Self.userFacingMessage(for: error))
            return
        }

        guard !recognitionSegments.isEmpty else {
            if let temp = tempDownloadURL { try? FileManager.default.removeItem(at: temp) }
            state = .error(String(localized: LocalizedStringResource("could_not_recognize_speech_please_check_that_the_audio_contains_japanese_speech", locale: AppLocale.current))
                + (source.type == .remote ? "\n\n" + String(localized: LocalizedStringResource("recognition_error_podcast_hint", locale: AppLocale.current)) : ""))
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
                    lineLooksJapanese: segment.isJapanese
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
                    lineLooksJapanese: segment.isJapanese
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
                state = .error(Self.userFacingMessage(for: error))
                return
            }
            finalSource.folderId = source.folderId
        } else {
            finalSource = source
        }

        state = .translating
        let segmentsToSave = await runTranslationIfNeeded(transcriptSegments)
        let doc = TranscriptDocument(
            source: finalSource,
            segments: segmentsToSave,
            folderId: finalSource.folderId,
            isNonJapaneseRecognitionSource: forceNonJa ? true : nil
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

    /// 使用设置中的目标语言对字幕做一次翻译，失败则返回原 segments（不阻塞导入）
    /// 仅当用户已在设置中开启「翻译」时执行
    private func runTranslationIfNeeded(_ segments: [TranscriptSegment]) async -> [TranscriptSegment] {
        guard !segments.isEmpty else { return segments }
        guard UserDefaults.standard.bool(forKey: "translationEnabled") else {
            return segments
        }
        let targetLang = TranslationTargetLanguageOptions.resolvedStoredOrDefault()
        do {
            let result = try await translationService.translateSegments(
                segments,
                sourceLanguageCode: "ja",
                targetLanguageCode: targetLang
            )
            print("ProcessingViewModel: 自动翻译完成 target=\(targetLang)")
            return result
        } catch {
            print("ProcessingViewModel: 自动翻译跳过 \(error)")
            return segments
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let downloadErr = error as? DownloadError {
            return downloadErr.errorDescription ?? String(localized: LocalizedStringResource("failed_to_download_audio", locale: AppLocale.current))
        }
        if error is RemoteSourceError {
            return String(localized: LocalizedStringResource("podcast_link_unresolvable", locale: AppLocale.current))
        }
        let raw = error.localizedDescription
        let isRecognitionEmpty = raw.contains("空でした") || raw.contains("empty") || raw.contains("音声認識") || raw.contains("recognition")
        if isRecognitionEmpty {
            return String(localized: LocalizedStringResource("could_not_recognize_speech_please_check_that_the_audio_contains_japanese_speech", locale: AppLocale.current))
        }
        return raw
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
