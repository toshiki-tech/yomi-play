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
    
    // MARK: - サービス
    
    private let speechService: SpeechRecognitionServiceProtocol
    private let furiganaService: FuriganaServiceProtocol
    private let translationService = TranslationService.shared
    
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
        Task {
            await process(source: source)
        }
    }
    
    /// SRT が提供されているかどうか（ProcessingView の UI 表示に使う）
    var hasSRT: Bool = false
    
    /// 音声認識→振り仮名生成の処理フロー
    @MainActor
    private func process(source: AudioSource) async {
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
        guard source.type == .remote, let remoteURL = source.playbackURL else {
            state = .error(String(localized: LocalizedStringResource("audio_url_not_found", locale: loc)))
            return
        }
        state = .resolvingRemoteSource
        let resolved = await RemoteMediaResolver.resolve(originalURL: remoteURL)
        guard resolved.isSupported, let audioURL = resolved.resolvedAudioURL else {
            state = .error(String(localized: LocalizedStringResource("podcast_link_unresolvable", locale: loc)))
            return
        }
        state = .downloadingPodcast
        let localAudioURL: URL
        do {
            localAudioURL = try await RemoteAudioFetcher.download(url: audioURL)
        } catch {
            state = .error(Self.userFacingMessage(for: error))
            return
        }
        defer { try? FileManager.default.removeItem(at: localAudioURL) }
        var localSource = Self.persistDownloadedMedia(from: localAudioURL, title: source.title)
        localSource.srtRelativeFilePath = source.srtRelativeFilePath
        await processWithSRT(source: localSource, srtURL: srtURL)
    }
    
    /// SRT 付き：語音識別をスキップし、SRT を解析して振り仮名を生成する
    @MainActor
    private func processWithSRT(source: AudioSource, srtURL: URL) async {
        do {
            state = .parsingSRT
            
            let srtSegments = try SubtitleImportService.parseSRT(from: srtURL)
            guard !srtSegments.isEmpty else {
                state = .error(String(localized: LocalizedStringResource("failed_to_parse_srt_file", locale: AppLocale.current)))
                return
            }
            
            print("ProcessingViewModel: SRT 解析完了 セグメント数=\(srtSegments.count)")
            
            state = .generatingFurigana
            var transcriptSegments: [TranscriptSegment] = []
            
            for seg in srtSegments {
                let isJapanese = WhisperSpeechRecognitionService.isLikelyJapanese(seg.text)
                let tokens = isJapanese ? await furiganaService.generateFurigana(for: seg.text) : []
                transcriptSegments.append(TranscriptSegment(
                    startTime: seg.startTime,
                    endTime: seg.endTime,
                    originalText: seg.text,
                    tokens: tokens,
                    skipFurigana: !isJapanese
                ))
            }
            
            print("ProcessingViewModel: 振り仮名生成完了")

            state = .translating
            let segmentsToSave = await runTranslationIfNeeded(transcriptSegments)
            let doc = TranscriptDocument(source: source, segments: segmentsToSave)
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
            print("ProcessingViewModel: SRT エラー: \(error)")
            state = .error(String(localized: LocalizedStringResource("failed_to_parse_srt_file", locale: AppLocale.current)))
        }
    }
    
    /// 流程：远程则 解析链接 → 下载到本地 → Whisper 识别 → 假名；本地则直接识别。
    @MainActor
    private func processWithRecognition(source: AudioSource) async {
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
            guard resolved.isSupported, let audioURL = resolved.resolvedAudioURL else {
                state = .error(String(localized: LocalizedStringResource("podcast_link_unresolvable", locale: AppLocale.current)))
                return
            }

            state = .downloadingPodcast
            do {
                localAudioURL = try await RemoteAudioFetcher.download(url: audioURL)
                tempDownloadURL = localAudioURL
            } catch {
                state = .error(Self.userFacingMessage(for: error))
                return
            }
            state = .loadingAudio
            state = .recognizing
        } else {
            state = .loadingAudio
            localAudioURL = url
            state = .recognizing
        }

        var recognitionSegments: [RecognitionSegment]
        do {
            recognitionSegments = try await speechService.recognize(audioURL: localAudioURL)
        } catch {
            if let temp = tempDownloadURL { try? FileManager.default.removeItem(at: temp) }
            state = .error(Self.userFacingMessage(for: error))
            return
        }

        guard !recognitionSegments.isEmpty else {
            if let temp = tempDownloadURL { try? FileManager.default.removeItem(at: temp) }
            state = .error(String(localized: LocalizedStringResource("could_not_recognize_speech_please_check_that_the_audio_contains_japanese_speech", locale: AppLocale.current))
                + (source.type == .remote ? "\n\n" + String(localized: LocalizedStringResource("recognition_error_podcast_hint", locale: AppLocale.current)) : ""))
            return
        }

        state = .generatingFurigana
        var transcriptSegments: [TranscriptSegment] = []
        for segment in recognitionSegments {
            let baseTokens: [FuriganaToken]
            if segment.isJapanese {
                // 日语：正常生成带假名/罗马字/词性的 tokens，再挂上逐词时间戳
                let tokens = await furiganaService.generateFurigana(for: segment.text)
                baseTokens = Self.attachWordTimingsIfAvailable(
                    tokens: tokens,
                    text: segment.text,
                    wordTimings: segment.wordTimings
                )
            } else if let wordTimings = segment.wordTimings, !wordTimings.isEmpty {
                // 非日语：仅根据 word timings 生成简易 token，用于卡拉 OK 高亮
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
            
            transcriptSegments.append(TranscriptSegment(
                startTime: segment.startTime,
                endTime: segment.endTime,
                originalText: segment.text,
                tokens: baseTokens,
                confidence: segment.confidence,
                skipFurigana: !segment.isJapanese
            ))
        }

        let finalSource: AudioSource
        if let temp = tempDownloadURL {
            finalSource = Self.persistDownloadedMedia(from: temp, title: source.title)
        } else {
            finalSource = source
        }

        state = .translating
        let segmentsToSave = await runTranslationIfNeeded(transcriptSegments)
        let doc = TranscriptDocument(source: finalSource, segments: segmentsToSave)
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

    /// 播客下载的临时文件移动到 Documents/Media，返回本地 AudioSource，便于播放时直接读文件。
    private static func persistDownloadedMedia(from tempURL: URL, title: String) -> AudioSource {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let mediaDir = docs.appendingPathComponent("Media", isDirectory: true)
        if !FileManager.default.fileExists(atPath: mediaDir.path) {
            try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        }
        let ext = tempURL.pathExtension.isEmpty ? "mp3" : tempURL.pathExtension
        let fileName = UUID().uuidString + "." + ext
        let destURL = mediaDir.appendingPathComponent(fileName)
        try? FileManager.default.moveItem(at: tempURL, to: destURL)
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
        let targetLang = UserDefaults.standard.string(forKey: "targetLanguageCode") ?? "zh-Hans"
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
