//
//  PlayerViewModel.swift
//  YomiPlay
//
//  プレーヤー画面のViewModel
//  再生制御・字幕同期・設定・字幕編集を管理する
//

import Foundation
import AVFoundation
import Translation

// MARK: - プレーヤー画面ViewModel

@MainActor
@Observable
final class PlayerViewModel {
    
    // MARK: - 公開プロパティ
    
    var document: TranscriptDocument
    var playerService: AudioPlayerService
    
    // 表示設定（UserDefaults で永続化）
    var showFurigana: Bool = true { didSet { Self.defaults.set(showFurigana, forKey: "showFurigana") } }
    var showRomaji: Bool = true { didSet { Self.defaults.set(showRomaji, forKey: "showRomaji") } }
    var showEnglish: Bool = true { didSet { Self.defaults.set(showEnglish, forKey: "showEnglish") } }
    var fontSize: CGFloat = 18 { didSet { Self.defaults.set(fontSize, forKey: "fontSize") } }
    var isLooping: Bool = false
    
    // 翻訳設定（UserDefaults で永続化）
    var targetLanguageCode: String = "zh-Hans" { didSet { Self.defaults.set(targetLanguageCode, forKey: "targetLanguageCode") } }
    var showTranslation: Bool = false { didSet { Self.defaults.set(showTranslation, forKey: "showTranslation") } }
    
    // 再生速度（UserDefaults で永続化）
    var playbackRate: Float = 1.0 { didSet { Self.defaults.set(playbackRate, forKey: "playbackRate") } }
    static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
    
    private static let defaults = UserDefaults.standard
    
    // 字幕編集
    var editingSegmentID: UUID? = nil
    var editingText: String = ""
    var editingSkipFurigana: Bool = false
    var editingStartTime: TimeInterval = 0
    var editingEndTime: TimeInterval = 0
    
    private let furiganaService = CFStringTokenizerFuriganaService()
    private let translationService = TranslationService.shared
    
    /// 翻訳中かどうか
    var isTranslating: Bool = false
    
    // MARK: - 初期化
    
    init(document: TranscriptDocument) {
        self.document = document
        self.playerService = AudioPlayerService()
        
        restoreSettings()
        
        if let url = document.source.playbackURL {
            playerService.loadAudio(from: url)
        }
        playerService.setSegments(document.segments)
        playerService.setPlaybackRate(playbackRate)
    }
    
    /// UserDefaults から保存済みの設定を復元する
    private func restoreSettings() {
        let d = Self.defaults
        
        if d.object(forKey: "showFurigana") != nil {
            showFurigana = d.bool(forKey: "showFurigana")
        }
        if d.object(forKey: "showRomaji") != nil {
            showRomaji = d.bool(forKey: "showRomaji")
        }
        if d.object(forKey: "showEnglish") != nil {
            showEnglish = d.bool(forKey: "showEnglish")
        }
        if d.object(forKey: "showTranslation") != nil {
            showTranslation = d.bool(forKey: "showTranslation")
        }
        if d.object(forKey: "fontSize") != nil {
            let stored = d.double(forKey: "fontSize")
            if stored >= 12 && stored <= 48 { fontSize = stored }
        }
        if d.object(forKey: "playbackRate") != nil {
            let stored = d.float(forKey: "playbackRate")
            if Self.availableRates.contains(stored) { playbackRate = stored }
        }
        
        if let stored = d.string(forKey: "targetLanguageCode"), !stored.isEmpty {
            targetLanguageCode = stored
        } else {
            targetLanguageCode = Self.detectDefaultLanguageCode()
        }
    }
    
