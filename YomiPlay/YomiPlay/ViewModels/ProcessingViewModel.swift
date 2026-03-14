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
            await processWithSRT(source: source, srtURL: srtURL)
        } else {
            await processWithRecognition(source: source)
        }
    }
    
    /// SRT 付き：語音識別をスキップし、SRT を解析して振り仮名を生成する
    @MainActor
    private func processWithSRT(source: AudioSource, srtURL: URL) async {
        do {
            state = .parsingSRT
            
            let srtSegments = try SubtitleImportService.parseSRT(from: srtURL)
            guard !srtSegments.isEmpty else {
                state = .error(String(localized: "failed_to_parse_srt_file"))
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
            
            let doc = TranscriptDocument(source: source, segments: transcriptSegments)
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
            state = .error(String(localized: "failed_to_parse_srt_file"))
        }
    }
    
    /// 流程：远程则 解析链接 → 下载到本地 → Whisper 识别 → 假名；本地则直接识别。
    @MainActor
    private func processWithRecognition(source: AudioSource) async {
        do {
            let authorized = await speechService.requestAuthorization()
            guard authorized else {
                state = .error(String(localized: "speech_recognition_permission_denied_please_enable_it_in_settings"))
                return
            }

            guard let url = source.playbackURL else {
                state = .error(String(localized: "audio_url_not_found"))
                return
            }

            var tempDownloadURL: URL?
            let localAudioURL: URL
            if source.type == .remote {
                state = .resolvingRemoteSource
                let resolved = await RemoteMediaResolver.resolve(originalURL: url)
                guard resolved.isSupported, let audioURL = resolved.resolvedAudioURL else {
                    state = .error(String(localized: "podcast_link_unresolvable"))
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
                state = .error(String(localized: "could_not_recognize_speech_please_check_that_the_audio_contains_japanese_speech")
                    + (source.type == .remote ? "\n\n" + String(localized: "recognition_error_podcast_hint") : ""))
                return
            }

            state = .generatingFurigana
            var transcriptSegments: [TranscriptSegment] = []
            for segment in recognitionSegments {
                let tokens: [FuriganaToken]
                if segment.isJapanese {
                    tokens = await furiganaService.generateFurigana(for: segment.text)
                } else {
                    tokens = []
                }
                transcriptSegments.append(TranscriptSegment(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    originalText: segment.text,
                    tokens: tokens,
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

            let doc = TranscriptDocument(source: finalSource, segments: transcriptSegments)
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
            state = .error(Self.userFacingMessage(for: error))
        }
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

    private static func userFacingMessage(for error: Error) -> String {
        if let downloadErr = error as? DownloadError {
            return downloadErr.errorDescription ?? String(localized: "failed_to_download_audio")
        }
        if error is RemoteSourceError {
            return String(localized: "podcast_link_unresolvable")
        }
        let raw = error.localizedDescription
        let isRecognitionEmpty = raw.contains("空でした") || raw.contains("empty") || raw.contains("音声認識") || raw.contains("recognition")
        if isRecognitionEmpty {
            return String(localized: "could_not_recognize_speech_please_check_that_the_audio_contains_japanese_speech")
        }
        return raw
    }
}
