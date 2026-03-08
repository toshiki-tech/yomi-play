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
    
    /// 音声認識→振り仮名生成の処理フロー
    @MainActor
    private func process(source: AudioSource) async {
        do {
            // ステップ0: 音声認識の権限を確認
            state = .loadingAudio
            
            let authorized = await speechService.requestAuthorization()
            guard authorized else {
                state = .error("音声認識の権限がありません。設定アプリから音声認識を許可してください。")
                return
            }
            
            // ステップ1: 音声URLを取得
            guard let url = source.playbackURL else {
                state = .error("音声URLが見つかりません")
                return
            }
            
            print("ProcessingViewModel: 音声認識開始 URL=\(url)")
            
            // ステップ2: 音声認識
            state = .recognizing
            let recognitionSegments = try await speechService.recognize(audioURL: url)
            
            print("ProcessingViewModel: 認識完了 セグメント数=\(recognitionSegments.count)")
            
            guard !recognitionSegments.isEmpty else {
                state = .error("音声を認識できませんでした。音声ファイルに日本語の音声が含まれているか確認してください。")
                return
            }
            
            // ステップ3: 振り仮名生成
            state = .generatingFurigana
            var transcriptSegments: [TranscriptSegment] = []
            
            for segment in recognitionSegments {
                let tokens = await furiganaService.generateFurigana(for: segment.text)
                let transcriptSegment = TranscriptSegment(
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    originalText: segment.text,
                    tokens: tokens,
                    confidence: segment.confidence
                )
                transcriptSegments.append(transcriptSegment)
            }
            
            print("ProcessingViewModel: 振り仮名生成完了")
            
            // ステップ4: ドキュメントの作成
            let doc = TranscriptDocument(
                source: source,
                segments: transcriptSegments
            )
            
            document = doc
            state = .completed
            
            // ドキュメントを自動保存
            do {
                try DocumentStore.shared.save(doc)
                print("ProcessingViewModel: ドキュメント自動保存完了")
            } catch {
                print("ProcessingViewModel: 保存失敗: \(error)")
            }
            
            // 少し待ってから完了フラグを設定
            try? await Task.sleep(nanoseconds: 500_000_000)
            isCompleted = true
            
        } catch {
            print("ProcessingViewModel: エラー発生: \(error)")
            state = .error(error.localizedDescription)
        }
    }
}