    /// システム言語から翻訳先のデフォルト言語コードを推定する
    private static func detectDefaultLanguageCode() -> String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh-Hans") || preferred.hasPrefix("zh-CN") { return "zh-Hans" }
        if preferred.hasPrefix("zh-Hant") || preferred.hasPrefix("zh-TW") || preferred.hasPrefix("zh-HK") { return "zh-Hant" }
        if preferred.hasPrefix("en") { return "en" }
        return "zh-Hans"
    }
    
    // MARK: - 再生コントロール
    
    func togglePlayPause() {
        playerService.togglePlayPause()
    }
    
    func skipBackward() {
        playerService.skip(seconds: -5)
    }
    
    func skipForward() {
        playerService.skip(seconds: 10)
    }
    
    func seek(to time: TimeInterval) {
        playerService.seek(to: time)
    }
    
    // MARK: - 再生速度
    
    func cyclePlaybackRate() {
        guard let currentIndex = Self.availableRates.firstIndex(of: playbackRate) else {
            playbackRate = 1.0
            playerService.setPlaybackRate(1.0)
            return
        }
        let nextIndex = (currentIndex + 1) % Self.availableRates.count
        playbackRate = Self.availableRates[nextIndex]
        playerService.setPlaybackRate(playbackRate)
    }
    
    var playbackRateText: String {
        if playbackRate == 1.0 { return "1x" }
        if playbackRate == floor(playbackRate) { return "\(Int(playbackRate))x" }
        return String(format: "%.2gx", playbackRate)
    }
    
    // MARK: - 字幕操作
    
    func onSegmentTapped(_ segment: TranscriptSegment) {
        playerService.seek(to: segment.startTime)
        if !playerService.isPlaying {
            playerService.play()
        }
    }
    
    func toggleCurrentLoop() {
        if isLooping {
            isLooping = false
            playerService.setLoopSegment(nil)
        } else if let segmentID = playerService.currentSegmentID,
                  let segment = document.segments.first(where: { $0.id == segmentID }) {
            isLooping = true
            playerService.setLoopSegment(segment)
        }
    }
    
    // MARK: - 字幕編集
    
    /// 編集を開始する
    func startEditing(segment: TranscriptSegment) {
        editingSegmentID = segment.id
        editingText = segment.originalText
        editingSkipFurigana = segment.skipFurigana
        editingStartTime = segment.startTime
        editingEndTime = segment.endTime
    }
    
    /// 編集をキャンセルする
    func cancelEditing() {
        editingSegmentID = nil
        editingText = ""
        editingSkipFurigana = false
        editingStartTime = 0
        editingEndTime = 0
    }
    
    /// 編集を確定し、振り仮名を再生成する
    func confirmEditing() {
        guard let segmentID = editingSegmentID,
              let index = document.segments.firstIndex(where: { $0.id == segmentID }) else {
            print("PlayerViewModel: 編集対象が見つかりません id=\(String(describing: editingSegmentID))")
            cancelEditing()
            return
        }
        
        let newText = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else {
            print("PlayerViewModel: 空のテキストのため編集をキャンセルします")
            cancelEditing()
            return
        }
        
        let shouldSkip = editingSkipFurigana
        let segmentIndex = index
        let duration = playerService.duration
        let clampedStart = max(0, min(editingStartTime, duration))
        let clampedEnd = max(clampedStart, min(editingEndTime, duration > 0 ? duration : editingEndTime))
        
        print("PlayerViewModel: 編集を確定中... text=\(newText), skip=\(shouldSkip), start=\(clampedStart), end=\(clampedEnd)")
        
        Task {
            // 1. 新しい振り仮名を生成（非メインスレッド）
            let tokens: [FuriganaToken] = shouldSkip
                ? []
                : await furiganaService.generateFurigana(for: newText)
            
            // 2. メインスレッドでドキュメントを更新して保存
            await MainActor.run {
                // インデックスガード
                guard segmentIndex < self.document.segments.count else { return }
                
                // プロパティを個別に更新
                self.document.segments[segmentIndex].startTime = clampedStart
                self.document.segments[segmentIndex].endTime = clampedEnd
                self.document.segments[segmentIndex].originalText = newText
                self.document.segments[segmentIndex].tokens = tokens
                self.document.segments[segmentIndex].skipFurigana = shouldSkip
                self.document.segments[segmentIndex].translatedText = nil
                
                // 再生サービス側も同期
                self.playerService.setSegments(self.document.segments)
                
                // 編集状態リセット
                self.editingSegmentID = nil
                self.editingText = ""
                self.editingSkipFurigana = false
                self.editingStartTime = 0
                self.editingEndTime = 0
                
                // 即座に保存
                self.saveDocument()
                print("PlayerViewModel: 編集内容を適用して保存しました id=\(segmentID)")
            }
        }
    }
    
    /// 現在編集中の字幕を削除する
    func deleteCurrentSegment() {
        guard let segmentID = editingSegmentID,
              let index = document.segments.firstIndex(where: { $0.id == segmentID }) else {
            return
        }
        document.segments.remove(at: index)
        playerService.setSegments(document.segments)
        cancelEditing()
        saveDocument()
        print("PlayerViewModel: セグメントを削除しました id=\(segmentID)")
    }
    
    /// 現在の再生位置で字幕を二つに分割する
    func splitCurrentSegmentAtCurrentTime() {
        guard let segmentID = editingSegmentID,
              let index = document.segments.firstIndex(where: { $0.id == segmentID }) else {
            return
        }
        let segment = document.segments[index]
        let t = playerService.currentTime
        guard t > segment.startTime, t < segment.endTime else {
            print("PlayerViewModel: 分割位置がセグメント範囲外のため処理しません")
            return
        }
        
        let first = TranscriptSegment(
            id: segment.id,
            startTime: segment.startTime,
            endTime: t,
            originalText: segment.originalText,
            tokens: segment.tokens,
            confidence: segment.confidence,
            skipFurigana: segment.skipFurigana,
            translatedText: segment.translatedText
        )
        let second = TranscriptSegment(
            startTime: t,
            endTime: segment.endTime,
            originalText: segment.originalText,
            tokens: segment.tokens,
            confidence: segment.confidence,
            skipFurigana: segment.skipFurigana,
            translatedText: segment.translatedText
        )
        
        document.segments.remove(at: index)
        document.segments.insert(contentsOf: [first, second], at: index)
        playerService.setSegments(document.segments)
        
        // 新しい後半セグメントを編集中として扱う
        editingSegmentID = second.id
        editingStartTime = second.startTime
        editingEndTime = second.endTime
        editingText = second.originalText
        editingSkipFurigana = second.skipFurigana
        
        saveDocument()
        print("PlayerViewModel: セグメントを分割しました id=\(segmentID) at t=\(t)")
    }
    
    /// 現在編集中の字幕を前の字幕と結合する
    func mergeCurrentWithPrevious() {
        guard let segmentID = editingSegmentID,
              let index = document.segments.firstIndex(where: { $0.id == segmentID }),
              index > 0 else {
            return
        }
        
        let prev = document.segments[index - 1]
        let current = document.segments[index]
        
        let mergedStart = min(prev.startTime, current.startTime)
        let mergedEnd = max(prev.endTime, current.endTime)
        let mergedText = (prev.originalText + " " + current.originalText).trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldSkip = prev.skipFurigana && current.skipFurigana
        let targetIndex = index - 1
        
        Task {
            let tokens: [FuriganaToken] = shouldSkip
                ? []
                : await furiganaService.generateFurigana(for: mergedText)
            
            await MainActor.run {
                guard targetIndex < self.document.segments.count else { return }
                self.document.segments[targetIndex].startTime = mergedStart
                self.document.segments[targetIndex].endTime = mergedEnd
                self.document.segments[targetIndex].originalText = mergedText
                self.document.segments[targetIndex].tokens = tokens
                self.document.segments[targetIndex].skipFurigana = shouldSkip
                self.document.segments[targetIndex].translatedText = nil
                
                // 現在のセグメントを削除
                if index < self.document.segments.count {
                    self.document.segments.remove(at: index)
                }
                
                self.playerService.setSegments(self.document.segments)
                
                // 結合後のセグメントを編集中として扱う
                self.editingSegmentID = self.document.segments[targetIndex].id
                self.editingStartTime = mergedStart
                self.editingEndTime = mergedEnd
                self.editingText = mergedText
                self.editingSkipFurigana = shouldSkip
                
                self.saveDocument()
                print("PlayerViewModel: セグメントを結合しました prev=\(prev.id), current=\(segmentID)")
            }
        }
    }
    
    // MARK: - 字幕翻訳
    
    /// 翻訳を開始するためのトリガー（SwiftUI .translationTask で監視）
    var translationConfiguration: TranslationSession.Configuration?
    
    /// 翻訳ボタンを押したとき：Configuration を設定して .translationTask を発火させる
    func requestTranslation() {
        translationConfiguration = nil
        isTranslating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
            translationConfiguration = translationService.makeConfiguration(
                sourceLanguageCode: "ja",
                targetLanguageCode: targetLanguageCode
            )
        }
    }
    
    /// .translationTask のコールバックで呼ばれる
    @MainActor
    func performTranslation(using session: TranslationSession) async {
        let segments = document.segments
        guard !segments.isEmpty else {
            isTranslating = false
            return
        }
        
        let requests = segments.enumerated().map { index, seg in
            TranslationSession.Request(
                sourceText: seg.originalText,
                clientIdentifier: "\(index)"
            )
        }
        
        do {
            let responses = try await session.translations(from: requests)
            for response in responses {
                if let idStr = response.clientIdentifier,
                   let idx = Int(idStr),
                   idx < document.segments.count {
                    document.segments[idx].translatedText = response.targetText
                }
            }
            saveDocument()
            showTranslation = true
        } catch {
            print("PlayerViewModel: 翻訳失敗 - \(error)")
        }
        isTranslating = false
    }
    
    // MARK: - SRT インポート
    
    var isImportingSRT: Bool = false
    var showSRTImportSuccess: Bool = false
    
    /// SRT ファイルをインポートして現在の字幕を置き換える
    func importSRT(from url: URL) {
        isImportingSRT = true
        Task {
            do {
                let srtSegments = try SubtitleImportService.parseSRT(from: url)
                guard !srtSegments.isEmpty else {
                    await MainActor.run { isImportingSRT = false }
                    return
                }
                
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
                
                await MainActor.run {
                    document.segments = transcriptSegments
                    playerService.setSegments(document.segments)
                    saveDocument()
                    isImportingSRT = false
                    showSRTImportSuccess = true
                    print("PlayerViewModel: SRT インポート完了 \(transcriptSegments.count) セグメント")
                }
            } catch {
                await MainActor.run {
                    isImportingSRT = false
                    print("PlayerViewModel: SRT インポート失敗: \(error)")
                }
            }
        }
    }
    
    // MARK: - .yomi インポート
    
    var isImportingYomi: Bool = false
    var showYomiImportSuccess: Bool = false
    
    /// .yomi ファイルをインポートして現在の字幕を置き換える
    func importYomi(from url: URL) {
        isImportingYomi = true
        Task {
            do {
                let importedDoc = try SubtitleExportService.readYomiFile(from: url)
                await MainActor.run {
                    document.segments = importedDoc.segments
                    playerService.setSegments(document.segments)
                    saveDocument()
                    isImportingYomi = false
                    showYomiImportSuccess = true
                    print("PlayerViewModel: .yomi インポート完了 \(importedDoc.segments.count) セグメント")
                }
            } catch {
                await MainActor.run {
                    isImportingYomi = false
                    print("PlayerViewModel: .yomi インポート失敗: \(error)")
                }
            }
        }
    }
    
    /// ドキュメントを保存する
    func saveDocument() {
        do {
            try DocumentStore.shared.save(document)
            print("PlayerViewModel: ドキュメント保存完了")
        } catch {
            print("PlayerViewModel: 保存失敗: \(error)")
        }
    }
    
    /// 現在の再生位置をドキュメントに保存する（画面を出るときに呼ぶ）
    func savePlaybackPosition() {
        document.lastPlaybackPosition = playerService.currentTime
        saveDocument()
    }
    
    // MARK: - 設定
    
    func adjustFontSize(by delta: CGFloat) {
        fontSize = max(12, min(48, fontSize + delta))
    }
    
    // MARK: - ヘルパー
    
    var isPlaying: Bool { playerService.isPlaying }
    
    var progress: Double {
        guard playerService.duration > 0 else { return 0 }
        return playerService.currentTime / playerService.duration
    }
}
