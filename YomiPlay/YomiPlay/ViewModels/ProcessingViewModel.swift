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
                let tokens = await furiganaService.generateFurigana(for: seg.text)
                transcriptSegments.append(TranscriptSegment(
                    startTime: seg.startTime,
                    endTime: seg.endTime,
                    originalText: seg.text,
                    tokens: tokens
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
    
    /// 通常フロー：音声認識→振り仮名生成
    @MainActor
    private func processWithRecognition(source: AudioSource) async {
        do {
            state = .loadingAudio
            
            let authorized = await speechService.requestAuthorization()
            guard authorized else {
                state = .error(String(localized: "speech_recognition_permission_denied_please_enable_it_in_settings"))
                return
            }
            
            guard let url = source.playbackURL else {
                state = .error(String(localized: "audio_url_not_found"))
                return
            }
            
            print("ProcessingViewModel: 音声認識開始 URL=\(url)")
            
            state = .recognizing
            let recognitionSegments = try await speechService.recognize(audioURL: url)
            
            print("ProcessingViewModel: 認識完了 セグメント数=\(recognitionSegments.count)")
            
            guard !recognitionSegments.isEmpty else {
                state = .error(String(localized: "could_not_recognize_speech_please_check_that_the_audio_contains_japanese_speech"))
                return
            }
            
            state = .generatingFurigana
            var transcriptSegments: [TranscriptSegment] = []
            
            for segment in recognitionSegments {
                let tokens = await furiganaService.generateFurigana(for: segment.text)
                transcriptSegments.append(TranscriptSegment(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    originalText: segment.text,
                    tokens: tokens,
                    confidence: segment.confidence
                ))
            }
            
            print("ProcessingViewModel: 振り仮名生成完了")
            
            let doc = TranscriptDocument(source: source, segments: transcriptSegments)
            document = doc
            state = .completed
            
            do {
                try DocumentStore.shared.save(doc)
                print("ProcessingViewModel: ドキュメント自動保存完了")
            } catch {
                print("ProcessingViewModel: 保存失敗: \(error)")
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000)
            isCompleted = true
            
        } catch {
            print("ProcessingViewModel: エラー発生: \(error)")
            state = .error(error.localizedDescription)
        }
    }
}
